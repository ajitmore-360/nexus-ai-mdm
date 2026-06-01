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
                $8,$9,$10,$11,$12,
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

            let provenance_json =
                serde_json::to_value(
                    &attribute.provenance
                )?;

            let embedding_json =
                serde_json::to_value(
                    &attribute.embedding_ref
                )?;

            let ai_annotations_json =
                serde_json::to_value(
                    &attribute.ai_annotations
                )?;

            let policy_tags_json =
                serde_json::to_value(
                    &attribute.policy_tags
                )?;

            sqlx::query(
                r#"
                INSERT INTO core_mdm.entity_attributes (
                    attribute_id,
                    tenant_id,
                    entity_id,
                    attribute_key,
                    attribute_value,
                    data_type,
                    semantic_type,
                    confidence_score,
                    provenance,
                    policy_tags,
                    aliases,
                    embedding_ref,
                    ai_annotations,
                    searchable,
                    indexed,
                    encrypted,
                    survivorship_eligible,
                    attribute_version,
                    metadata,
                    created_at,
                    updated_at
                )
                VALUES (
                    $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,
                    $11,$12,$13,$14,$15,$16,$17,$18,
                    $19,$20,$21
                )
                "#
            )
            .bind(attribute.attribute_id)
            .bind(entity.tenant_id)
            .bind(entity.entity_id)
            .bind(&attribute.key)
            .bind(
                sqlx::types::Json(
                    &attribute.value
                )
            )
            .bind(&attribute.data_type)
            .bind(&attribute.semantic_type)
            .bind(
                attribute
                    .confidence
                    .as_ref()
                    .map(|c| c.score)
            )
            .bind(
                sqlx::types::Json(
                    provenance_json
                )
            )
            .bind(
                sqlx::types::Json(
                    policy_tags_json
                )
            )
            .bind(&attribute.aliases)
            .bind(
                sqlx::types::Json(
                    embedding_json
                )
            )
            .bind(
                sqlx::types::Json(
                    ai_annotations_json
                )
            )
            .bind(attribute.searchable)
            .bind(attribute.indexed)
            .bind(attribute.encrypted)
            .bind(
                attribute
                    .survivorship_eligible
            )
            .bind(
                attribute.attribute_version
                    as i64
            )
            .bind(
                sqlx::types::Json(
                    &attribute.metadata
                )
            )
            .bind(attribute.updated_at)
            .bind(attribute.updated_at)
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
                SELECT *
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
                                "confidence_score"
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

                    let provenance =
                        attr
                            .try_get::<
                                sqlx::types::Json<
                                    Option<DataProvenance>
                                >,
                                _
                            >(
                                "provenance"
                            )
                            .map(|v| v.0)
                            .unwrap_or(None);

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
}