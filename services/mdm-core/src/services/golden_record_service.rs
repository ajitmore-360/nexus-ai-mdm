use std::sync::Arc;

use anyhow::Result;
use tracing::instrument;
use uuid::Uuid;

use contracts::mdm::golden_record::{GoldenRecord, GoldenRecordLifecycleStage};
use database::{DbPool, RequestContext, RequestContextFactory};

use crate::db::repositories::golden_record_repository::GoldenRecordRepository;

pub struct GoldenRecordService {
    pool:                     DbPool,
    golden_record_repository: Arc<GoldenRecordRepository>,
}

impl GoldenRecordService {
    pub fn new(
        pool:                     DbPool,
        golden_record_repository: Arc<GoldenRecordRepository>,
    ) -> Self {
        Self { pool, golden_record_repository }
    }

    /// Fetch a single golden record by id.
    pub async fn get(
        &self,
        tenant_id:        Uuid,
        golden_record_id: Uuid,
    ) -> Result<Option<GoldenRecord>> {
        self.golden_record_repository
            .fetch_golden_record(tenant_id, golden_record_id)
            .await
    }

    /// List golden records for a tenant with optional type filter.
    pub async fn list(
        &self,
        tenant_id:   Uuid,
        entity_type: Option<&str>,
        limit:       i64,
        offset:      i64,
    ) -> Result<Vec<GoldenRecord>> {
        self.golden_record_repository
            .list_golden_records(tenant_id, entity_type, limit, offset)
            .await
    }

    /// Advance a golden record to Published lifecycle stage and emit an outbox event.
    #[instrument(skip(self, ctx), fields(tenant_id=%ctx.tenant_id, golden_record_id=%golden_record_id))]
    pub async fn publish(
        &self,
        ctx:              RequestContext,
        golden_record_id: Uuid,
    ) -> Result<()> {
        let factory = RequestContextFactory::new(self.pool.clone());
        let mut uow = factory
            .begin_uow(ctx.tenant_id, ctx.user_id, ctx.trace_id.clone())
            .await?;

        self.golden_record_repository
            .update_lifecycle_stage(
                &mut uow.tx,
                ctx.tenant_id,
                golden_record_id,
                GoldenRecordLifecycleStage::Published,
            )
            .await?;

        uow.add_event(database::PendingOutboxEvent::new(
            ctx.tenant_id,
            "golden_record".to_string(),
            golden_record_id,
            "GoldenRecordPublished".to_string(),
            serde_json::json!({ "golden_record_id": golden_record_id, "tenant_id": ctx.tenant_id }),
            serde_json::json!({ "correlation_id": ctx.correlation_id }),
            "mdm.golden.events".to_string(),
        ));

        uow.commit().await?;
        Ok(())
    }

    /// Archive a golden record (soft-remove from active set).
    #[instrument(skip(self, ctx), fields(tenant_id=%ctx.tenant_id, golden_record_id=%golden_record_id))]
    pub async fn archive(
        &self,
        ctx:              RequestContext,
        golden_record_id: Uuid,
    ) -> Result<()> {
        let factory = RequestContextFactory::new(self.pool.clone());
        let mut uow = factory
            .begin_uow(ctx.tenant_id, ctx.user_id, ctx.trace_id.clone())
            .await?;

        self.golden_record_repository
            .update_lifecycle_stage(
                &mut uow.tx,
                ctx.tenant_id,
                golden_record_id,
                GoldenRecordLifecycleStage::Archived,
            )
            .await?;

        uow.commit().await?;
        Ok(())
    }
}
