use std::sync::Arc;

use anyhow::{anyhow, Result};
use chrono::Utc;
use serde_json::json;
use tracing::instrument;
use uuid::Uuid;

use contracts::events::mdm_events::MDMEventPayload;
use contracts::mdm::entity::{CanonicalEntity, EntityStatus};
use contracts::mdm::merge::{MergeExecutionResult, MergeRequest};
use contracts::mdm::survivorship::{SurvivorshipRule, SurvivorshipScope, SurvivorshipStatus, SurvivorshipStrategy};
use database::{DbPool, PendingOutboxEvent, RequestContext, RequestContextFactory};
use azile_redis::{TaskQueue, queue::task_types};

use crate::db::repositories::entity_repository::EntityRepository;
use crate::db::repositories::golden_record_repository::GoldenRecordRepository;
use crate::survivorship::engine::apply_survivorship;

/// Executes the merge pipeline: survivorship evaluation â†’ golden record
/// creation â†’ entity status update â†’ outbox events, all within a single
/// tenant-scoped PostgreSQL transaction with RLS context set.
pub struct MergeService {
    pool:                     DbPool,
    entity_repository:        Arc<EntityRepository>,
    golden_record_repository: Arc<GoldenRecordRepository>,
    /// Optional Redis task queue for triggering re-embedding after merge.
    task_queue:               Option<Arc<TaskQueue>>,
}

impl MergeService {
    pub fn new(
        pool:                     DbPool,
        entity_repository:        Arc<EntityRepository>,
        golden_record_repository: Arc<GoldenRecordRepository>,
    ) -> Self {
        Self { pool, entity_repository, golden_record_repository, task_queue: None }
    }

    pub fn with_task_queue(mut self, task_queue: Arc<TaskQueue>) -> Self {
        self.task_queue = Some(task_queue);
        self
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

        // â”€â”€ Load primary entity â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        let primary = self
            .entity_repository
            .fetch_entity(tenant_id, request.primary_entity_id)
            .await?
            .ok_or_else(|| anyhow!("primary entity {} not found", request.primary_entity_id))?;

        // â”€â”€ Load candidate entities â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

        // â”€â”€ Survivorship â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        // Load active rules from the DB so configured strategies (TrustedSource,
        // MostRecent, HybridWeighted, etc.) are applied. Falls back to the
        // engine's built-in latest-wins default when no rules exist.
        let rules = load_survivorship_rules(&self.pool, tenant_id).await
            .unwrap_or_else(|e| {
                tracing::warn!(error=%e, “failed to load survivorship rules — using default latest-wins”);
                vec![]
            });
        let golden = apply_survivorship(entities.clone(), rules);

        // â”€â”€ Atomic write with tenant RLS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

        // Link primary entity â†’ golden record
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

        // After a successful merge the surviving entity's attributes may have
        // changed via survivorship. Re-queue an embedding task so the vector
        // index stays in sync.
        let embeddings_regenerated = if let Some(queue) = &self.task_queue {
            let task = azile_redis::queue::Task::new(
                task_types::ENTITY_EMBED,
                tenant_id.to_string(),
                json!({
                    "entity_id":  primary.entity_id,
                    "tenant_id":  tenant_id,
                    "attributes": primary.attributes,
                }),
            );
            match queue.enqueue(task_types::ENTITY_EMBED, &task).await {
                Ok(_)  => true,
                Err(e) => {
                    tracing::warn!(
                        entity_id=%primary.entity_id,
                        error=%e,
                        "embed re-queue after merge failed"
                    );
                    false
                }
            }
        } else {
            false
        };

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
            embeddings_regenerated,
            metadata:                 Default::default(),
        })
    }
}

// ── Survivorship rules loader ────────────────────────────────────────────────

async fn load_survivorship_rules(pool: &DbPool, tenant_id: Uuid) -> Result<Vec<SurvivorshipRule>> {
    use sqlx::Row;

    let rows = sqlx::query(
        r#"
        SELECT rule_id, rule_name, description, attribute_name, strategy, scope,
               source_priority, source_weights, minimum_confidence, ai_assisted,
               explainability_enabled, allow_manual_override, status, priority,
               effective_from, effective_to, created_by, metadata
        FROM core_mdm.survivorship_rules
        WHERE tenant_id = $1
          AND status = 'active'
          AND (effective_from IS NULL OR effective_from <= NOW())
          AND (effective_to   IS NULL OR effective_to   >  NOW())
        ORDER BY priority DESC
        "#,
    )
    .bind(tenant_id)
    .fetch_all(pool)
    .await?;

    let rules = rows.iter().map(|row| {
        let strategy_str: String = row.get("strategy");
        let strategy = serde_json::from_value(serde_json::Value::String(strategy_str))
            .unwrap_or(SurvivorshipStrategy::MostRecent);

        let scope_str: String = row.get("scope");
        let scope = serde_json::from_value(serde_json::Value::String(scope_str))
            .unwrap_or(SurvivorshipScope::Tenant);

        let status_str: String = row.get("status");
        let status = serde_json::from_value(serde_json::Value::String(status_str))
            .unwrap_or(SurvivorshipStatus::Active);

        let source_priority: Vec<String> = row
            .get::<sqlx::types::Json<Vec<String>>, _>("source_priority")
            .0;

        SurvivorshipRule {
            rule_id:               row.get("rule_id"),
            rule_name:             row.get("rule_name"),
            description:           row.get("description"),
            attribute:             row.get("attribute_name"),
            strategy,
            scope,
            source_priority,
            source_weights:        Default::default(),
            minimum_confidence:    row.get::<Option<f64>, _>("minimum_confidence").map(|v| v as f32),
            ai_assisted:           row.get("ai_assisted"),
            explainability_enabled: row.get("explainability_enabled"),
            allow_manual_override: row.get("allow_manual_override"),
            status,
            priority:              row.get("priority"),
            effective_from:        row.get("effective_from"),
            effective_to:          row.get("effective_to"),
            created_by:            row.get("created_by"),
            audit:                 Default::default(),
            metadata:              Default::default(),
        }
    }).collect();

    Ok(rules)
}
