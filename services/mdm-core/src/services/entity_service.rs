use std::sync::Arc;

use anyhow::{anyhow, Result};
use chrono::Utc;
use serde_json::json;
use tracing::instrument;
use uuid::Uuid;

use contracts::events::mdm_events::MDMEventPayload;
use contracts::mdm::distribution::{
    CreateEntityRequest, CreateEntityResponse, DistributionRequest, EntityRecordOrigin,
};
use contracts::mdm::entity::{EntitySourceSnapshot, EntityStatus};

use database::{DbPool, PendingOutboxEvent, RequestContext, RequestContextFactory};
use nexus_redis::{EntityCache, TaskQueue, queue::task_types};

use crate::db::repositories::entity_repository::EntityRepository;

/// Service responsible for the full entity creation lifecycle:
///
/// 1. Idempotency check (Redis cache-aside → DB fallback)
/// 2. Domain validation
/// 3. Open a PostgreSQL transaction with tenant RLS context set
/// 4. Persist entity
/// 5. Store in Redis cache
/// 6. Enqueue outbox events atomically inside the same transaction (UoW)
/// 7. Optionally enqueue an async embedding task via Redis
/// 8. Commit
pub struct EntityService {
    pool:              DbPool,
    entity_repository: Arc<EntityRepository>,
    /// Optional Redis task queue — if absent, embeddings are skipped silently.
    task_queue:        Option<Arc<TaskQueue>>,
    /// Optional Redis entity cache — if absent, every read hits PostgreSQL.
    entity_cache:      Option<Arc<EntityCache>>,
}

impl EntityService {
    pub fn new(
        pool:              DbPool,
        entity_repository: Arc<EntityRepository>,
        task_queue:        Option<Arc<TaskQueue>>,
    ) -> Self {
        Self { pool, entity_repository, task_queue, entity_cache: None }
    }

    pub fn with_cache(mut self, cache: Arc<EntityCache>) -> Self {
        self.entity_cache = Some(cache);
        self
    }

    /// Optionally attach a cache — passes through `None` gracefully.
    pub fn with_cache_opt(mut self, cache: Option<Arc<EntityCache>>) -> Self {
        self.entity_cache = cache;
        self
    }

