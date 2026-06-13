use anyhow::Result;

use chrono::{
    DateTime,
    Utc,
};

use sqlx::{
    PgPool,
    Postgres,
    Row,
    Transaction,
};

use std::collections::HashMap;

use uuid::Uuid;

use contracts::mdm::{
    common::{
        AIAnnotation,
        AuditMetadata,
        ConfidenceScore,
        DataProvenance,
        EmbeddingReference,
        MetadataMap,
        PolicyTag,
        SourceReference,
        VersionInfo,
    },
    entity::{
        CanonicalEntity,
        EntityAttribute,
        EntityStatus,
        EntityType,
    },
};

//
// ========================================
// ENTITY REPOSITORY
// ========================================
//

#[derive(Clone)]
pub struct EntityRepository {

    pub pool:
        PgPool,
}

impl EntityRepository {

    //
    // ====================================
    // CONSTRUCTOR
    // ====================================
    //

    pub fn new(
        pool: PgPool,
    ) -> Self {

        Self {
            pool,
        }
    }

    //
    // ====================================
    // HEALTH CHECK
    // ====================================
    //

    pub async fn health_check(
        &self,
    ) -> Result<i64> {

        let result: (i64,) =
            sqlx::query_as(
                "SELECT 1"
            )
            .fetch_one(&self.pool)
            .await?;

        Ok(result.0)
    }

    //
    // ====================================
    // CREATE ENTITY
    // ====================================
    //

    pub async fn create_entity(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        entity: &CanonicalEntity,
    ) -> Result<()> {

        //
        // ====================================
        // INSERT ENTITY
        // ====================================
        //

        sqlx::query(
            r#"
            INSERT INTO core_mdm.entities (
                entity_id,
                tenant_id,
                entity_type,
                status,
                external_ids,
                tags,
                metadata,
                trust_score,
                semantic_identity,
                vector_namespace,
                valid_from,
                valid_to,
                created_at,
                updated_at
            )
            VALUES (
                $1,$2,$3,$4,$5,$6,$7,
                $8,$9,$10,
                COALESCE($11, NOW()),
                COALESCE($12, 'infinity'::timestamptz),
                $13,$14
            )
            "#
        )
        .bind(entity.entity_id)
        .bind(entity.tenant_id)
        .bind(format!("{:?}", entity.entity_type))
        .bind(format!("{:?}", entity.status))
        .bind(
            sqlx::types::Json(
                &entity.external_ids
            )
        )
        .bind(&entity.tags)
        .bind(
            sqlx::types::Json(
                &entity.metadata
            )
        )
        .bind(entity.trust_score)
        .bind(&entity.semantic_identity)
        .bind(&entity.vector_namespace)
        .bind(entity.valid_from)
        .bind(entity.valid_to)
        .bind(entity.audit.created_at)
        .bind(entity.audit.updated_at)
        .execute(&mut **tx)
        .await?;

        //
        // ====================================
        // INSERT ATTRIBUTES
        // ====================================
        //

        for attribute in &entity.attributes {

            sqlx::query(
                r#"
                INSERT INTO core_mdm.entity_attributes (
                    attribute_id,
                    tenant_id,
                    entity_id,
                    attribute_key,
                    attribute_value,
                    data_type,
                    confidence,
                    source_system,
                    is_masked
                )
                VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
                "#
            )
            .bind(attribute.attribute_id)
            .bind(entity.tenant_id)
            .bind(entity.entity_id)
            .bind(&attribute.key)
            .bind(sqlx::types::Json(&attribute.value))
            .bind(attribute.data_type.as_str())
            .bind(attribute.confidence.as_ref().map(|c| c.score))
            .bind(
                attribute
                    .provenance
                    .as_ref()
                    .map(|p| p.source.source_system.as_str())
            )
            .bind(attribute.encrypted)
            .execute(&mut **tx)
            .await?;
        }

        Ok(())
    }

    //
    // ====================================
    // ENTITY EXISTS
    // ====================================
    //

