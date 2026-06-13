use anyhow::Result;
use tracing::instrument;
use uuid::Uuid;

use contracts::mdm::matching::MatchCandidate;
use database::{DbPool, PendingOutboxEvent, RequestContext, RequestContextFactory};

use crate::db::repositories::matching_repository::MatchingRepository;

/// Manages the human stewardship review queue.
///
/// Stewards call `get_queue` to see pending review cases, then either
/// `approve` or `reject` each one.  Both approval and rejection emit outbox
/// events so downstream systems (ai-service feedback, audit trail) stay
/// in sync.
pub struct ReviewService {
    pool:                DbPool,
    matching_repository: std::sync::Arc<MatchingRepository>,
}

impl ReviewService {
    pub fn new(
        pool:                DbPool,
        matching_repository: std::sync::Arc<MatchingRepository>,
    ) -> Self {
        Self { pool, matching_repository }
    }

    /// Return pending review cases for the tenant, newest first.
    pub async fn get_queue(
        &self,
        tenant_id: Uuid,
        limit:     i64,
        offset:    i64,
    ) -> Result<Vec<MatchCandidate>> {
        self.matching_repository
            .fetch_review_queue(tenant_id, limit, offset)
            .await
            .map_err(Into::into)
    }

    /// Steward approves a match — mark it as Matched and emit a feedback event.
    #[instrument(skip(self, ctx), fields(tenant_id=%ctx.tenant_id))]
    pub async fn approve(
        &self,
        ctx:          RequestContext,
        request_id:   Uuid,
        candidate_id: Uuid,
        notes:        Option<String>,
    ) -> Result<()> {
        let factory = RequestContextFactory::new(self.pool.clone());
        let mut uow = factory
            .begin_uow(ctx.tenant_id, ctx.user_id, ctx.trace_id.clone())
            .await?;

        self.matching_repository
            .update_candidate_status(&mut uow.tx, ctx.tenant_id, request_id, candidate_id, "Matched")
            .await?;

        uow.add_event(PendingOutboxEvent::new(
            ctx.tenant_id,
            "match_review".to_string(),
            request_id,
            "MatchApprovedByHuman".to_string(),
            serde_json::json!({
                "request_id":   request_id,
                "candidate_id": candidate_id,
                "steward_id":   ctx.user_id,
                "notes":        notes,
                "tenant_id":    ctx.tenant_id,
            }),
            serde_json::json!({ "correlation_id": ctx.correlation_id }),
            "mdm.match.events".to_string(),
        ));

        uow.commit().await?;
        Ok(())
    }

    /// Steward rejects a match — mark it as Rejected and emit a feedback event.
    #[instrument(skip(self, ctx), fields(tenant_id=%ctx.tenant_id))]
    pub async fn reject(
        &self,
        ctx:          RequestContext,
        request_id:   Uuid,
        candidate_id: Uuid,
        notes:        Option<String>,
    ) -> Result<()> {
        let factory = RequestContextFactory::new(self.pool.clone());
        let mut uow = factory
            .begin_uow(ctx.tenant_id, ctx.user_id, ctx.trace_id.clone())
            .await?;

        self.matching_repository
            .update_candidate_status(&mut uow.tx, ctx.tenant_id, request_id, candidate_id, "Rejected")
            .await?;

        uow.add_event(PendingOutboxEvent::new(
            ctx.tenant_id,
            "match_review".to_string(),
            request_id,
            "MatchRejectedByHuman".to_string(),
            serde_json::json!({
                "request_id":   request_id,
                "candidate_id": candidate_id,
                "steward_id":   ctx.user_id,
                "notes":        notes,
                "tenant_id":    ctx.tenant_id,
            }),
            serde_json::json!({ "correlation_id": ctx.correlation_id }),
            "mdm.match.events".to_string(),
        ));

        uow.commit().await?;
        Ok(())
    }
}
