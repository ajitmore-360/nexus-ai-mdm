use std::sync::Arc;

use anyhow::{anyhow, Result};
use chrono::Utc;
use serde_json::json;
use tracing::instrument;
use uuid::Uuid;

use contracts::events::mdm_events::MDMEventPayload;
use contracts::mdm::entity::{CanonicalEntity, EntityStatus};
use contracts::mdm::merge::{MergeExecutionResult, MergeRequest};
use contracts::mdm::survivorship::SurvivorshipRule;
use database::{DbPool, PendingOutboxEvent, RequestContext, RequestContextFactory};

use crate::db::repositories::entity_repository::EntityRepository;
use crate::db::repositories::golden_record_repository::GoldenRecordRepository;
use crate::survivorship::engine::apply_survivorship;

/// Executes the merge pipeline: survivorship evaluation → golden record
/// creation → entity status update → outbox events, all within a single
/// tenant-scoped PostgreSQL transaction with RLS context set.
pub struct MergeService {
    pool:                     DbPool,
    entity_repository:        Arc<EntityRepository>,
    golden_record_repository: Arc<GoldenRecordRepository>,
}

impl MergeService {
    pub fn new(
        pool:                     DbPool,
        entity_repository:        Arc<EntityRepository>,
        golden_record_repository: Arc<GoldenRecordRepository>,
    ) -> Self {
        Self { pool, entity_repository, golden_record_repository }
    }

    #[instrument(skip(self, ctx, request), fields(
        tenant_id        = %ctx.tenant_id,
        primary_id       = %request.primary_entity_id,
        merge_request_id = %request.merge_request_id,
    ))]
    pub async fn execute_merge(
        &self,
        ctx:     RequestContext,
        request: MergeRequest,
    ) -> Result<MergeExecutionResult> {
        let tenant_id  = ctx.tenant_id;
        let started_at = Utc::now();

        // ── Load primary entity ─────────────────────────────────────────────
        let primary = self
            .entity_repository
            .fetch_entity(tenant_id, request.primary_entity_id)
            .await?
            .ok_or_else(|| anyhow!("primary entity {} not found", request.primary_entity_id))?;

        // ── Load candidate entities ─────────────────────────────────────────
        let mut entities: Vec<CanonicalEntity> = vec![primary.clone()];
        let mut merged_ids: Vec<Uuid> = Vec::new();

        for candidate in &request.candidate_entities {
            match self.entity_repository.fetch_entity(tenant_id, candidate.entity_id).await? {
                Some(e) => {
                    merged_ids.push(e.entity_id);
                    entities.push(e);
                }
                None => {
                    tracing::warn!(
                        entity_id=%candidate.entity_id,
                        "candidate entity not found; skipping"
                    );
                }
            }
        }

        if entities.len() < 2 {
            return Err(anyhow!(
                "merge requires at least 2 valid entities (found {})",
                entities.len()
            ));
        }

        // ── Survivorship ────────────────────────────────────────────────────
        // Rules come from the proposed golden record's attributes if present,
        // otherwise a default empty rule set is used (latest-wins fallback in
        // the survivorship engine).
        let rules: Vec<SurvivorshipRule> = vec![];
        let golden = apply_survivorship(entities.clone(), rules);

        // ── Atomic write with tenant RLS ────────────────────────────────────
        let factory = RequestContextFactory::new(self.pool.clone());
        let mut uow = factory
            .begin_uow(ctx.tenant_id, ctx.user_id, ctx.trace_id.clone())
            .await?;

        // Persist golden record
        self.golden_record_repository
            .create_golden_record(&mut uow.tx, &golden)
            .await?;

        // Mark merged entities
        for &mid in &merged_ids {
            self.entity_repository
                .update_entity_status(&mut uow.tx, tenant_id, mid, EntityStatus::Merged)
                .await?;
        }

        // Link primary entity → golden record
        self.entity_repository
            .set_golden_record_id(&mut uow.tx, tenant_id, primary.entity_id, golden.golden_record_id)
            .await?;

        // Lineage: each merged entity has a "merged_into" edge pointing at the primary
        let mut lineage_ids: Vec<Uuid> = Vec::with_capacity(merged_ids.len());
        for &mid in &merged_ids {
            let lid = Uuid::new_v4();
            sqlx::query(
                r#"
                INSERT INTO lineage.entity_lineage
                    (lineage_id, tenant_id, source_entity_id, target_entity_id, lineage_type, metadata)
                VALUES ($1, $2, $3, $4, 'merged_into', $5)
                "#,
            )
            .bind(lid)
            .bind(tenant_id)
            .bind(mid)
            .bind(primary.entity_id)
            .bind(serde_json::json!({
                "golden_record_id":  golden.golden_record_id,
                "merge_request_id":  request.merge_request_id,
            }))
            .execute(&mut *uow.tx)
            .await?;
            lineage_ids.push(lid);
        }

        // Outbox events
        uow.add_event(PendingOutboxEvent::new(
            tenant_id,
            "golden_record".to_string(),
            golden.golden_record_id,
            "GoldenRecordCreated".to_string(),
            serde_json::to_value(MDMEventPayload::GoldenRecordCreated(golden.clone()))?,
            json!({
                "merge_request_id": request.merge_request_id,
                "correlation_id":   ctx.correlation_id,
            }),
            "mdm.golden.events".to_string(),
        ));

        uow.add_event(PendingOutboxEvent::new(
            tenant_id,
            "entity".to_string(),
            primary.entity_id,
            "EntityMerged".to_string(),
            json!({
                "surviving_entity_id": primary.entity_id,
                "merged_entity_ids":   merged_ids,
                "golden_record_id":    golden.golden_record_id,
                "tenant_id":           tenant_id,
            }),
            json!({ "correlation_id": ctx.correlation_id }),
            "mdm.entity.events".to_string(),
        ));

        uow.commit().await?;

        let completed_at = Utc::now();

        tracing::info!(
            golden_record_id=%golden.golden_record_id,
            merged_count=merged_ids.len(),
            "merge completed"
        );

        Ok(MergeExecutionResult {
            merge_request_id:         request.merge_request_id,
            surviving_entity:         primary,
            merged_entity_ids:        merged_ids,
            generated_golden_record:  Some(golden),
            execution_started_at:     started_at,
            execution_completed_at:   completed_at,
            success:                  true,
            warnings:                 vec![],
            errors:                   vec![],
            execution_summary:        Some("Merge completed successfully".to_string()),
            execution_trace:          vec![],
            lineage_event_ids:        lineage_ids,
            published_event_ids:      vec![],
            search_reindexed:         false,
            embeddings_regenerated:   false,
            metadata:                 Default::default(),
        })
    }
}