    /// Create or idempotently retrieve a canonical entity.
    ///
    /// The caller must supply a `RequestContext` built from the inbound HTTP
    /// request headers so that the correct tenant/trace context is propagated
    /// into the PostgreSQL session variables used by RLS policies.
    #[instrument(skip(self, ctx, request), fields(
        tenant_id  = %ctx.tenant_id,
        request_id = %ctx.request_id,
    ))]
    pub async fn create_entity(
        &self,
        ctx:     RequestContext,
        request: CreateEntityRequest,
    ) -> Result<CreateEntityResponse> {
        let mut entity = request.entity;

        // Assign a stable id if the caller omitted one
        if entity.entity_id.is_nil() {
            entity.entity_id = Uuid::new_v4();
        }

        if matches!(entity.status, EntityStatus::Deleted) {
            return Err(anyhow!("cannot create entity with deleted status"));
        }

        // ── Idempotency ─────────────────────────────────────────────────────
        // A client that retries on network failure must not create a duplicate.
        // If the id was provided and already exists, return the existing record.
        if !entity.entity_id.is_nil() && self
            .entity_repository
            .fetch_entity(entity.tenant_id, entity.entity_id)
            .await?
            .is_some()
        {
            tracing::debug!(entity_id=%entity.entity_id, "idempotent entity create — returning existing");
            return Ok(CreateEntityResponse {
                entity_id:         entity.entity_id,
                distribution_id:   None,
                outbox_event_ids:  vec![],
            });
        }

        // ── Auto-assign business number ────────────────────────────────────────
        // If no business number is present, auto-generate one from the sequence.
        // This assigns CUST-000001, VEND-000001, PROD-000001, etc.
        let entity_type_str = format!("{:?}", entity.entity_type);
        let number_key = format!("{}_number", entity_type_str.to_lowercase());

        let needs_number = !entity.attributes.iter().any(|a| {
            a.key == number_key
                || a.key == format!("{}_number", entity_type_str.to_lowercase())
                || a.key == "customer_number"
                || a.key == "vendor_number"
                || a.key == "product_number"
                || a.key == "material_number"
                || a.key == "employee_id"
                || a.key == "location_code"
        });

        if needs_number {
            // Attempt to get next number from sequence table (non-fatal if missing)
            if let Ok(Some(number)) = sqlx::query_scalar::<_, String>(
                "SELECT core_mdm.next_entity_number($1, $2) WHERE EXISTS \
                 (SELECT 1 FROM core_mdm.entity_sequences WHERE tenant_id=$1 AND entity_type=$2)"
            )
            .bind(entity.tenant_id)
            .bind(&entity_type_str)
            .fetch_optional(&self.pool)
            .await
            {
                entity.attributes.push(contracts::mdm::entity::EntityAttribute {
                    attribute_id:          Uuid::new_v4(),
                    key:                   number_key.clone(),
                    value:                 serde_json::Value::String(number.clone()),
                    data_type:             "string".to_string(),
                    confidence:            None,
                    provenance:            None,
                    policy_tags:           vec![],
                    semantic_type:         Some("business_number".to_string()),
                    aliases:               vec![],
                    embedding_ref:         None,
                    ai_annotations:        vec![],
                    searchable:            true,
                    indexed:               true,
                    encrypted:             false,
                    survivorship_eligible: false,
                    updated_at:            Some(chrono::Utc::now()),
                    attribute_version:     1,
                    metadata:              Default::default(),
                });
                tracing::debug!(entity_id=%entity.entity_id, business_number=%number, "auto-assigned business number");
            }
        }

        // ── Origin enrichment ───────────────────────────────────────────────
        if request.record_origin == EntityRecordOrigin::MdmAuthoritative {
            entity.metadata.insert(
                "record_origin".to_string(),
                json!("mdm_authoritative"),
            );
            entity.source_snapshots.push(EntitySourceSnapshot {
                source_system:     "nexus-mdm".to_string(),
                source_entity_id:  entity.entity_id.to_string(),
                payload_reference: None,
                extracted_at:      Some(Utc::now()),
                metadata:          Default::default(),
            });
        }

        // ── Transactional write with RLS context ────────────────────────────
        // begin_uow() sets app.current_tenant, app.request_id,
        // app.correlation_id, app.trace_id, app.current_user_id on the
        // PostgreSQL session before any DML so RLS policies can filter correctly.
        let factory = RequestContextFactory::new(self.pool.clone());
        let mut uow = factory
            .begin_uow(ctx.tenant_id, ctx.user_id, ctx.trace_id.clone())
            .await?;

        self.entity_repository
            .create_entity(&mut uow.tx, &entity)
            .await?;

        // EntityCreated outbox event
        let created_payload = serde_json::to_value(
            MDMEventPayload::EntityCreated(entity.clone())
        )?;

        let created_event_id = Uuid::new_v4();
        uow.add_event(PendingOutboxEvent::new(
            entity.tenant_id,
            "entity".to_string(),
            entity.entity_id,
            "EntityCreated".to_string(),
            created_payload,
            json!({
                "correlation_id": ctx.correlation_id,
                "trace_id":       ctx.trace_id,
                "user_id":        ctx.user_id,
            }),
            "mdm.entity.events".to_string(),
        ));

        // Optional distribution event
        let mut distribution_id = None;

        if request.distribute {
            let dist_id = Uuid::new_v4();
            distribution_id = Some(dist_id);

            let distribution = DistributionRequest {
                distribution_id:      dist_id,
                tenant_id:            entity.tenant_id,
                entity_id:            entity.entity_id,
                correlation_id:       entity.audit.correlation_id,
                targets:              request.distribution_targets,
                publish_golden_record: false,
                metadata:             Default::default(),
            };

            let dist_payload = serde_json::to_value(
                MDMEventPayload::EntityDistributionRequested(distribution)
            )?;

            uow.add_event(PendingOutboxEvent::new(
                entity.tenant_id,
                "entity".to_string(),
                entity.entity_id,
                "EntityDistributionRequested".to_string(),
                dist_payload,
                json!({ "correlation_id": ctx.correlation_id }),
                "mdm.entity.distribution".to_string(),
            ));
        }

        uow.commit().await?;

        // ── Redis entity cache (write-through) ──────────────────────────────
        // Store immediately after commit so subsequent reads are cache hits.
        if let Some(cache) = &self.entity_cache {
            if let Err(e) = cache.set_entity(entity.tenant_id, entity.entity_id, &entity).await {
                tracing::warn!(
                    entity_id=%entity.entity_id,
                    error=%e,
                    "entity cache write failed — entity created but not cached"
                );
            }
        }

        // ── Async embedding ─────────────────────────────────────────────────
        // Enqueue a low-priority task so the ai-service can embed this entity's
        // attributes into pgvector.  This is fire-and-forget; failure is logged
        // but does not fail the create response.
        if let Some(queue) = &self.task_queue {
            let task = nexus_redis::queue::Task::new(
                task_types::ENTITY_EMBED,
                entity.tenant_id.to_string(),
                json!({
                    "entity_id":  entity.entity_id,
                    "tenant_id":  entity.tenant_id,
                    "attributes": entity.attributes,
                }),
            );
            if let Err(e) = queue.enqueue(task_types::ENTITY_EMBED, &task).await {
                tracing::warn!(
                    entity_id=%entity.entity_id,
                    error=%e,
                    "embedding task enqueue failed — entity created but not embedded"
                );
            }
        }

        Ok(CreateEntityResponse {
            entity_id:        entity.entity_id,
            distribution_id,
            outbox_event_ids: vec![created_event_id],
        })
    }

    /// Fetch an entity by id — checks Redis cache first, falls back to DB.
    ///
    /// On cache miss the entity is stored in Redis for the next call.
    pub async fn get_entity(
        &self,
        tenant_id: Uuid,
        entity_id: Uuid,
    ) -> Result<Option<contracts::mdm::entity::CanonicalEntity>> {
        // ── Cache hit ────────────────────────────────────────────────────────
        if let Some(cache) = &self.entity_cache {
            match cache.get_entity(tenant_id, entity_id).await {
                Ok(Some(cached)) => {
                    tracing::debug!(entity_id=%entity_id, "entity cache hit");
                    return Ok(Some(cached));
                }
                Ok(None) => {} // cache miss — fall through to DB
                Err(e) => {
                    tracing::warn!(error=%e, "entity cache read failed — falling back to DB");
                }
            }
        }

        // ── DB fallback ──────────────────────────────────────────────────────
        let entity = self
            .entity_repository
            .fetch_entity(tenant_id, entity_id)
            .await?;

        // Populate cache on miss
        if let (Some(cache), Some(ref e)) = (&self.entity_cache, &entity) {
            if let Err(err) = cache.set_entity(tenant_id, entity_id, e).await {
                tracing::warn!(error=%err, "entity cache population failed");
            }
        }

        Ok(entity)
    }

    /// Invalidate a specific entity from the cache (call after update/merge).
    pub async fn invalidate_cache(&self, tenant_id: Uuid, entity_id: Uuid) {
        if let Some(cache) = &self.entity_cache {
            let _ = cache.invalidate_entity(tenant_id, entity_id).await;
        }
    }
}
