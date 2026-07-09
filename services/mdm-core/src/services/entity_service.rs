use std::collections::HashSet;
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
use contracts::mdm::entity::{EntityAttribute, EntitySourceSnapshot, EntityStatus};

use database::{DbPool, PendingOutboxEvent, RequestContext, RequestContextFactory};
use sqlx::Row;
use azile_redis::{EntityCache, TaskQueue, queue::task_types};
use azile_security::encryption::field_encryption::FieldEncryptionService;

use crate::db::repositories::entity_repository::EntityRepository;

/// Service responsible for the full entity creation lifecycle:
///
/// 1. Idempotency check (Redis cache-aside â†’ DB fallback)
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
    /// Optional Redis task queue â€” if absent, embeddings are skipped silently.
    task_queue:        Option<Arc<TaskQueue>>,
    /// Optional Redis entity cache â€” if absent, every read hits PostgreSQL.
    entity_cache:      Option<Arc<EntityCache>>,
    /// AES-256-GCM PII encryption. None = plaintext (dev only).
    field_encryption:  Option<Arc<FieldEncryptionService>>,
}

impl EntityService {
    pub fn new(
        pool:              DbPool,
        entity_repository: Arc<EntityRepository>,
        task_queue:        Option<Arc<TaskQueue>>,
    ) -> Self {
        Self { pool, entity_repository, task_queue, entity_cache: None, field_encryption: None }
    }

    pub fn with_cache(mut self, cache: Arc<EntityCache>) -> Self {
        self.entity_cache = Some(cache);
        self
    }

    /// Optionally attach a cache â€” passes through `None` gracefully.
    pub fn with_cache_opt(mut self, cache: Option<Arc<EntityCache>>) -> Self {
        self.entity_cache = cache;
        self
    }

    /// Attach field-level encryption for PII attributes.
    pub fn with_encryption(mut self, enc: Option<Arc<FieldEncryptionService>>) -> Self {
        self.field_encryption = enc;
        self
    }

    /// Query `core_mdm.attribute_schemas` for all attribute keys the tenant has
    /// explicitly marked `is_pii = true`. Keys are returned as lowercase so callers
    /// can do case-insensitive membership checks. Returns an empty set on DB error
    /// so the static-key fallback in `is_pii_attribute` still applies.
    pub(crate) async fn load_schema_pii_keys(pool: &DbPool, tenant_id: Uuid) -> HashSet<String> {
        match sqlx::query_scalar::<_, String>(
            r#"SELECT attribute_key
               FROM core_mdm.attribute_schemas
               WHERE tenant_id = $1 AND is_pii = true"#,
        )
        .bind(tenant_id)
        .fetch_all(pool)
        .await
        {
            Ok(keys) => keys.into_iter().map(|k| k.to_lowercase()).collect(),
            Err(e) => {
                tracing::warn!(error=%e, %tenant_id, "failed to load schema PII keys; relying on static list");
                HashSet::new()
            }
        }
    }

    /// Returns true if the attribute key is a well-known PII field.
    pub(crate) fn is_pii_attribute(key: &str) -> bool {
        const PII_KEYS: &[&str] = &[
            "email", "email_address",
            "phone", "phone_number", "mobile", "mobile_number", "cell_phone",
            "ssn", "social_security_number", "national_id", "national_insurance_number",
            "tax_id", "tax_number", "tin", "ein",
            "date_of_birth", "dob", "birth_date",
            "passport", "passport_number",
            "driver_license", "drivers_license", "license_number",
            "credit_card", "card_number", "cvv",
            "bank_account", "account_number", "iban", "routing_number",
            "ip_address",
            "street_address", "home_address", "billing_address",
        ];
        let lower = key.to_lowercase();
        // Exact match or ends with a known PII suffix (e.g. "contact_email")
        PII_KEYS.contains(&lower.as_str())
            || PII_KEYS.iter().any(|&pii| lower.ends_with(&format!("_{}", pii)))
    }

