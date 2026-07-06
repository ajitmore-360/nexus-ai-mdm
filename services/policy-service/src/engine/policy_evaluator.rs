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
    ///
    /// Each DB rule is uploaded to OPA under the key `nexus_rule_{rule_id}`
    /// before evaluation so OPA always has the latest version.  All rules must
    /// declare `package mdm.policy` so OPA merges them into one namespace and
    /// a single `POST /v1/data/mdm/policy` call returns the combined decision.
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

        // Upload each rule to OPA (idempotent PUT) so OPA has the latest rego.
        // Rules use package mdm.policy — OPA merges them; one evaluation covers all.
        let mut applied_rules = Vec::<String>::new();
        for (rule_id, rego) in &rules {
            let policy_key = format!("nexus_rule_{}", rule_id.as_simple());
            if let Err(e) = self.opa.upload_policy(&policy_key, rego).await {
                tracing::warn!(rule_id=%rule_id, error=%e, "failed to upload rule to OPA; skipping");
                continue;
            }
            applied_rules.push(rule_id.to_string());
        }

        if applied_rules.is_empty() {
            return Ok(PolicyDecision::permissive("no rules could be uploaded to OPA"));
        }

        // One evaluation call — OPA aggregates all uploaded mdm.policy rules.
        let decision = self.opa.evaluate("mdm/policy", ctx).await;

        Ok(PolicyDecision {
            allowed:        decision.allowed,
            reason:         decision.reason,
            masked_fields:  { let mut v = decision.masked_fields; v.sort(); v.dedup(); v },
            required_fields: { let mut v = decision.required_fields; v.sort(); v.dedup(); v },
            warnings:       decision.warnings,
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

    /// Remove a rule from OPA when it is deleted or deactivated.
    /// Called by CRUD handlers via `AppState::opa`.
    pub async fn remove_from_opa(&self, rule_id: Uuid) {
        let policy_key = format!("nexus_rule_{}", rule_id.as_simple());
        if let Err(e) = self.opa.delete_policy(&policy_key).await {
            tracing::warn!(rule_id=%rule_id, error=%e, "failed to remove rule from OPA");
        }
    }

    async fn load_active_rules(
        &self,
        tenant_id:   Uuid,
        entity_type: &str,
    ) -> Result<Vec<(Uuid, String)>> {
        let rows = sqlx::query(
            r#"
            SELECT rule_id, rego_policy
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

        Ok(rows.into_iter().filter_map(|r| {
            let rule_id: Uuid   = r.try_get("rule_id").ok()?;
            let rego: String    = r.try_get("rego_policy").ok()?;
            Some((rule_id, rego))
        }).collect())
    }
}
