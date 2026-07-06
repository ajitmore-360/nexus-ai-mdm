use sqlx::PgPool;
use uuid::Uuid;
use tracing::warn;

pub struct DataQualityService {
    db: PgPool,
}

impl DataQualityService {
    pub fn new(db: PgPool) -> Self {
        Self { db }
    }

    /// Compute a completeness score for an entity based on how many required
    /// attributes (as defined in the entity type schema) are actually populated.
    ///
    /// Writes the result back to `core_mdm.entities.trust_score`.
    /// Returns the score in [0, 1] or 0.8 when no required attributes are defined.
    ///
    /// This is intentionally fire-and-forget from the caller's perspective — use
    /// `compute_and_update_background` to avoid blocking the request path.
    pub async fn compute_and_update(
        &self,
        tenant_id: Uuid,
        entity_id: Uuid,
    ) -> Result<f32, sqlx::Error> {
        // Count required attributes defined for this entity's type.
        let required: i64 = sqlx::query_scalar::<_, i64>(
            r#"
            SELECT COUNT(eta.id)
            FROM   core_mdm.entity_type_attributes eta
            JOIN   core_mdm.entity_type_configs    etcfg
                       ON  etcfg.id         = eta.entity_type_config_id
                       AND etcfg.tenant_id  = eta.tenant_id
            JOIN   core_mdm.entities               e
                       ON  e.entity_type::TEXT = etcfg.code
                       AND e.tenant_id         = etcfg.tenant_id
            WHERE  e.entity_id    = $1
              AND  e.tenant_id    = $2
              AND  eta.is_required = TRUE
            "#,
        )
        .bind(entity_id)
        .bind(tenant_id)
        .fetch_one(&self.db)
        .await
        .unwrap_or(0);

        if required == 0 {
            return Ok(0.8);
        }

        // Count how many of those required attributes are actually filled.
        let filled: i64 = sqlx::query_scalar::<_, i64>(
            r#"
            SELECT COUNT(eta.id)
            FROM   core_mdm.entity_type_attributes eta
            JOIN   core_mdm.entity_type_configs    etcfg
                       ON  etcfg.id         = eta.entity_type_config_id
                       AND etcfg.tenant_id  = eta.tenant_id
            JOIN   core_mdm.entities               e
                       ON  e.entity_type::TEXT = etcfg.code
                       AND e.tenant_id         = etcfg.tenant_id
            JOIN   core_mdm.entity_attributes      ea
                       ON  ea.entity_id      = e.entity_id
                       AND ea.attribute_key  = eta.attribute_key
                       AND ea.tenant_id      = e.tenant_id
                       AND ea.value IS NOT NULL
                       AND ea.value::TEXT   <> 'null'
            WHERE  e.entity_id    = $1
              AND  e.tenant_id    = $2
              AND  eta.is_required = TRUE
            "#,
        )
        .bind(entity_id)
        .bind(tenant_id)
        .fetch_one(&self.db)
        .await
        .unwrap_or(0);

        let score = (filled as f32 / required as f32).clamp(0.0, 1.0);

        if let Err(e) = sqlx::query(
            "UPDATE core_mdm.entities \
             SET trust_score = $1, updated_at = NOW() \
             WHERE entity_id = $2 AND tenant_id = $3",
        )
        .bind(score)
        .bind(entity_id)
        .bind(tenant_id)
        .execute(&self.db)
        .await
        {
            warn!(error=%e, entity_id=%entity_id, "trust_score update failed");
        }

        Ok(score)
    }

    /// Non-blocking variant — spawns a Tokio task.  Errors are only logged.
    pub fn compute_and_update_background(&self, tenant_id: Uuid, entity_id: Uuid) {
        let db = self.db.clone();
        let svc = DataQualityService { db };
        tokio::spawn(async move {
            if let Err(e) = svc.compute_and_update(tenant_id, entity_id).await {
                warn!(error=%e, entity_id=%entity_id, "background quality score failed");
            }
        });
    }
}
