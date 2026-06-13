use anyhow::Result;
use chrono::Utc;
use sqlx::{PgPool, Row};
use uuid::Uuid;

use crate::models::{CreateRuleRequest, PolicyRule, PolicyRuleStatus, PolicyRuleType};

pub struct PolicyRepository {
    pool: PgPool,
}

impl PolicyRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    pub async fn create_rule(&self, req: CreateRuleRequest) -> Result<Uuid> {
        let rule_id = Uuid::new_v4();
        let now     = Utc::now();

        sqlx::query(
            r#"
            INSERT INTO governance.policy_rules
            (rule_id, tenant_id, name, description, rule_type, entity_type,
             field_name, rego_policy, priority, status, created_at, updated_at)
            VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,'active',$10,$11)
            "#,
        )
        .bind(rule_id)
        .bind(req.tenant_id)
        .bind(&req.name)
        .bind(req.description.as_deref())
        .bind(req.rule_type.to_string())
        .bind(req.entity_type.as_deref())
        .bind(req.field_name.as_deref())
        .bind(&req.rego_policy)
        .bind(req.priority.unwrap_or(100))
        .bind(now)
        .bind(now)
        .execute(&self.pool)
        .await?;

        Ok(rule_id)
    }

    pub async fn list_rules(
        &self,
        tenant_id:   Uuid,
        entity_type: Option<&str>,
    ) -> Result<Vec<PolicyRule>> {
        let rows = if let Some(etype) = entity_type {
            sqlx::query(
                r#"
                SELECT rule_id, tenant_id, name, description, rule_type, entity_type,
                       field_name, rego_policy, priority, status, created_at, updated_at
                FROM governance.policy_rules
                WHERE tenant_id   = $1
                  AND (entity_type IS NULL OR entity_type = $2)
                ORDER BY priority ASC
                "#,
            )
            .bind(tenant_id)
            .bind(etype)
            .fetch_all(&self.pool)
            .await?
        } else {
            sqlx::query(
                r#"
                SELECT rule_id, tenant_id, name, description, rule_type, entity_type,
                       field_name, rego_policy, priority, status, created_at, updated_at
                FROM governance.policy_rules
                WHERE tenant_id = $1
                ORDER BY priority ASC
                "#,
            )
            .bind(tenant_id)
            .fetch_all(&self.pool)
            .await?
        };

        let rules = rows.into_iter().filter_map(|r| {
            let rule_type = r.try_get::<String, _>("rule_type").ok()?.parse::<PolicyRuleType>().ok()?;
            let status    = r.try_get::<String, _>("status").ok()?.parse::<PolicyRuleStatus>().ok()?;
            Some(PolicyRule {
                rule_id:     r.try_get("rule_id").ok()?,
                tenant_id:   r.try_get("tenant_id").ok()?,
                name:        r.try_get("name").unwrap_or_default(),
                description: r.try_get("description").ok().flatten(),
                rule_type,
                entity_type: r.try_get("entity_type").ok().flatten(),
                field_name:  r.try_get("field_name").ok().flatten(),
                rego_policy: r.try_get("rego_policy").unwrap_or_default(),
                priority:    r.try_get("priority").unwrap_or(100),
                status,
                created_at:  r.try_get("created_at").unwrap_or_else(|_| Utc::now()),
                updated_at:  r.try_get("updated_at").unwrap_or_else(|_| Utc::now()),
            })
        }).collect();

        Ok(rules)
    }

    pub async fn delete_rule(&self, rule_id: Uuid, tenant_id: Uuid) -> Result<bool> {
        let result = sqlx::query(
            "DELETE FROM governance.policy_rules WHERE rule_id = $1 AND tenant_id = $2",
        )
        .bind(rule_id)
        .bind(tenant_id)
        .execute(&self.pool)
        .await?;

        Ok(result.rows_affected() > 0)
    }

    #[allow(dead_code)]
    pub async fn update_status(
        &self,
        rule_id:   Uuid,
        tenant_id: Uuid,
        status:    &str,
    ) -> Result<()> {
        sqlx::query(
            "UPDATE governance.policy_rules SET status = $3, updated_at = NOW() WHERE rule_id = $1 AND tenant_id = $2",
        )
        .bind(rule_id)
        .bind(tenant_id)
        .bind(status)
        .execute(&self.pool)
        .await?;
        Ok(())
    }
}