    pub async fn entity_exists(
        &self,
        tenant_id: Uuid,
        entity_id: Uuid,
    ) -> Result<bool> {

        let row =
            sqlx::query(
                r#"
                SELECT EXISTS(
                    SELECT 1
                    FROM core_mdm.entities
                    WHERE tenant_id = $1
                    AND entity_id = $2
                )
                "#
            )
            .bind(tenant_id)
            .bind(entity_id)
            .fetch_one(&self.pool)
            .await?;

        Ok(
            row.get::<bool, _>(0)
        )
    }

    //
    // ====================================
    // FETCH ENTITY
    // ====================================
    //

    pub async fn fetch_entity(
        &self,
        tenant_id: Uuid,
        entity_id: Uuid,
    ) -> Result<Option<CanonicalEntity>> {

        //
        // ====================================
        // FETCH ENTITY
        // ====================================
        //

        let entity_row =
            sqlx::query(
                r#"
                SELECT
                    entity_id, tenant_id, entity_type, status,
                    external_ids, tags, metadata, trust_score,
                    source_system, golden_record_id, semantic_identity,
                    vector_namespace, recorded_at, created_at, updated_at,
                    created_by, correlation_id,
                    CASE WHEN valid_from = '-infinity'::timestamptz THEN NULL
                         ELSE valid_from END AS valid_from,
                    CASE WHEN valid_to = 'infinity'::timestamptz THEN NULL
                         ELSE valid_to END AS valid_to
                FROM core_mdm.entities
                WHERE tenant_id = $1
                  AND entity_id = $2
                "#
            )
            .bind(tenant_id)
            .bind(entity_id)
            .fetch_optional(&self.pool)
            .await?;

        let Some(row) = entity_row else {

            return Ok(None);
        };

        //
        // ====================================
        // FETCH ATTRIBUTES
        // ====================================
        //

        let attribute_rows =
            sqlx::query(
                r#"
                SELECT *
                FROM core_mdm.entity_attributes
                WHERE tenant_id = $1
                AND entity_id = $2
                "#
            )
            .bind(tenant_id)
            .bind(entity_id)
            .fetch_all(&self.pool)
            .await?;

        //
        // ====================================
        // BUILD ATTRIBUTES
        // ====================================
        //

        let attributes: Vec<EntityAttribute> =
            attribute_rows
                .into_iter()
                .map(|attr| {

                    //
                    // CONFIDENCE
                    //

                    let confidence =
                        attr
                            .try_get::<
                                Option<f32>,
                                _
                            >(
                                "confidence"
                            )
                            .ok()
                            .flatten()
                            .map(|score| {

                                ConfidenceScore {

                                    score,

                                    explanation:
                                        None,

                                    model_version:
                                        None,
                                }
                            });

                    //
                    // ATTRIBUTE VALUE
                    //

                    let value =
                        attr
                            .try_get::<
                                sqlx::types::Json<
                                    serde_json::Value
                                >,
                                _
                            >(
                                "attribute_value"
                            )
                            .map(|v| v.0)
                            .unwrap_or(
                                serde_json::Value::Null
                            );

                    //
                    // METADATA
                    //

                    let metadata =
                        attr
                            .try_get::<
                                sqlx::types::Json<
                                    MetadataMap
                                >,
                                _
                            >(
                                "metadata"
                            )
                            .map(|v| v.0)
                            .unwrap_or_default();

                    //
                    // PROVENANCE
                    //

                    let provenance: Option<DataProvenance> =
                        attr
                            .try_get::<String, _>("source_system")
                            .ok()
                            .filter(|s| !s.is_empty())
                            .map(|source_system| DataProvenance {
                                source: SourceReference {
                                    source_system,
                                    source_record_id: String::new(),
                                    ingestion_batch_id: None,
                                    ingestion_job_id: None,
                                    extracted_at: None,
                                },
                                transformation_pipeline: None,
                                transformation_version: None,
                                transformation_steps: vec![],
                            });

                    //
                    // POLICY TAGS
                    //

                    let policy_tags =
                        attr
                            .try_get::<
                                sqlx::types::Json<
                                    Vec<PolicyTag>
                                >,
                                _
                            >(
                                "policy_tags"
                            )
                            .map(|v| v.0)
                            .unwrap_or_default();

                    //
                    // EMBEDDING
                    //

                    let embedding_ref =
                        attr
                            .try_get::<
                                sqlx::types::Json<
                                    Option<
                                        EmbeddingReference
                                    >
                                >,
                                _
                            >(
                                "embedding_ref"
                            )
                            .map(|v| v.0)
                            .unwrap_or(None);

                    //
                    // AI ANNOTATIONS
                    //

                    let ai_annotations =
                        attr
                            .try_get::<
                                sqlx::types::Json<
                                    Vec<AIAnnotation>
                                >,
                                _
                            >(
                                "ai_annotations"
                            )
                            .map(|v| v.0)
                            .unwrap_or_default();

                    //
                    // UPDATED AT
                    //

                    let updated_at:
                        Option<DateTime<Utc>> =
                        attr
                            .try_get(
                                "updated_at"
                            )
                            .ok();

                    //
                    // ATTRIBUTE VERSION
                    //

                    let attribute_version:
                        i64 =
                        attr
                            .try_get(
                                "attribute_version"
                            )
                            .unwrap_or(1);

                    //
                    // BUILD ATTRIBUTE
                    //

                    EntityAttribute {

                        //
                        // IDENTITY
                        //

                        attribute_id:
                            attr
                                .try_get(
                                    "attribute_id"
                                )
                                .unwrap_or_else(|_| {
                                    Uuid::new_v4()
                                }),

                        key:
                            attr
                                .get(
                                    "attribute_key"
                                ),

                        //
                        // VALUE
                        //

                        value,

                        //
                        // TYPES
                        //

                        data_type:
                            attr
                                .try_get(
                                    "data_type"
                                )
                                .unwrap_or_else(|_| {
                                    "string"
                                        .to_string()
                                }),

                        semantic_type:
                            attr
                                .try_get(
                                    "semantic_type"
                                )
                                .ok(),

                        //
                        // CONFIDENCE
                        //

                        confidence,

                        //
                        // PROVENANCE
                        //

                        provenance,

                        //
                        // POLICY
                        //

                        policy_tags,

                        //
                        // SEARCH
                        //

                        aliases:
                            attr
                                .try_get(
                                    "aliases"
                                )
                                .unwrap_or_default(),

                        //
                        // VECTOR
                        //

                        embedding_ref,

                        //
                        // AI
                        //

                        ai_annotations,

                        //
                        // FLAGS
                        //

                        searchable:
                            attr
                                .try_get(
                                    "searchable"
                                )
                                .unwrap_or(true),

                        indexed:
                            attr
                                .try_get(
                                    "indexed"
                                )
                                .unwrap_or(true),

                        encrypted:
                            attr
                                .try_get(
                                    "encrypted"
                                )
                                .unwrap_or(false),

                        survivorship_eligible:
                            attr
                                .try_get(
                                    "survivorship_eligible"
                                )
                                .unwrap_or(true),

                        //
                        // TIMESTAMPS
                        //

                        updated_at,

                        //
                        // VERSION
                        //

                        attribute_version:
                            attribute_version
                                as u64,

                        //
                        // METADATA
                        //

                        metadata,
                    }
                })
                .collect();

        //
        // ====================================
        // EXTERNAL IDS
        // ====================================
        //

        let external_ids =
            row
                .try_get::<
                    sqlx::types::Json<
                        HashMap<String, String>
                    >,
                    _
                >(
                    "external_ids"
                )
                .map(|v| v.0)
                .unwrap_or_default();

        //
        // ====================================
        // METADATA
        // ====================================
        //

        let metadata =
            row
                .try_get::<
                    sqlx::types::Json<
                        MetadataMap
                    >,
                    _
                >(
                    "metadata"
                )
                .map(|v| v.0)
                .unwrap_or_default();

        //
        // ====================================
        // ENTITY TYPE
        // ====================================
        //

        let entity_type_string:
            String =
            row
                .try_get(
                    "entity_type"
                )
                .unwrap_or_else(|_| {
                    "Customer".to_string()
                });

        let entity_type =
            match entity_type_string.as_str() {

                "Vendor" =>
                    EntityType::Vendor,

                "Material" =>
                    EntityType::Material,

                "Product" =>
                    EntityType::Product,

                "Account" =>
                    EntityType::Account,

                "Employee" =>
                    EntityType::Employee,

                "Location" =>
                    EntityType::Location,

                "Organization" =>
                    EntityType::Organization,

                "Asset" =>
                    EntityType::Asset,

                "ReferenceData" =>
                    EntityType::ReferenceData,

                _ =>
                    EntityType::Customer,
            };

        //
        // ====================================
        // STATUS
        // ====================================
        //

        let status_string:
            String =
            row
                .try_get(
                    "status"
                )
                .unwrap_or_else(|_| {
                    "Active".to_string()
                });

        let status =
            match status_string.as_str() {

                "Draft" =>
                    EntityStatus::Draft,

                "Inactive" =>
                    EntityStatus::Inactive,

                "PendingReview" =>
                    EntityStatus::PendingReview,

                "UnderInvestigation" =>
                    EntityStatus::UnderInvestigation,

                "Merged" =>
                    EntityStatus::Merged,

                "Deleted" =>
                    EntityStatus::Deleted,

                "Archived" =>
                    EntityStatus::Archived,

                "SoftDeleted" =>
                    EntityStatus::SoftDeleted,

                _ =>
                    EntityStatus::Active,
            };

        //
        // ====================================
        // BUILD ENTITY
        // ====================================
        //

        let entity =
            CanonicalEntity {

                entity_id:
                    row.get(
                        "entity_id"
                    ),

                tenant_id:
                    row.get(
                        "tenant_id"
                    ),

                entity_type,

                external_ids,

                status,

                attributes,

                relationships:
                    vec![],

                source_snapshots:
                    vec![],

                version_info:
                    VersionInfo {

                        schema_version:
                            "1.0.0"
                                .to_string(),

                        contract_version:
                            "1.0.0"
                                .to_string(),

                        entity_version:
                            1,
                    },

                audit:
                    AuditMetadata {

                        created_at:
                            row
                                .try_get(
                                    "created_at"
                                )
                                .unwrap_or_else(|_| {
                                    Utc::now()
                                }),

                        updated_at:
                            row
                                .try_get(
                                    "updated_at"
                                )
                                .unwrap_or_else(|_| {
                                    Utc::now()
                                }),

                        created_by:
                            None,

                        updated_by:
                            None,

                        correlation_id:
                            None,

                        causation_id:
                            None,

                        request_id:
                            None,
                    },

                tags:
                    row
                        .try_get(
                            "tags"
                        )
                        .unwrap_or_default(),

                data_quality:
                    None,

                metadata,

                embedding_refs:
                    vec![],

                trust_score:
                    row
                        .try_get(
                            "trust_score"
                        )
                        .ok(),

                master_record:
                    row
                        .try_get(
                            "master_record"
                        )
                        .ok(),

                lineage_refs:
                    vec![],

                merge_refs:
                    vec![],

                survivorship_refs:
                    vec![],

                workflow_refs:
                    vec![],

                policy_refs:
                    vec![],

                changes:
                    vec![],

                semantic_identity:
                    row
                        .try_get(
                            "semantic_identity"
                        )
                        .ok(),

                vector_namespace:
                    row
                        .try_get(
                            "vector_namespace"
                        )
                        .ok(),

                valid_from:
                    row
                        .try_get(
                            "valid_from"
                        )
                        .ok(),

                valid_to:
                    row
                        .try_get(
                            "valid_to"
                        )
                        .ok(),
            };

        Ok(Some(entity))
    }

