use std::sync::Arc;

use anyhow::Result;
use sqlx::{PgPool, Row};
use tracing::instrument;
use uuid::Uuid;

use crate::engine::opa_client::OpaClient;
use crate::models::{PolicyContext, PolicyDecision};

pub struct PolicyEvaluator {
    pool: PgPool,
    opa:  Arc<OpaClient>,
}

impl PolicyEvaluator {
    pub fn new(pool: PgPool, opa: Arc<OpaClient>) -> Self {
        Self { pool, opa }
    }

    /// Main evaluation entry-point: evaluate all active rules for the tenant
    /// and aggregate the decisions (any deny → denied, union of masks).
    #[instrument(skip(self, ctx), fields(
        tenant_id   = %ctx.tenant_id,
        entity_type = %ctx.entity_type,
        operation   = %ctx.operation,
    ))]
    pub async fn evaluate(&self, ctx: &PolicyContext) -> Result<PolicyDecision> {
        let rules = self.load_active_rules(ctx.tenant_id, &ctx.entity_type).await?;

        if rules.is_empty() {
            return Ok(PolicyDecision::permissive("no active rules for this context"));
        }

        let mut allowed         = true;
        let mut reason          = String::new();
        let mut masked_fields   = Vec::<String>::new();
        let mut required_fields = Vec::<String>::new();
        let mut warnings        = Vec::<String>::new();
        let mut applied_rules   = Vec::<String>::new();

        for rule_rego in &rules {
            let decision = self.opa.evaluate("mdm/policy", ctx).await;
            applied_rules.push(rule_rego.clone());

            if !decision.allowed {
                allowed = false;
                reason  = decision.reason.clone();
            }
            masked_fields.extend(decision.masked_fields);
            required_fields.extend(decision.required_fields);
            warnings.extend(decision.warnings);
        }

        masked_fields.sort();
        masked_fields.dedup();
        required_fields.sort();
        required_fields.dedup();

        Ok(PolicyDecision {
            allowed,
            reason: if allowed { "allowed by all active rules".into() } else { reason },
            masked_fields,
            required_fields,
            warnings,
            applied_rules,
        })
    }

    /// Mask PII fields on an entity value in-place.
    #[allow(dead_code)]
    pub fn mask_entity(
        entity:       &mut serde_json::Value,
        masked_fields: &[String],
    ) {
        if let Some(obj) = entity.as_object_mut() {
            for field in masked_fields {
                if let Some(v) = obj.get_mut(field) {
                    if !v.is_null() {
                        *v = serde_json::Value::String("***MASKED***".into());
                    }
                }
            }
        }
    }

    async fn load_active_rules(
        &self,
        tenant_id:   Uuid,
        entity_type: &str,
    ) -> Result<Vec<String>> {
        let rows = sqlx::query(
            r#"
            SELECT rego_policy
            FROM governance.policy_rules
            WHERE tenant_id  = $1
              AND (entity_type IS NULL OR entity_type = $2)
              AND status = 'active'
            ORDER BY priority ASC
            "#,
        )
        .bind(tenant_id)
        .bind(entity_type)
        .fetch_all(&self.pool)
        .await?;

        Ok(rows.into_iter()
            .map(|r| r.try_get::<String, _>("rego_policy").unwrap_or_default())
            .collect())
    }
}