    /// Encrypt plaintext string values for PII-tagged attributes.
    /// Checks both the built-in static key list and `schema_pii_keys` (keys the
    /// tenant declared `is_pii=true` in `core_mdm.attribute_schemas`).
    /// Returns a new attribute list â€” non-PII and already-encrypted attrs are unchanged.
    pub(crate) fn encrypt_pii_attributes(
        attrs:           Vec<EntityAttribute>,
        enc:             &FieldEncryptionService,
        schema_pii_keys: &HashSet<String>,
    ) -> Vec<EntityAttribute> {
        attrs.into_iter().map(|mut attr| {
            let key_lower = attr.key.to_lowercase();
            if !attr.encrypted && (Self::is_pii_attribute(&attr.key) || schema_pii_keys.contains(&key_lower)) {
                if let serde_json::Value::String(ref plain) = attr.value {
                    match enc.encrypt(plain) {
                        Ok(ciphertext) => {
                            attr.value     = serde_json::Value::String(ciphertext);
                            attr.encrypted = true;
                        }
                        Err(e) => {
                            tracing::warn!(key=%attr.key, error=%e, "PII encryption failed â€” storing plaintext");
                        }
                    }
                } else if !matches!(attr.value, serde_json::Value::Null) {
                    // Non-string PII (number, bool, array, object): serialise to the JSON
                    // representation and encrypt it so no PII leaks through type mismatch.
                    let json_str = attr.value.to_string();
                    match enc.encrypt(&json_str) {
                        Ok(ciphertext) => {
                            tracing::warn!(
                                key=%attr.key,
                                "PII attribute has a non-string value â€” serialised to JSON before encryption"
                            );
                            attr.value     = serde_json::Value::String(ciphertext);
                            attr.encrypted = true;
                        }
                        Err(e) => {
                            tracing::warn!(key=%attr.key, error=%e, "PII encryption failed for non-string value");
                        }
                    }
                }
            }
            attr
        }).collect()
    }

    /// Map the EntityType enum variant to the uppercase code stored in attribute_schemas.
    fn entity_type_to_code(entity_type: &contracts::mdm::entity::EntityType) -> String {
        use contracts::mdm::entity::EntityType as ET;
        match entity_type {
            ET::Customer      => "CUSTOMER".to_string(),
            ET::Vendor        => "VENDOR".to_string(),
            ET::Material      => "MATERIAL".to_string(),
            ET::Product       => "PRODUCT".to_string(),
            ET::Account       => "ACCOUNT".to_string(),
            ET::Employee      => "EMPLOYEE".to_string(),
            ET::Location      => "LOCATION".to_string(),
            ET::Organization  => "ORGANIZATION".to_string(),
            ET::Asset         => "ASSET".to_string(),
            ET::ReferenceData => "REFERENCE_DATA".to_string(),
            ET::Custom(code)  => code.to_uppercase(),
        }
    }

