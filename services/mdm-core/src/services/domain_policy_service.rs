use anyhow::Result;
use sqlx::{PgPool, Row};
use uuid::Uuid;

use crate::matching::policy::MatchingPolicy;

pub struct DomainPolicyService {
    db: PgPool,
}

impl DomainPolicyService {
    pub fn new(db: PgPool) -> Self {
        Self { db }
    }

    /// Fetch a domain-level policy override for (tenant, entity_type_code).
    /// Returns `None` when no active row exists.
    pub async fn get_policy(
        &self,
        tenant_id: Uuid,
        entity_type_code: &str,
    ) -> Result<Option<MatchingPolicy>> {
        let row = sqlx::query(
            r#"
            SELECT
                auto_merge_threshold,
                review_threshold,
                ambiguity_delta,
                exact_weight,
                fuzzy_weight,
                phonetic_weight,
                semantic_weight,
                vector_weight,
                master_weight_score,
                master_weight_confidence,
                master_weight_centrality,
                max_clusters
            FROM core_mdm.domain_matching_policies
            WHERE tenant_id = $1
              AND entity_type_code = $2
              AND is_active = TRUE
            LIMIT 1
            "#,
        )
        .bind(tenant_id)
        .bind(entity_type_code)
        .fetch_optional(&self.db)
        .await?;

        match row {
            None => Ok(None),
            Some(r) => Ok(Some(MatchingPolicy {
                auto_merge_threshold:    r.get::<f32, _>("auto_merge_threshold"),
                review_threshold:        r.get::<f32, _>("review_threshold"),
                ambiguity_delta:         r.get::<f32, _>("ambiguity_delta"),
                exact_weight:            r.get::<f32, _>("exact_weight"),
                fuzzy_weight:            r.get::<f32, _>("fuzzy_weight"),
                phonetic_weight:         r.get::<f32, _>("phonetic_weight"),
                semantic_weight:         r.get::<f32, _>("semantic_weight"),
                vector_weight:           r.get::<f32, _>("vector_weight"),
                master_weight_score:     r.get::<f32, _>("master_weight_score"),
                master_weight_confidence: r.get::<f32, _>("master_weight_confidence"),
                master_weight_centrality: r.get::<f32, _>("master_weight_centrality"),
                max_clusters:            r.get::<i32, _>("max_clusters") as usize,
            })),
        }
    }

    /// Return the domain policy for this (tenant, entity_type_code) if one exists,
    /// otherwise clone the supplied global policy as a fallback.
    pub async fn resolve(
        &self,
        tenant_id: Uuid,
        entity_type_code: &str,
        global: &MatchingPolicy,
    ) -> Result<MatchingPolicy> {
        match self.get_policy(tenant_id, entity_type_code).await? {
            Some(domain) => Ok(domain),
            None => Ok(global.clone()),
        }
    }

    /// List all active domain policies for a tenant as JSON-serialisable values.
    pub async fn list(&self, tenant_id: Uuid) -> Result<Vec<serde_json::Value>> {
        let rows = sqlx::query(
            r#"
            SELECT
                entity_type_code,
                description,
                is_active,
                auto_merge_threshold,
                review_threshold,
                ambiguity_delta,
                exact_weight,
                fuzzy_weight,
                phonetic_weight,
                semantic_weight,
                vector_weight,
                master_weight_score,
                master_weight_confidence,
                master_weight_centrality,
                max_clusters,
                created_at,
                updated_at
            FROM core_mdm.domain_matching_policies
            WHERE tenant_id = $1
            ORDER BY entity_type_code
            "#,
        )
        .bind(tenant_id)
        .fetch_all(&self.db)
        .await?;

        let result = rows
            .into_iter()
            .map(|r| {
                serde_json::json!({
                    "entity_type_code":        r.get::<String, _>("entity_type_code"),
                    "description":             r.get::<Option<String>, _>("description"),
                    "is_active":               r.get::<bool, _>("is_active"),
                    "auto_merge_threshold":    r.get::<f32, _>("auto_merge_threshold"),
                    "review_threshold":        r.get::<f32, _>("review_threshold"),
                    "ambiguity_delta":         r.get::<f32, _>("ambiguity_delta"),
                    "exact_weight":            r.get::<f32, _>("exact_weight"),
                    "fuzzy_weight":            r.get::<f32, _>("fuzzy_weight"),
                    "phonetic_weight":         r.get::<f32, _>("phonetic_weight"),
                    "semantic_weight":         r.get::<f32, _>("semantic_weight"),
                    "vector_weight":           r.get::<f32, _>("vector_weight"),
                    "master_weight_score":     r.get::<f32, _>("master_weight_score"),
                    "master_weight_confidence": r.get::<f32, _>("master_weight_confidence"),
                    "master_weight_centrality": r.get::<f32, _>("master_weight_centrality"),
                    "max_clusters":            r.get::<i32, _>("max_clusters"),
                    "created_at":              r.get::<chrono::DateTime<chrono::Utc>, _>("created_at").to_rfc3339(),
                    "updated_at":              r.get::<chrono::DateTime<chrono::Utc>, _>("updated_at").to_rfc3339(),
                })
            })
            .collect();

        Ok(result)
    }

