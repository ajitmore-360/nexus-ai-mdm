use anyhow::Result;

use chrono::Utc;

use serde_json::Value;

use sqlx::{
    PgPool,
    Postgres,
    Row,
    Transaction,
};

use uuid::Uuid;

use contracts::mdm::{
    common::{
        AuditMetadata,
        MetadataMap,
        VersionInfo,
    },
    entity::{
        EntityAttribute,
        EntityType,
    },
    golden_record::{
        GoldenAttribute,
        GoldenRecord,
        GoldenRecordLifecycleStage,
        GoldenRecordQuality,
        GoldenRecordStatus,
    },
};

//
// ========================================
// GOLDEN RECORD REPOSITORY
// ========================================
//

#[derive(Clone)]
pub struct GoldenRecordRepository {

    pub pool: PgPool,
}

impl GoldenRecordRepository {

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
    // CREATE GOLDEN RECORD
    // ====================================
    //

    pub async fn create_golden_record(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        golden_record: &GoldenRecord,
    ) -> Result<()> {

        //
        // INSERT GOLDEN RECORD
        //

        sqlx::query(
            r#"
            INSERT INTO core_mdm.golden_records (
                golden_record_id,
                tenant_id,
                entity_type,
                lifecycle_stage,
                status,
                source_entities,
                semantic_identity,
                vector_namespace,
                valid_from,
                valid_to,
                metadata,
                created_at,
                updated_at
            )
            VALUES (
                $1,$2,$3,$4,$5,
                $6,$7,$8,$9,$10,
                $11,$12,$13
            )
            "#
        )
        .bind(golden_record.golden_record_id)
        .bind(golden_record.tenant_id)
        .bind(format!("{:?}", golden_record.entity_type))
        .bind(format!("{:?}", golden_record.lifecycle_stage))
        .bind(format!("{:?}", golden_record.status))
        .bind(&golden_record.source_entities)
        .bind(&golden_record.semantic_identity)
        .bind(&golden_record.vector_namespace)
        .bind(golden_record.valid_from)
        .bind(golden_record.valid_to)
        .bind(sqlx::types::Json(
            &golden_record.metadata
        ))
        .bind(Utc::now())
        .bind(Utc::now())
        .execute(&mut **tx)
        .await?;

        //
        // INSERT GOLDEN ATTRIBUTES
        //

        for attribute in &golden_record.golden_attributes {

            self.insert_golden_attribute(
                tx,
                golden_record,
                attribute,
            )
            .await?;
        }

        Ok(())
    }

    //
    // ====================================
    // INSERT GOLDEN ATTRIBUTE
    // ====================================
    //

    async fn insert_golden_attribute(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        golden_record: &GoldenRecord,
        attribute: &GoldenAttribute,
    ) -> Result<()> {

        sqlx::query(
            r#"
            INSERT INTO core_mdm.golden_record_attributes (
                golden_attribute_id,
                tenant_id,
                golden_record_id,
                attribute_key,
                attribute_value,
                selected_from_entity,
                selected_from_source,
                survivorship_score,
                ai_confidence,
                explainability,
                metadata,
                created_at
            )
            VALUES (
                $1,$2,$3,$4,$5,
                $6,$7,$8,$9,$10,
                $11,$12
            )
            "#
        )
        .bind(attribute.golden_attribute_id)
        .bind(golden_record.tenant_id)
        .bind(golden_record.golden_record_id)
        .bind(&attribute.attribute.key)
        .bind(sqlx::types::Json(
            &attribute.attribute.value
        ))
        .bind(attribute.selected_from_entity)
        .bind(&attribute.selected_from_source)
        .bind(attribute.survivorship_score)
        .bind(attribute.ai_confidence)
        .bind(&attribute.explainability)
        .bind(sqlx::types::Json(
            &attribute.metadata
        ))
        .bind(Utc::now())
        .execute(&mut **tx)
        .await?;

        Ok(())
    }

    //
    // ====================================
    // FETCH GOLDEN RECORD
    // ====================================
    //