    //
    // ====================================
    // DELETE ENTITY
    // ====================================
    //

    pub async fn delete_entity(
        &self,
        tenant_id: Uuid,
        entity_id: Uuid,
    ) -> Result<u64> {

        let result =
            sqlx::query(
                r#"
                DELETE FROM core_mdm.entities
                WHERE tenant_id = $1
                AND entity_id = $2
                "#
            )
            .bind(tenant_id)
            .bind(entity_id)
            .execute(&self.pool)
            .await?;

        Ok(
            result.rows_affected()
        )
    }

    //
    // ====================================
    // COUNT ENTITIES
    // ====================================
    //

    pub async fn count_entities(
        &self,
        tenant_id: Uuid,
    ) -> Result<i64> {

        let row =
            sqlx::query(
                r#"
                SELECT COUNT(*)
                FROM core_mdm.entities
                WHERE tenant_id = $1
                "#
            )
            .bind(tenant_id)
            .fetch_one(&self.pool)
            .await?;

        Ok(
            row.get::<i64, _>(0)
        )
    }

    // ====================================
    // LIST ENTITIES (paginated)
    // ====================================

    /// Returns a page of entities in a Flutter-compatible JSON shape, plus total count.
    pub async fn list_entities(
        &self,
        tenant_id:   Uuid,
        page:        i64,
        page_size:   i64,
        entity_type: Option<&str>,
        status:      Option<&str>,
        search:      Option<&str>,
    ) -> Result<(Vec<serde_json::Value>, i64)> {
        let offset = (page - 1) * page_size;

        // Normalise filter values to the capitalized enum format stored in the DB.
        let type_filter: Option<String> = entity_type.map(|t| {
            let mut c = t.chars();
            match c.next() {
                None        => String::new(),
                Some(first) => first.to_uppercase().to_string() + c.as_str(),
            }
        });
        let status_filter: Option<String> = status.map(|s| match s.to_lowercase().as_str() {
            "review"   => "PendingReview".to_string(),
            "pending"  => "Draft".to_string(),
            "golden"   => "Active".to_string(),
            other      => {
                let mut c = other.chars();
                match c.next() {
                    None        => String::new(),
                    Some(first) => first.to_uppercase().to_string() + c.as_str(),
                }
            }
        });
        let search_pattern: Option<String> = search.map(|s| format!("%{}%", s));

        // Count query (separate from data query for clarity).
        let total: i64 = sqlx::query_scalar(
            r#"
            SELECT COUNT(*)
            FROM core_mdm.entities e
            WHERE e.tenant_id = $1
              AND ($2::text IS NULL OR e.entity_type = $2)
              AND ($3::text IS NULL OR e.status      = $3)
              AND (
                $4::text IS NULL
                OR e.entity_id::text ILIKE $4
                OR EXISTS (
                    SELECT 1
                    FROM core_mdm.entity_attributes a
                    WHERE a.entity_id  = e.entity_id
                      AND a.tenant_id  = e.tenant_id
                      AND a.attribute_value::text ILIKE $4
                )
              )
            "#,
        )
        .bind(tenant_id)
        .bind(&type_filter)
        .bind(&status_filter)
        .bind(&search_pattern)
        .fetch_one(&self.pool)
        .await?;

        // Data query with display_name and primary_source derived from attributes.
        // NOTE: entity_attributes has columns: attribute_key, attribute_value,
        //       data_type, confidence, source_system, created_at.
        let rows = sqlx::query(
            r#"
            SELECT
                e.entity_id,
                e.entity_type,
                e.status,
                e.trust_score::double precision AS trust_score,
                e.created_at,
                e.updated_at,
                (
                    SELECT a.attribute_value #>> '{}'
                    FROM   core_mdm.entity_attributes a
                    WHERE  a.entity_id = e.entity_id
                      AND  a.tenant_id = e.tenant_id
                      AND  lower(a.attribute_key) IN (
                               'name', 'full_name', 'display_name',
                               'company_name', 'legal_name'
                           )
                    ORDER  BY a.confidence DESC NULLS LAST,
                              a.created_at  DESC
                    LIMIT  1
                ) AS display_name,
                (
                    SELECT a.source_system
                    FROM   core_mdm.entity_attributes a
                    WHERE  a.entity_id    = e.entity_id
                      AND  a.tenant_id   = e.tenant_id
                      AND  a.source_system IS NOT NULL
                    ORDER  BY a.confidence DESC NULLS LAST
                    LIMIT  1
                ) AS primary_source
            FROM  core_mdm.entities e
            WHERE e.tenant_id = $1
              AND ($2::text IS NULL OR e.entity_type = $2)
              AND ($3::text IS NULL OR e.status      = $3)
              AND (
                $4::text IS NULL
                OR e.entity_id::text ILIKE $4
                OR EXISTS (
                    SELECT 1
                    FROM core_mdm.entity_attributes a
                    WHERE a.entity_id  = e.entity_id
                      AND a.tenant_id  = e.tenant_id
                      AND a.attribute_value::text ILIKE $4
                )
              )
            ORDER BY e.created_at DESC
            LIMIT  $5 OFFSET $6
            "#,
        )
        .bind(tenant_id)
        .bind(&type_filter)
        .bind(&status_filter)
        .bind(&search_pattern)
        .bind(page_size)
        .bind(offset)
        .fetch_all(&self.pool)
        .await?;

        let items: Vec<serde_json::Value> = rows
            .iter()
            .map(|row| {
                let entity_id:   Uuid     = row.get("entity_id");
                let entity_type: String   = row.try_get("entity_type").unwrap_or_default();
                let status:      String   = row.try_get("status").unwrap_or_default();
                let trust_score: Option<f64> = row.try_get("trust_score").ok();
                let created_at:  DateTime<Utc> =
                    row.try_get("created_at").unwrap_or_else(|_| Utc::now());
                let updated_at:  DateTime<Utc> =
                    row.try_get("updated_at").unwrap_or_else(|_| Utc::now());
                let display_name:   Option<String> = row.try_get("display_name").ok().flatten();
                let primary_source: Option<String> = row.try_get("primary_source").ok().flatten();

                let flutter_type   = entity_type_to_flutter(&entity_type);
                let flutter_status = entity_status_to_flutter(&status);
                let score          = trust_score.unwrap_or(0.8);
                let name           = display_name.unwrap_or_else(|| {
                    format!(
                        "{} {}",
                        &entity_type,
                        &entity_id.to_string()[..8]
                    )
                });
                let source = primary_source.unwrap_or_else(|| "Nexus MDM".to_string());

                serde_json::json!({
                    "id":            entity_id.to_string(),
                    "entity_id":     entity_id.to_string(),
                    "type":          flutter_type,
                    "status":        flutter_status,
                    "display_name":  name,
                    "trust_score":   score,
                    "quality_score": score,
                    "primary_source": source,
                    "source_systems": [source],
                    "attributes":    {},
                    "created_at":    created_at.to_rfc3339(),
                    "updated_at":    updated_at.to_rfc3339()
                })
            })
            .collect();

        Ok((items, total))
    }