    /// Validate entity attributes against the tenant's configured attribute schemas.
    ///
    /// If no schemas exist for this entity type, validation is a silent no-op â€”
    /// the feature only activates once the tenant defines schemas via the admin UI.
    async fn validate_attributes_against_schema(
        &self,
        tenant_id:   Uuid,
        entity_type_code: &str,
        attrs:       &[EntityAttribute],
    ) -> Result<()> {
        // Struct for the schema rows we need
        struct SchemaRow {
            attribute_key: String,
            data_type:     String,
            is_required:   bool,
            min_length:    Option<i32>,
            max_length:    Option<i32>,
            enum_values:   Option<Vec<String>>,
        }

        let rows = sqlx::query(
            r#"
            SELECT attribute_key, data_type, is_required,
                   (validation->>'min_length')::int AS min_length,
                   (validation->>'max_length')::int AS max_length,
                   CASE WHEN enum_values IS NULL THEN NULL
                        ELSE ARRAY(SELECT jsonb_array_elements_text(enum_values))
                   END AS enum_values
            FROM core_mdm.attribute_schemas
            WHERE tenant_id = $1
              AND entity_type = $2
            "#,
        )
        .bind(tenant_id)
        .bind(entity_type_code)
        .fetch_all(&self.pool)
        .await?;

        if rows.is_empty() {
            return Ok(());
        }

        let schemas: Vec<SchemaRow> = rows
            .into_iter()
            .map(|r| SchemaRow {
                attribute_key: r.get::<String, _>("attribute_key"),
                data_type:     r.get::<String, _>("data_type"),
                is_required:   r.get::<bool, _>("is_required"),
                min_length:    r.try_get::<Option<i32>, _>("min_length").unwrap_or(None),
                max_length:    r.try_get::<Option<i32>, _>("max_length").unwrap_or(None),
                enum_values:   r.try_get::<Option<Vec<String>>, _>("enum_values").unwrap_or(None),
            })
            .collect();

        let attr_map: std::collections::HashMap<&str, &EntityAttribute> =
            attrs.iter().map(|a| (a.key.as_str(), a)).collect();

        let mut errors: Vec<String> = vec![];

        for schema in &schemas {
            match attr_map.get(schema.attribute_key.as_str()) {
                None if schema.is_required => {
                    errors.push(format!("'{}' is required", schema.attribute_key));
                }
                None => {} // optional absent â€” fine
                Some(attr) => {
                    let val_str = attr.value.as_str();

                    if schema.is_required && (val_str.map(str::is_empty).unwrap_or(true)) {
                        errors.push(format!("'{}' is required and must not be empty", schema.attribute_key));
                        continue;
                    }

                    if let Some(v) = val_str {
                        match schema.data_type.as_str() {
                            "email" => {
                                if !v.contains('@') || !v.contains('.') {
                                    errors.push(format!("'{}' must be a valid email address", schema.attribute_key));
                                }
                            }
                            "phone" => {
                                let invalid = v.chars().any(|c| !c.is_ascii_digit() && !"+ -()".contains(c));
                                if invalid {
                                    errors.push(format!("'{}' must be a valid phone number", schema.attribute_key));
                                }
                            }
                            "number" | "currency" => {
                                if v.parse::<f64>().is_err() {
                                    errors.push(format!("'{}' must be a number", schema.attribute_key));
                                }
                            }
                            "boolean" => {
                                if !["true", "false", "1", "0", "yes", "no"].contains(&v.to_lowercase().as_str()) {
                                    errors.push(format!("'{}' must be a boolean value", schema.attribute_key));
                                }
                            }
                            "enum" => {
                                if let Some(allowed) = &schema.enum_values {
                                    if !allowed.iter().any(|a| a.eq_ignore_ascii_case(v)) {
                                        errors.push(format!(
                                            "'{}' must be one of: {}",
                                            schema.attribute_key,
                                            allowed.join(", ")
                                        ));
                                    }
                                }
                            }
                            _ => {}
                        }

                        let char_count = v.chars().count() as i32;
                        if let Some(min) = schema.min_length {
                            if char_count < min {
                                errors.push(format!(
                                    "'{}' must be at least {} characters",
                                    schema.attribute_key, min
                                ));
                            }
                        }
                        if let Some(max) = schema.max_length {
                            if char_count > max {
                                errors.push(format!(
                                    "'{}' must not exceed {} characters",
                                    schema.attribute_key, max
                                ));
                            }
                        }
                    }
                }
            }
        }

        if errors.is_empty() {
            Ok(())
        } else {
            Err(anyhow!("attribute validation failed: {}", errors.join("; ")))
        }
    }

    /// Decrypt encrypted attribute values back to plaintext.
    fn decrypt_pii_attributes(
        attrs: Vec<EntityAttribute>,
        enc:   &FieldEncryptionService,
    ) -> Vec<EntityAttribute> {
        attrs.into_iter().map(|mut attr| {
            if attr.encrypted {
                if let serde_json::Value::String(ref ciphertext) = attr.value {
                    match enc.decrypt(ciphertext) {
                        Ok(plain) => {
                            attr.value     = serde_json::Value::String(plain);
                            attr.encrypted = false;
                        }
                        Err(e) => {
                            tracing::warn!(key=%attr.key, error=%e, "PII decryption failed â€” returning ciphertext");
                        }
                    }
                }
            }
            attr
        }).collect()
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

        // â”€â”€ Idempotency â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        // A client that retries on network failure must not create a duplicate.
        // If the id was provided and already exists, return the existing record.
        if !entity.entity_id.is_nil() && self
            .entity_repository
            .fetch_entity(entity.tenant_id, entity.entity_id)
            .await?
            .is_some()
        {
            tracing::debug!(entity_id=%entity.entity_id, "idempotent entity create â€” returning existing");
            return Ok(CreateEntityResponse {
                entity_id:         entity.entity_id,
                distribution_id:   None,
                outbox_event_ids:  vec![],
            });
        }

        // â”€â”€ Attribute schema validation â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        // Validates required fields and basic type constraints against
        // core_mdm.attribute_schemas for this entity type.
        // Fails fast before any transaction is opened.
        let entity_type_code = Self::entity_type_to_code(&entity.entity_type);
        self.validate_attributes_against_schema(
            entity.tenant_id,
            &entity_type_code,
            &entity.attributes,
        )
        .await?;

        // â”€â”€ Auto-assign business number â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        // If no business number is present, auto-generate one from the sequence.
        // This assigns CUST-000001, VEND-000001, PROD-000001, etc.
        let entity_type_str = entity.entity_type.to_string();
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

        // â”€â”€ Origin enrichment â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        if request.record_origin == EntityRecordOrigin::MdmAuthoritative {
            entity.metadata.insert(
                "record_origin".to_string(),
                json!("mdm_authoritative"),
            );
            entity.source_snapshots.push(EntitySourceSnapshot {
                source_system:     "azile-mdm".to_string(),
                source_entity_id:  entity.entity_id.to_string(),
                payload_reference: None,
                extracted_at:      Some(Utc::now()),
                metadata:          Default::default(),
            });
        }

