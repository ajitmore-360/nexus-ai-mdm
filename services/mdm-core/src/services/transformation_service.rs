use anyhow::{anyhow, Result};
use regex::Regex;
use serde_json::{json, Value};
use sqlx::PgPool;
use uuid::Uuid;

pub struct TransformationService {
    db: PgPool,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct CreateRuleInput {
    pub rule_name:      String,
    pub description:    Option<String>,
    pub entity_type:    Option<String>,
    pub attribute_name: String,
    pub transform_fn:   String,
    pub params:         Value,
    pub priority:       Option<i16>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct TransformResult {
    pub entity_id:      Uuid,
    pub attribute_name: String,
    pub value_before:   Option<String>,
    pub value_after:    Option<String>,
    pub rules_applied:  Vec<String>,
}

impl TransformationService {
    pub fn new(db: PgPool) -> Self {
        Self { db }
    }

    // ── Rule CRUD ─────────────────────────────────────────────────────────────

    pub async fn create_rule(
        &self,
        tenant_id: Uuid,
        input:     CreateRuleInput,
        actor_id:  Option<Uuid>,
    ) -> Result<Value> {
        let mut tx = self.db.begin().await?;
        sqlx::query("SELECT set_config('app.current_tenant', $1, true)")
            .bind(tenant_id.to_string())
            .execute(&mut *tx)
            .await?;

        let row = sqlx::query(
            r#"
            INSERT INTO core_mdm.transformation_rules
                (tenant_id, rule_name, description, entity_type, attribute_name,
                 transform_fn, params, priority, created_by)
            VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
            RETURNING id, rule_name, entity_type, attribute_name, transform_fn, params, priority, is_active
            "#,
        )
        .bind(tenant_id)
        .bind(&input.rule_name)
        .bind(input.description.as_deref())
        .bind(input.entity_type.as_deref())
        .bind(&input.attribute_name)
        .bind(&input.transform_fn)
        .bind(&input.params)
        .bind(input.priority.unwrap_or(100))
        .bind(actor_id)
        .fetch_one(&mut *tx)
        .await;

        use sqlx::Row;
        let r = row.map_err(|e| anyhow!(e))?;
        tx.commit().await?;
        Ok(json!({
            "id":             r.get::<Uuid, _>("id"),
            "rule_name":      r.get::<String, _>("rule_name"),
            "entity_type":    r.get::<Option<String>, _>("entity_type"),
            "attribute_name": r.get::<String, _>("attribute_name"),
            "transform_fn":   r.get::<String, _>("transform_fn"),
            "params":         r.get::<Value, _>("params"),
            "priority":       r.get::<i16, _>("priority"),
            "is_active":      r.get::<bool, _>("is_active"),
        }))
    }

    pub async fn list_rules(
        &self,
        tenant_id:   Uuid,
        entity_type: Option<&str>,
    ) -> Result<Vec<Value>> {
        use sqlx::Row;

        let query = match entity_type {
            Some(et) => sqlx::query(
                r#"
                SELECT id, rule_name, description, entity_type, attribute_name,
                       transform_fn, params, priority, is_active, created_at
                FROM core_mdm.transformation_rules
                WHERE tenant_id = $1 AND (entity_type IS NULL OR entity_type = $2)
                ORDER BY attribute_name, priority
                "#,
            )
            .bind(tenant_id)
            .bind(et)
            .fetch_all(&self.db)
            .await?,
            None => sqlx::query(
                r#"
                SELECT id, rule_name, description, entity_type, attribute_name,
                       transform_fn, params, priority, is_active, created_at
                FROM core_mdm.transformation_rules
                WHERE tenant_id = $1
                ORDER BY attribute_name, priority
                "#,
            )
            .bind(tenant_id)
            .fetch_all(&self.db)
            .await?,
        };

        Ok(query.iter().map(|r| json!({
            "id":             r.get::<Uuid, _>("id"),
            "rule_name":      r.get::<String, _>("rule_name"),
            "description":    r.get::<Option<String>, _>("description"),
            "entity_type":    r.get::<Option<String>, _>("entity_type"),
            "attribute_name": r.get::<String, _>("attribute_name"),
            "transform_fn":   r.get::<String, _>("transform_fn"),
            "params":         r.get::<Value, _>("params"),
            "priority":       r.get::<i16, _>("priority"),
            "is_active":      r.get::<bool, _>("is_active"),
            "created_at":     r.get::<chrono::DateTime<chrono::Utc>, _>("created_at"),
        })).collect())
    }

    pub async fn toggle_rule(&self, tenant_id: Uuid, rule_id: Uuid) -> Result<bool> {
        let row = sqlx::query_scalar::<_, bool>(
            r#"
            UPDATE core_mdm.transformation_rules
            SET is_active = NOT is_active, updated_at = NOW()
            WHERE id = $1 AND tenant_id = $2
            RETURNING is_active
            "#,
        )
        .bind(rule_id)
        .bind(tenant_id)
        .fetch_optional(&self.db)
        .await?;

        row.ok_or_else(|| anyhow!("rule not found"))
    }

    pub async fn delete_rule(&self, tenant_id: Uuid, rule_id: Uuid) -> Result<bool> {
        let r = sqlx::query(
            "DELETE FROM core_mdm.transformation_rules WHERE id = $1 AND tenant_id = $2",
        )
        .bind(rule_id)
        .bind(tenant_id)
        .execute(&self.db)
        .await?;
        Ok(r.rows_affected() > 0)
    }

    // ── Apply rules to an entity ──────────────────────────────────────────────

    /// Apply all active rules for the given entity_type to entity attributes.
    /// Returns list of changes made; writes audit log entries.
    pub async fn apply_rules(
        &self,
        tenant_id:   Uuid,
        entity_id:   Uuid,
        entity_type: &str,
        attributes:  &mut Value,
    ) -> Result<Vec<TransformResult>> {
        use sqlx::Row;

        let rules = sqlx::query(
            r#"
            SELECT id, attribute_name, transform_fn, params
            FROM core_mdm.transformation_rules
            WHERE tenant_id = $1
              AND is_active  = true
              AND (entity_type IS NULL OR entity_type = $2)
            ORDER BY attribute_name, priority
            "#,
        )
        .bind(tenant_id)
        .bind(entity_type)
        .fetch_all(&self.db)
        .await?;

        let mut results: Vec<TransformResult> = Vec::new();

        // Group by attribute, collect rules in order
        for rule_row in &rules {
            let rule_id:   Uuid   = rule_row.get("id");
            let attr:      String = rule_row.get("attribute_name");
            let fn_name:   String = rule_row.get("transform_fn");
            let params:    Value  = rule_row.get("params");

            let original = attributes.get(&attr).and_then(|v| v.as_str()).map(String::from);
            if let Some(original_val) = &original {
                let transformed = apply_fn(original_val, &fn_name, &params)?;
                if transformed != *original_val {
                    // Update attribute in place
                    if let Some(obj) = attributes.as_object_mut() {
                        obj.insert(attr.clone(), Value::String(transformed.clone()));
                    }
                    // Write audit log
                    let _ = sqlx::query(
                        r#"
                        INSERT INTO core_mdm.transformation_log
                            (tenant_id, entity_id, rule_id, attribute_name, value_before, value_after)
                        VALUES ($1,$2,$3,$4,$5,$6)
                        "#,
                    )
                    .bind(tenant_id)
                    .bind(entity_id)
                    .bind(rule_id)
                    .bind(&attr)
                    .bind(original_val)
                    .bind(&transformed)
                    .execute(&self.db)
                    .await;

                    // Accumulate result per attribute (merge rule names)
                    if let Some(existing) = results.iter_mut().find(|r| r.attribute_name == attr) {
                        existing.value_after = Some(transformed);
                        existing.rules_applied.push(fn_name);
                    } else {
                        results.push(TransformResult {
                            entity_id,
                            attribute_name: attr,
                            value_before:   original.clone(),
                            value_after:    Some(transformed),
                            rules_applied:  vec![fn_name],
                        });
                    }
                }
            }
        }

        Ok(results)
    }

    // ── Preview (dry-run) ─────────────────────────────────────────────────────

    /// Preview transformation result without persisting anything.
    pub async fn preview(
        &self,
        tenant_id:   Uuid,
        entity_type: &str,
        attributes:  &Value,
    ) -> Result<Vec<Value>> {
        use sqlx::Row;

        let rules = sqlx::query(
            r#"
            SELECT attribute_name, transform_fn, params, rule_name
            FROM core_mdm.transformation_rules
            WHERE tenant_id = $1
              AND is_active  = true
              AND (entity_type IS NULL OR entity_type = $2)
            ORDER BY attribute_name, priority
            "#,
        )
        .bind(tenant_id)
        .bind(entity_type)
        .fetch_all(&self.db)
        .await?;

        let mut preview_attrs = attributes.clone();
        let mut changes: Vec<Value> = Vec::new();

        for rule_row in &rules {
            let attr:      String = rule_row.get("attribute_name");
            let fn_name:   String = rule_row.get("transform_fn");
            let params:    Value  = rule_row.get("params");
            let rule_name: String = rule_row.get("rule_name");

            let original = preview_attrs.get(&attr).and_then(|v| v.as_str()).map(String::from);
            if let Some(original_val) = &original {
                let transformed = apply_fn(original_val, &fn_name, &params)?;
                if transformed != *original_val {
                    if let Some(obj) = preview_attrs.as_object_mut() {
                        obj.insert(attr.clone(), Value::String(transformed.clone()));
                    }
                    changes.push(json!({
                        "attribute":     attr,
                        "rule_name":     rule_name,
                        "transform_fn":  fn_name,
                        "value_before":  original_val,
                        "value_after":   transformed,
                    }));
                }
            }
        }

        Ok(changes)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Transformation function implementations
// ─────────────────────────────────────────────────────────────────────────────

fn apply_fn(value: &str, fn_name: &str, params: &Value) -> Result<String> {
    match fn_name {
        "trim"             => Ok(value.trim().to_string()),
        "uppercase"        => Ok(value.to_uppercase()),
        "lowercase"        => Ok(value.to_lowercase()),
        "title_case"       => Ok(to_title_case(value)),
        "normalize_phone"  => Ok(normalize_phone(value, params)),
        "normalize_email"  => Ok(value.trim().to_lowercase()),
        "normalize_date"   => normalize_date(value, params),
        "strip_punctuation"=> Ok(value.chars().filter(|c| c.is_alphanumeric() || c.is_whitespace()).collect()),
        "extract_digits"   => Ok(value.chars().filter(|c| c.is_ascii_digit()).collect()),
        "regex_replace"    => regex_replace(value, params),
        "map_value"        => Ok(map_value(value, params)),
        "default_if_empty" => Ok(if value.trim().is_empty() {
            params.get("default").and_then(|v| v.as_str()).unwrap_or("").to_string()
        } else {
            value.to_string()
        }),
        "truncate" => {
            let max = params.get("length").and_then(|v| v.as_u64()).unwrap_or(255) as usize;
            Ok(value.chars().take(max).collect())
        }
        "pad_left" => {
            let len = params.get("length").and_then(|v| v.as_u64()).unwrap_or(10) as usize;
            let ch  = params.get("char").and_then(|v| v.as_str()).unwrap_or("0").chars().next().unwrap_or('0');
            Ok(format!("{:>width$}", value, width = len).replacen(' ', &ch.to_string(), len))
        }
        "pad_right" => {
            let len = params.get("length").and_then(|v| v.as_u64()).unwrap_or(10) as usize;
            let ch  = params.get("char").and_then(|v| v.as_str()).unwrap_or(" ").chars().next().unwrap_or(' ');
            let s: String = value.chars().collect();
            let pad = if s.len() < len { ch.to_string().repeat(len - s.len()) } else { String::new() };
            Ok(format!("{}{}", s, pad))
        }
        "remove_whitespace" => Ok(value.chars().filter(|c| !c.is_whitespace()).collect()),
        other => Err(anyhow!("unknown transform function: {}", other)),
    }
}

fn to_title_case(s: &str) -> String {
    s.split_whitespace()
        .map(|word| {
            let mut chars = word.chars();
            match chars.next() {
                None    => String::new(),
                Some(c) => c.to_uppercase().collect::<String>() + &chars.as_str().to_lowercase(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn normalize_phone(value: &str, params: &Value) -> String {
    let digits: String = value.chars().filter(|c| c.is_ascii_digit()).collect();
    let country_code = params.get("country_code").and_then(|v| v.as_str()).unwrap_or("+1");

    match digits.len() {
        10 => format!("{}-{}-{}-{}", country_code, &digits[..3], &digits[3..6], &digits[6..]),
        11 if digits.starts_with('1') => {
            let d = &digits[1..];
            format!("+1-{}-{}-{}", &d[..3], &d[3..6], &d[6..])
        }
        _ => digits, // can't normalize, return digits only
    }
}

fn normalize_date(value: &str, params: &Value) -> Result<String> {
    let target_format = params.get("format").and_then(|v| v.as_str()).unwrap_or("%Y-%m-%d");
    // Try common input formats
    let formats = ["%Y-%m-%d", "%m/%d/%Y", "%d/%m/%Y", "%d-%m-%Y", "%Y%m%d", "%d.%m.%Y"];
    for fmt in &formats {
        if let Ok(dt) = chrono::NaiveDate::parse_from_str(value.trim(), fmt) {
            return Ok(dt.format(target_format).to_string());
        }
    }
    Ok(value.to_string()) // return as-is if unparseable
}

fn regex_replace(value: &str, params: &Value) -> Result<String> {
    let pattern     = params.get("pattern").and_then(|v| v.as_str()).unwrap_or("");
    let replacement = params.get("replacement").and_then(|v| v.as_str()).unwrap_or("");
    let re = Regex::new(pattern).map_err(|e| anyhow!("invalid regex pattern: {}", e))?;
    Ok(re.replace_all(value, replacement).to_string())
}

fn map_value(value: &str, params: &Value) -> String {
    params.get("map")
        .and_then(|m| m.get(value))
        .and_then(|v| v.as_str())
        .unwrap_or(value)
        .to_string()
}