    pub async fn fetch_golden_record(
        &self,
        tenant_id: Uuid,
        golden_record_id: Uuid,
    ) -> Result<Option<GoldenRecord>> {

        let row =
            sqlx::query(
                r#"
                SELECT *
                FROM core_mdm.golden_records
                WHERE tenant_id = $1
                AND golden_record_id = $2
                "#
            )
            .bind(tenant_id)
            .bind(golden_record_id)
            .fetch_optional(&self.pool)
            .await?;

        let Some(row) = row else {
            return Ok(None);
        };

        //
        // LOAD ATTRIBUTES
        //

        let golden_attributes =
            self.fetch_golden_attributes(
                tenant_id,
                golden_record_id,
            )
            .await?;

        //
        // METADATA
        //

        let metadata =
            row.try_get::<
                sqlx::types::Json<MetadataMap>,
                _
            >("metadata")
            .map(|v| v.0)
            .unwrap_or_default();

        //
        // BUILD OBJECT
        //

        let record =
            GoldenRecord {

                golden_record_id:
                    row.get("golden_record_id"),

                tenant_id:
                    row.get("tenant_id"),

                entity_type:
                    EntityType::Customer,

                lifecycle_stage:
                    GoldenRecordLifecycleStage::Published,

                status:
                    GoldenRecordStatus::Active,

                source_entities:
                    row
                        .try_get("source_entities")
                        .unwrap_or_default(),

                golden_attributes,

                quality:
                    Some(
                        GoldenRecordQuality {

                            trust_score:
                                row.try_get(
                                    "trust_score"
                                ).ok(),

                            completeness_score:
                                None,

                            consistency_score:
                                None,

                            accuracy_score:
                                None,

                            overall_quality_score:
                                None,
                        }
                    ),

                conflicts:
                    vec![],

                source_contributions:
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

                version_info:
                    VersionInfo {

                        schema_version:
                            "1.0.0".to_string(),

                        contract_version:
                            "1.0.0".to_string(),

                        entity_version:
                            1,
                    },

                audit:
                    AuditMetadata {

                        created_at:
                            row.get("created_at"),

                        updated_at:
                            row.get("updated_at"),

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

                metadata,

                embedding_refs:
                    vec![],

                lineage_refs:
                    vec![],

                merge_refs:
                    vec![],

                workflow_refs:
                    vec![],

                policy_refs:
                    vec![],

                survivorship_refs:
                    vec![],

                approval_refs:
                    vec![],

                valid_from:
                    row.try_get("valid_from").ok(),

                valid_to:
                    row.try_get("valid_to").ok(),
            };

        Ok(Some(record))
    }

    //
    // ====================================
    // FETCH GOLDEN ATTRIBUTES
    // ====================================
    //

    async fn fetch_golden_attributes(
        &self,
        tenant_id: Uuid,
        golden_record_id: Uuid,
    ) -> Result<Vec<GoldenAttribute>> {

        let rows =
            sqlx::query(
                r#"
                SELECT *
                FROM core_mdm.golden_record_attributes
                WHERE tenant_id = $1
                AND golden_record_id = $2
                ORDER BY created_at ASC
                "#
            )
            .bind(tenant_id)
            .bind(golden_record_id)
            .fetch_all(&self.pool)
            .await?;

        let mut attributes =
            Vec::new();

        for row in rows {

            let entity_attribute =
                EntityAttribute {

                    attribute_id:
                        Uuid::new_v4(),

                    key:
                        row.get("attribute_key"),

                    value:
                        row.try_get::<
                            Value,
                            _
                        >(
                            "attribute_value"
                        )
                        .unwrap_or(Value::Null),

                    data_type:
                        "string".to_string(),

                    confidence:
                        None,

                    provenance:
                        None,

                    policy_tags:
                        vec![],

                    semantic_type:
                        None,

                    aliases:
                        vec![],

                    embedding_ref:
                        None,

                    ai_annotations:
                        vec![],

                    searchable:
                        true,

                    indexed:
                        true,

                    encrypted:
                        false,

                    survivorship_eligible:
                        true,

                    updated_at:
                        Some(Utc::now()),

                    attribute_version:
                        1,

                    metadata:
                        MetadataMap::default(),
                };

            attributes.push(
                GoldenAttribute {

                    golden_attribute_id:
                        row.get(
                            "golden_attribute_id"
                        ),

                    attribute:
                        entity_attribute,

                    selected_from_entity:
                        row.get(
                            "selected_from_entity"
                        ),

                    selected_from_source:
                        row
                            .try_get(
                                "selected_from_source"
                            )
                            .ok(),

                    survivorship_rule_id:
                        None,

                    survivorship_execution_id:
                        None,

                    survivorship_score:
                        row
                            .try_get(
                                "survivorship_score"
                            )
                            .ok(),

                    ai_confidence:
                        row
                            .try_get(
                                "ai_confidence"
                            )
                            .ok(),

                    overridden_by_user:
                        None,

                    overridden_at:
                        None,

                    override_reason:
                        None,

                    explainability:
                        row
                            .try_get(
                                "explainability"
                            )
                            .ok(),

                    candidate_entities:
                        vec![],

                    policy_refs:
                        vec![],

                    metadata:
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
                            .unwrap_or_default(),
                }
            );
        }

        Ok(attributes)
    }

    //
    // ====================================
    // DELETE GOLDEN RECORD
    // ====================================
    //

    pub async fn delete_golden_record(
        &self,
        tenant_id: Uuid,
        golden_record_id: Uuid,
    ) -> Result<u64> {

        let result =
            sqlx::query(
                r#"
                DELETE FROM core_mdm.golden_records
                WHERE tenant_id = $1
                AND golden_record_id = $2
                "#
            )
            .bind(tenant_id)
            .bind(golden_record_id)
            .execute(&self.pool)
            .await?;

        Ok(
            result.rows_affected()
        )
    }

    //
    // ====================================
    // COUNT GOLDEN RECORDS
    // ====================================
    //

    pub async fn count_golden_records(
        &self,
        tenant_id: Uuid,
    ) -> Result<i64> {

        let row =
            sqlx::query(
                r#"
                SELECT COUNT(*)
                FROM core_mdm.golden_records
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
    // LIST GOLDEN RECORDS
    // ====================================

    pub async fn list_golden_records(
        &self,
        tenant_id:   Uuid,
        entity_type: Option<&str>,
        limit:       i64,
        offset:      i64,
    ) -> Result<Vec<GoldenRecord>> {
        // Minimal projection — return id + tenant + type + status + lifecycle
        // stage. Callers that need full attributes should call fetch_golden_record.
        let rows = if let Some(etype) = entity_type {
            sqlx::query(
                r#"
                SELECT golden_record_id, tenant_id, entity_type, status,
                       lifecycle_stage, metadata
                FROM core_mdm.golden_records
                WHERE tenant_id   = $1
                  AND entity_type = $2
                  AND valid_to    = 'infinity'
                ORDER BY updated_at DESC
                LIMIT $3 OFFSET $4
                "#,
            )
            .bind(tenant_id)
            .bind(etype)
            .bind(limit)
            .bind(offset)
            .fetch_all(&self.pool)
            .await?
        } else {
            sqlx::query(
                r#"
                SELECT golden_record_id, tenant_id, entity_type, status,
                       lifecycle_stage, metadata
                FROM core_mdm.golden_records
                WHERE tenant_id = $1
                  AND valid_to  = 'infinity'
                ORDER BY updated_at DESC
                LIMIT $2 OFFSET $3
                "#,
            )
            .bind(tenant_id)
            .bind(limit)
            .bind(offset)
            .fetch_all(&self.pool)
            .await?
        };

        // For the list view we return shallow GoldenRecord stubs.
        // fetch_golden_record provides the full record.
        let mut results = Vec::with_capacity(rows.len());
        for row in rows {
            let gid: Uuid = row.try_get("golden_record_id")?;
            if let Some(gr) = self.fetch_golden_record(tenant_id, gid).await? {
                results.push(gr);
            }
        }
        Ok(results)
    }

    // ====================================
    // UPDATE LIFECYCLE STAGE
    // ====================================

    pub async fn update_lifecycle_stage(
        &self,
        tx:               &mut sqlx::Transaction<'_, sqlx::Postgres>,
        tenant_id:        Uuid,
        golden_record_id: Uuid,
        stage:            contracts::mdm::golden_record::GoldenRecordLifecycleStage,
    ) -> Result<()> {
        sqlx::query(
            r#"
            UPDATE core_mdm.golden_records
            SET    lifecycle_stage = $3,
                   updated_at      = NOW()
            WHERE  tenant_id       = $1
            AND    golden_record_id = $2
            "#,
        )
        .bind(tenant_id)
        .bind(golden_record_id)
        .bind(format!("{:?}", stage))
        .execute(&mut **tx)
        .await?;
        Ok(())
    }
}