    /// Insert or update a domain policy row.
    /// Uses ON CONFLICT (tenant_id, entity_type_code) to upsert in place.
    pub async fn upsert(
        &self,
        tenant_id: Uuid,
        entity_type_code: &str,
        policy: &MatchingPolicy,
        description: Option<&str>,
    ) -> Result<()> {
        sqlx::query(
            r#"
            INSERT INTO core_mdm.domain_matching_policies (
                tenant_id,
                entity_type_code,
                description,
                is_active,
                auto_merge_threshold,
                review_threshold,
                ambiguity_delta,
                exact_weight,
                fuzzy_weight,
                phonetic_weight,
                semantic_weight,
                vector_weight,
                master_weight_score,
                master_weight_confidence,
                master_weight_centrality,
                max_clusters,
                created_at,
                updated_at
            )
            VALUES (
                $1, $2, $3, TRUE,
                $4, $5, $6,
                $7, $8, $9, $10, $11,
                $12, $13, $14,
                $15,
                NOW(), NOW()
            )
            ON CONFLICT (tenant_id, entity_type_code) DO UPDATE SET
                description              = EXCLUDED.description,
                is_active                = TRUE,
                auto_merge_threshold     = EXCLUDED.auto_merge_threshold,
                review_threshold         = EXCLUDED.review_threshold,
                ambiguity_delta          = EXCLUDED.ambiguity_delta,
                exact_weight             = EXCLUDED.exact_weight,
                fuzzy_weight             = EXCLUDED.fuzzy_weight,
                phonetic_weight          = EXCLUDED.phonetic_weight,
                semantic_weight          = EXCLUDED.semantic_weight,
                vector_weight            = EXCLUDED.vector_weight,
                master_weight_score      = EXCLUDED.master_weight_score,
                master_weight_confidence = EXCLUDED.master_weight_confidence,
                master_weight_centrality = EXCLUDED.master_weight_centrality,
                max_clusters             = EXCLUDED.max_clusters,
                updated_at               = NOW()
            "#,
        )
        .bind(tenant_id)
        .bind(entity_type_code)
        .bind(description)
        .bind(policy.auto_merge_threshold)
        .bind(policy.review_threshold)
        .bind(policy.ambiguity_delta)
        .bind(policy.exact_weight)
        .bind(policy.fuzzy_weight)
        .bind(policy.phonetic_weight)
        .bind(policy.semantic_weight)
        .bind(policy.vector_weight)
        .bind(policy.master_weight_score)
        .bind(policy.master_weight_confidence)
        .bind(policy.master_weight_centrality)
        .bind(policy.max_clusters as i32)
        .execute(&self.db)
        .await?;

        Ok(())
    }

    /// Delete the domain policy for (tenant, entity_type_code).
    /// Returns `true` if a row was actually deleted, `false` if none existed.
    pub async fn delete(
        &self,
        tenant_id: Uuid,
        entity_type_code: &str,
    ) -> Result<bool> {
        let result = sqlx::query(
            r#"
            DELETE FROM core_mdm.domain_matching_policies
            WHERE tenant_id = $1
              AND entity_type_code = $2
            "#,
        )
        .bind(tenant_id)
        .bind(entity_type_code)
        .execute(&self.db)
        .await?;

        Ok(result.rows_affected() > 0)
    }
}