    // ====================================
    // UPDATE ENTITY (PATCH)
    // ====================================

    #[allow(clippy::too_many_arguments)]
    pub async fn update_entity(
        &self,
        tx:          &mut Transaction<'_, Postgres>,
        tenant_id:   Uuid,
        entity_id:   Uuid,
        entity_type: Option<&str>,
        status:      Option<&str>,
        tags:        Option<&Vec<String>>,
        attributes:  Option<&Vec<contracts::mdm::entity::EntityAttribute>>,
    ) -> Result<bool> {
        // Build a dynamic UPDATE — only touch columns that were supplied.
        let mut set_clauses: Vec<String> = vec!["updated_at = NOW()".to_string()];
        let mut param_index: i32 = 3; // $1=tenant_id, $2=entity_id already reserved

        if entity_type.is_some() {
            set_clauses.push(format!("entity_type = ${}", param_index));
            param_index += 1;
        }
        if status.is_some() {
            set_clauses.push(format!("status = ${}", param_index));
            param_index += 1;
        }
        if tags.is_some() {
            set_clauses.push(format!("tags = ${}", param_index));
        }

        let sql = format!(
            "UPDATE core_mdm.entities SET {} WHERE tenant_id = $1 AND entity_id = $2",
            set_clauses.join(", ")
        );

        let mut q = sqlx::query(&sql)
            .bind(tenant_id)
            .bind(entity_id);
        if let Some(v) = entity_type { q = q.bind(v); }
        if let Some(v) = status      { q = q.bind(v); }
        if let Some(v) = tags        { q = q.bind(v); }

        let result = q.execute(&mut **tx).await?;
        if result.rows_affected() == 0 {
            return Ok(false);
        }

        // Replace attributes when supplied — delete-then-insert is the MDM
        // golden-record survivorship pattern for authority-authored records.
        if let Some(attrs) = attributes {
            sqlx::query(
                "DELETE FROM core_mdm.entity_attributes WHERE tenant_id = $1 AND entity_id = $2"
            )
            .bind(tenant_id)
            .bind(entity_id)
            .execute(&mut **tx)
            .await?;

            for attribute in attrs {
                sqlx::query(
                    r#"
                    INSERT INTO core_mdm.entity_attributes (
                        attribute_id, tenant_id, entity_id,
                        attribute_key, attribute_value, data_type,
                        confidence, source_system, is_masked
                    )
                    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
                    "#
                )
                .bind(attribute.attribute_id)
                .bind(tenant_id)
                .bind(entity_id)
                .bind(&attribute.key)
                .bind(sqlx::types::Json(&attribute.value))
                .bind(attribute.data_type.as_str())
                .bind(attribute.confidence.as_ref().map(|c| c.score))
                .bind(attribute.provenance.as_ref().map(|p| p.source.source_system.as_str()))
                .bind(attribute.encrypted)
                .execute(&mut **tx)
                .await?;
            }
        }

        Ok(true)
    }