        // â”€â”€ Transactional write with RLS context â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        // begin_uow() sets app.current_tenant, app.request_id,
        // app.correlation_id, app.trace_id, app.current_user_id on the
        // PostgreSQL session before any DML so RLS policies can filter correctly.
        let factory = RequestContextFactory::new(self.pool.clone());
        let mut uow = factory
            .begin_uow(ctx.tenant_id, ctx.user_id, ctx.trace_id.clone())
            .await?;

        // Encrypt PII attributes before writing to DB. The in-memory entity
        // retains plaintext for outbox events and cache â€” the security boundary
        // is the PostgreSQL database.
        let schema_pii_keys = Self::load_schema_pii_keys(&self.pool, ctx.tenant_id).await;
        let db_entity = if let Some(enc) = &self.field_encryption {
            let mut e = entity.clone();
            e.attributes = Self::encrypt_pii_attributes(e.attributes, enc, &schema_pii_keys);
            e
        } else {
            entity.clone()
        };
        self.entity_repository
            .create_entity(&mut uow.tx, &db_entity)
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

        // â”€â”€ Redis entity cache (write-through) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        // Store immediately after commit so subsequent reads are cache hits.
        if let Some(cache) = &self.entity_cache {
            if let Err(e) = cache.set_entity(entity.tenant_id, entity.entity_id, &entity).await {
                tracing::warn!(
                    entity_id=%entity.entity_id,
                    error=%e,
                    "entity cache write failed â€” entity created but not cached"
                );
            }
        }

        // â”€â”€ Async embedding â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        // Enqueue a low-priority task so the ai-service can embed this entity's
        // attributes into pgvector.  This is fire-and-forget; failure is logged
        // but does not fail the create response.
        if let Some(queue) = &self.task_queue {
            let task = azile_redis::queue::Task::new(
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
                    "embedding task enqueue failed â€” entity created but not embedded"
                );
            }
        }

        Ok(CreateEntityResponse {
            entity_id:        entity.entity_id,
            distribution_id,
            outbox_event_ids: vec![created_event_id],
        })
    }

    /// Fetch an entity by id â€” checks Redis cache first, falls back to DB.
    ///
    /// On cache miss the entity is stored in Redis for the next call.
    pub async fn get_entity(
        &self,
        tenant_id: Uuid,
        entity_id: Uuid,
    ) -> Result<Option<contracts::mdm::entity::CanonicalEntity>> {
        // â”€â”€ Cache hit â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        if let Some(cache) = &self.entity_cache {
            match cache.get_entity(tenant_id, entity_id).await {
                Ok(Some(cached)) => {
                    tracing::debug!(entity_id=%entity_id, "entity cache hit");
                    return Ok(Some(cached));
                }
                Ok(None) => {} // cache miss â€” fall through to DB
                Err(e) => {
                    tracing::warn!(error=%e, "entity cache read failed â€” falling back to DB");
                }
            }
        }

        // â”€â”€ DB fallback â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        let entity = self
            .entity_repository
            .fetch_entity(tenant_id, entity_id)
            .await?
            .map(|mut e| {
                if let Some(enc) = &self.field_encryption {
                    e.attributes = Self::decrypt_pii_attributes(e.attributes, enc);
                }
                e
            });

        // Populate cache on miss (cache stores decrypted plaintext â€” stays in Redis TTL only)
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