    // ====================================
    // UPDATE ENTITY STATUS
    // ====================================

    pub async fn update_entity_status(
        &self,
        tx:        &mut sqlx::Transaction<'_, sqlx::Postgres>,
        tenant_id: Uuid,
        entity_id: Uuid,
        status:    contracts::mdm::entity::EntityStatus,
    ) -> Result<()> {
        sqlx::query(
            r#"
            UPDATE core_mdm.entities
            SET    status     = $3,
                   updated_at = NOW()
            WHERE  tenant_id  = $1
            AND    entity_id  = $2
            "#,
        )
        .bind(tenant_id)
        .bind(entity_id)
        .bind(format!("{:?}", status))
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    // ====================================
    // SET GOLDEN RECORD LINK
    // ====================================

    pub async fn set_golden_record_id(
        &self,
        tx:               &mut sqlx::Transaction<'_, sqlx::Postgres>,
        tenant_id:        Uuid,
        entity_id:        Uuid,
        golden_record_id: Uuid,
    ) -> Result<()> {
        sqlx::query(
            r#"
            UPDATE core_mdm.entities
            SET    golden_record_id = $3,
                   updated_at       = NOW()
            WHERE  tenant_id        = $1
            AND    entity_id        = $2
            "#,
        )
        .bind(tenant_id)
        .bind(entity_id)
        .bind(golden_record_id)
        .execute(&mut **tx)
        .await?;
        Ok(())
    }
}

// ── Mapping helpers ──────────────────────────────────────────────────────────

pub fn entity_type_to_flutter(entity_type: &str) -> &'static str {
    match entity_type {
        "Customer" | "Employee"                   => "person",
        "Vendor" | "Account" | "Organization"     => "organization",
        "Material" | "Product" | "ReferenceData"  => "product",
        "Location"                                => "location",
        "Asset"                                   => "asset",
        _                                         => "person",
    }
}

pub fn entity_status_to_flutter(status: &str) -> &'static str {
    match status {
        "Active"                                  => "active",
        "Draft"                                   => "pending",
        "PendingReview" | "UnderInvestigation"    => "review",
        "Merged"                                  => "merged",
        "Inactive" | "Deleted" | "Archived"
        | "SoftDeleted"                           => "inactive",
        _                                         => "active",
    }
}