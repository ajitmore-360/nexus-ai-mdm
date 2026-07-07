use std::collections::HashMap;
use std::sync::OnceLock;

use regex::Regex;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sqlx::{PgPool, Row};
use tracing::warn;
use uuid::Uuid;

// ─────────────────────────────────────────────────────────────────────────────
// Domain types
// ─────────────────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QualityCondition {
    pub field:            String,
    pub operator:         String,
    pub value:            Option<String>,
    /// Second field name used by cross-field operators (postal_city_match,
    /// postal_format_valid when country comes from another attribute).
    #[serde(default)]
    pub reference_field:  Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QualityRule {
    pub id:          Uuid,
    pub tenant_id:   Uuid,
    pub name:        String,
    pub entity_type: String,
    pub dimension:   String,
    pub conditions:  Vec<QualityCondition>,
    pub logical_op:  String,
    pub action:      String,
    pub severity:    String,
    pub priority:    i32,
    pub is_active:   bool,
    pub created_by:  Option<Uuid>,
    pub created_at:  chrono::DateTime<chrono::Utc>,
    pub updated_at:  chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ViolatedField {
    pub field:   String,
    pub message: String,
}

#[derive(Debug, Clone)]
pub struct RuleCheckResult {
    pub rule_id:         Uuid,
    pub rule_name:       String,
    pub action:          String,
    pub severity:        String,
    pub violated_fields: Vec<ViolatedField>,
    pub rule_snapshot:   Value,
}

pub struct CheckOutcome {
    /// True when any `reject` or `quarantine` rule fired.
    pub blocking:   bool,
    pub violations: Vec<RuleCheckResult>,
}

// ─────────────────────────────────────────────────────────────────────────────
// Condition evaluation (pure, no I/O)
// ─────────────────────────────────────────────────────────────────────────────

fn get_str(attrs: &HashMap<String, Value>, field: &str) -> Option<String> {
    attrs.get(field).and_then(|v| match v {
        Value::String(s) => Some(s.clone()),
        Value::Null      => None,
        other            => Some(other.to_string()),
    })
}

fn eval_condition(cond: &QualityCondition, attrs: &HashMap<String, Value>) -> (bool, String) {
    let val = get_str(attrs, &cond.field);
    let cval = cond.value.as_deref().unwrap_or("");

    match cond.operator.as_str() {
        "is_not_empty" => {
            let ok = val.as_deref().map(|s| !s.trim().is_empty()).unwrap_or(false);
            (ok, format!("'{}' must not be empty", cond.field))
        }
        "is_empty" => {
            let ok = val.as_deref().map(|s| s.trim().is_empty()).unwrap_or(true);
            (ok, format!("'{}' must be empty", cond.field))
        }
        "equals" => {
            let ok = val.as_deref() == Some(cval);
            (ok, format!("'{}' must equal '{}'", cond.field, cval))
        }
        "not_equals" => {
            let ok = val.as_deref() != Some(cval);
            (ok, format!("'{}' must not equal '{}'", cond.field, cval))
        }
        "contains" => {
            let ok = val.as_ref().map(|s| s.contains(cval)).unwrap_or(false);
            (ok, format!("'{}' must contain '{}'", cond.field, cval))
        }
        "starts_with" => {
            let ok = val.as_ref().map(|s| s.starts_with(cval)).unwrap_or(false);
            (ok, format!("'{}' must start with '{}'", cond.field, cval))
        }
        "matches" => {
            // Cache compiled regexes to avoid recompilation on every entity check.
            static CACHE: OnceLock<std::sync::Mutex<HashMap<String, Option<Regex>>>> =
                OnceLock::new();
            let cache = CACHE.get_or_init(|| std::sync::Mutex::new(HashMap::new()));
            let compiled = {
                let mut lock = cache.lock().unwrap_or_else(|p| p.into_inner());
                lock.entry(cval.to_string())
                    .or_insert_with(|| Regex::new(cval).ok())
                    .clone()
            };
            let ok = match (compiled, val.as_ref()) {
                (Some(re), Some(s)) => re.is_match(s),
                _                   => false,
            };
            (ok, format!("'{}' must match pattern '{}'", cond.field, cval))
        }
        "greater_than" => {
            let threshold: f64 = cval.parse().unwrap_or(0.0);
            let actual: f64 = val.as_deref().unwrap_or("0").parse().unwrap_or(f64::NEG_INFINITY);
            let ok = actual > threshold;
            (ok, format!("'{}' must be greater than {}", cond.field, threshold))
        }
        "less_than" => {
            let threshold: f64 = cval.parse().unwrap_or(0.0);
            let actual: f64 = val.as_deref().unwrap_or("0").parse().unwrap_or(f64::INFINITY);
            let ok = actual < threshold;
            (ok, format!("'{}' must be less than {}", cond.field, threshold))
        }

        // ── IBAN validation (MOD-97 algorithm — no network call) ─────────────
        "iban_valid" => {
            let ok = val.as_deref().map(|s| validate_iban(s)).unwrap_or(false);
            (ok, format!("'{}' is not a valid IBAN", cond.field))
        }

        // ── Postal code format per country ───────────────────────────────────
        // `value` = literal country code (e.g. "GB"), OR
        // resolved externally when reference_field is set (see evaluate_rule).
        "postal_format_valid" => {
            let country = cval.to_uppercase();
            let ok = val.as_deref()
                .map(|pc| postal_format_ok(&country, pc))
                .unwrap_or(false);
            (ok, format!("'{}' is not a valid postal code for country '{}'", cond.field, country))
        }

        // postal_city_match requires a DB lookup — handled in evaluate_rule_async.
        // If somehow called synchronously, pass through.
        "postal_city_match" => (true, String::new()),

        _ => (true, String::new()), // unknown operator — always pass (forward compat)
    }
}

// ── IBAN validator (pure, no dependencies) ────────────────────────────────────

fn validate_iban(raw: &str) -> bool {
    // Normalise: remove spaces, uppercase
    let iban: String = raw.chars().filter(|c| !c.is_whitespace()).collect::<String>().to_uppercase();
    if iban.len() < 5 || iban.len() > 34 { return false; }

    // Each country has a defined IBAN length; we enforce a general length bound
    // and let the MOD-97 checksum catch structural errors.
    // Rearrange: move first 4 chars to end
    let rearranged = format!("{}{}", &iban[4..], &iban[..4]);

    // Replace letters with digits (A=10 … Z=35)
    let numeric: String = rearranged.chars().map(|c| {
        if c.is_ascii_alphabetic() {
            format!("{}", c as u32 - 'A' as u32 + 10)
        } else {
            c.to_string()
        }
    }).collect();

    // Compute MOD 97 in chunks to avoid overflow
    let mut remainder: u64 = 0;
    for ch in numeric.chars() {
        if let Some(d) = ch.to_digit(10) {
            remainder = (remainder * 10 + d as u64) % 97;
        } else {
            return false;
        }
    }
    remainder == 1
}

// ── Postal code format patterns per country ───────────────────────────────────

fn postal_format_ok(country: &str, postal: &str) -> bool {
    static PATTERNS: OnceLock<HashMap<&'static str, Regex>> = OnceLock::new();
    let patterns = PATTERNS.get_or_init(|| {
        let raw: &[(&str, &str)] = &[
            ("GB", r"^[A-Z]{1,2}[0-9][0-9A-Z]?\s?[0-9][A-Z]{2}$"),
            ("US", r"^\d{5}(-\d{4})?$"),
            ("CA", r"^[A-Z]\d[A-Z]\s?\d[A-Z]\d$"),
            ("AU", r"^\d{4}$"),
            ("DE", r"^\d{5}$"),
            ("FR", r"^\d{5}$"),
            ("IT", r"^\d{5}$"),
            ("ES", r"^\d{5}$"),
            ("NL", r"^\d{4}\s?[A-Z]{2}$"),
            ("BE", r"^\d{4}$"),
            ("CH", r"^\d{4}$"),
            ("AT", r"^\d{4}$"),
            ("SE", r"^\d{3}\s?\d{2}$"),
            ("NO", r"^\d{4}$"),
            ("DK", r"^\d{4}$"),
            ("FI", r"^\d{5}$"),
            ("PL", r"^\d{2}-\d{3}$"),
            ("CZ", r"^\d{3}\s?\d{2}$"),
            ("HU", r"^\d{4}$"),
            ("RO", r"^\d{6}$"),
            ("IN", r"^\d{6}$"),
            ("JP", r"^\d{3}-\d{4}$"),
            ("CN", r"^\d{6}$"),
            ("BR", r"^\d{5}-?\d{3}$"),
            ("MX", r"^\d{5}$"),
            ("ZA", r"^\d{4}$"),
            ("SG", r"^\d{6}$"),
            ("HK", r"^$"),                 // HK has no postal codes
            ("NZ", r"^\d{4}$"),
            ("AR", r"^[A-Z]?\d{4}[A-Z]{3}?$"),
            ("RU", r"^\d{6}$"),
            ("TR", r"^\d{5}$"),
            ("AE", r"^\d{5,6}$"),
            ("SA", r"^\d{5}$"),
        ];
        raw.iter().filter_map(|(cc, pat)| {
            Regex::new(pat).ok().map(|re| (*cc, re))
        }).collect()
    });

    match patterns.get(country) {
        Some(re) => re.is_match(postal),
        // Unknown country — pass (avoid false-positives for unsupported countries)
        None => true,
    }
}

async fn evaluate_rule(
    rule:  &QualityRule,
    attrs: &HashMap<String, Value>,
    db:    &PgPool,
) -> Option<RuleCheckResult> {
    if rule.conditions.is_empty() {
        return None;
    }

    let mut results: Vec<(bool, String, String)> = Vec::with_capacity(rule.conditions.len());

    for c in &rule.conditions {
        let (ok, msg) = if c.operator == "postal_city_match" {
            eval_postal_city_match(c, attrs, db).await
        } else if c.operator == "postal_format_valid" && c.reference_field.is_some() {
            // Country comes from another attribute rather than a literal value
            let country = c.reference_field.as_deref()
                .and_then(|f| get_str(attrs, f))
                .unwrap_or_default()
                .to_uppercase();
            let postal = get_str(attrs, &c.field);
            let ok = postal.as_deref().map(|pc| postal_format_ok(&country, pc)).unwrap_or(false);
            (ok, format!("'{}' is not a valid postal code for country '{}'", c.field, country))
        } else {
            eval_condition(c, attrs)
        };
        results.push((ok, c.field.clone(), msg));
    }

    let all_passed = if rule.logical_op == "OR" {
        results.iter().any(|(ok, _, _)| *ok)
    } else {
        results.iter().all(|(ok, _, _)| *ok)
    };

    if all_passed {
        return None; // no violation
    }

    let violated_fields = results
        .iter()
        .filter(|(ok, _, _)| !ok)
        .map(|(_, field, msg)| ViolatedField {
            field:   field.clone(),
            message: msg.clone(),
        })
        .collect::<Vec<_>>();

    let rule_snapshot = json!({
        "id":          rule.id,
        "name":        rule.name,
        "entity_type": rule.entity_type,
        "dimension":   rule.dimension,
        "action":      rule.action,
        "severity":    rule.severity,
        "conditions":  rule.conditions,
        "logical_op":  rule.logical_op,
    });

    Some(RuleCheckResult {
        rule_id:         rule.id,
        rule_name:       rule.name.clone(),
        action:          rule.action.clone(),
        severity:        rule.severity.clone(),
        violated_fields,
        rule_snapshot,
    })
}

// ── Postal code ↔ city consistency check (DB lookup) ─────────────────────────
// cond.field          = postal_code attribute
// cond.reference_field = city attribute
// cond.value           = country code (literal) OR resolved from a third field
async fn eval_postal_city_match(
    cond:  &QualityCondition,
    attrs: &HashMap<String, Value>,
    db:    &PgPool,
) -> (bool, String) {
    let postal  = match get_str(attrs, &cond.field) {
        Some(p) if !p.trim().is_empty() => p.trim().to_string(),
        _ => return (true, String::new()), // nothing to validate
    };
    let city_field = match &cond.reference_field {
        Some(f) => f.clone(),
        None    => return (true, String::new()),
    };
    let city = match get_str(attrs, &city_field) {
        Some(c) if !c.trim().is_empty() => c.trim().to_lowercase(),
        _ => return (true, String::new()), // no city — skip
    };
    // Country: from literal value or from a second reference encoded as
    // "country_field:<field_name>" in `value`.
    let country: String = if let Some(v) = &cond.value {
        if let Some(field_name) = v.strip_prefix("country_field:") {
            get_str(attrs, field_name).unwrap_or_default().to_uppercase()
        } else {
            v.to_uppercase()
        }
    } else {
        get_str(attrs, "country").unwrap_or_default().to_uppercase()
    };

    if country.is_empty() {
        return (true, String::new()); // can't validate without country
    }

    let found: bool = sqlx::query_scalar::<_, bool>(
        r#"
        SELECT EXISTS (
            SELECT 1 FROM core_mdm.geo_postal_codes
            WHERE  country_code = $1
            AND    postal_code  = $2
            AND    lower(place_name) LIKE '%' || $3 || '%'
        )
        "#,
    )
    .bind(&country)
    .bind(&postal)
    .bind(&city)
    .fetch_one(db)
    .await
    .unwrap_or(true); // fail-open: if DB lookup fails, don't block the entity

    if found {
        (true, String::new())
    } else {
        (false, format!(
            "postal code '{}' does not match city '{}' for country '{}'",
            postal, city, country
        ))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

pub struct DataQualityService {
    db: PgPool,
}

impl DataQualityService {
    pub fn new(db: PgPool) -> Self {
        Self { db }
    }

    // ── Completeness scoring (unchanged) ────────────────────────────────────

    pub async fn compute_and_update(
        &self,
        tenant_id: Uuid,
        entity_id: Uuid,
    ) -> Result<f32, sqlx::Error> {
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

    pub fn compute_and_update_background(&self, tenant_id: Uuid, entity_id: Uuid) {
        let db  = self.db.clone();
        let svc = DataQualityService { db };
        tokio::spawn(async move {
            if let Err(e) = svc.compute_and_update(tenant_id, entity_id).await {
                warn!(error=%e, entity_id=%entity_id, "background quality score failed");
            }
        });
    }

    // ── Rule loading ──────────────────────────────────────────────────────────

    async fn load_active_rules(
        &self,
        tenant_id:   Uuid,
        entity_type: &str,
    ) -> Result<Vec<QualityRule>, sqlx::Error> {
        let rows = sqlx::query(
            r#"
            SELECT id, tenant_id, name, entity_type, dimension,
                   conditions, logical_op, action, severity, priority,
                   is_active, created_by, created_at, updated_at
            FROM core_mdm.quality_rules
            WHERE tenant_id = $1
              AND is_active  = true
              AND (entity_type = 'all' OR LOWER(entity_type) = LOWER($2))
            ORDER BY priority ASC, severity DESC
            "#,
        )
        .bind(tenant_id)
        .bind(entity_type)
        .fetch_all(&self.db)
        .await?;

        Ok(rows
            .iter()
            .filter_map(|r| self.row_to_rule(r).ok())
            .collect())
    }

    fn row_to_rule(&self, r: &sqlx::postgres::PgRow) -> Result<QualityRule, sqlx::Error> {
        let conds_val: Value = r.try_get("conditions").unwrap_or(Value::Array(vec![]));
        let conditions: Vec<QualityCondition> =
            serde_json::from_value(conds_val).unwrap_or_default();

        Ok(QualityRule {
            id:          r.get("id"),
            tenant_id:   r.get("tenant_id"),
            name:        r.get("name"),
            entity_type: r.get("entity_type"),
            dimension:   r.get("dimension"),
            conditions,
            logical_op:  r.get("logical_op"),
            action:      r.get("action"),
            severity:    r.get("severity"),
            priority:    r.get("priority"),
            is_active:   r.get("is_active"),
            created_by:  r.try_get("created_by").unwrap_or(None),
            created_at:  r.get("created_at"),
            updated_at:  r.get("updated_at"),
        })
    }

    // ── Quality check (called on entity create/update) ────────────────────────

    /// Evaluate all active rules for `entity_type` against the supplied
    /// attribute map. Returns a `CheckOutcome` that the caller uses to decide
    /// whether to block or allow the entity write.
    pub async fn check_entity(
        &self,
        tenant_id:   Uuid,
        entity_type: &str,
        attrs:       &HashMap<String, Value>,
    ) -> CheckOutcome {
        let rules = match self.load_active_rules(tenant_id, entity_type).await {
            Ok(r)  => r,
            Err(e) => {
                warn!(error=%e, "quality rule load failed — skipping checks");
                return CheckOutcome { blocking: false, violations: vec![] };
            }
        };

        let mut violations = Vec::new();
        let mut blocking   = false;

        for rule in &rules {
            if let Some(result) = evaluate_rule(rule, attrs, &self.db).await {
                if matches!(result.action.as_str(), "reject" | "quarantine") {
                    blocking = true;
                }
                violations.push(result);
            }
        }

        CheckOutcome { blocking, violations }
    }

    /// Persist violations generated by `check_entity`. Runs in a background
    /// task so it never blocks the entity write path.
    pub fn save_violations_background(
        &self,
        tenant_id:   Uuid,
        entity_id:   Uuid,
        entity_type: String,
        violations:  Vec<RuleCheckResult>,
    ) {
        let db = self.db.clone();
        tokio::spawn(async move {
            for v in violations {
                let fields_json =
                    serde_json::to_value(&v.violated_fields).unwrap_or(Value::Array(vec![]));
                if let Err(e) = sqlx::query(
                    r#"
                    INSERT INTO core_mdm.quality_violations
                        (tenant_id, rule_id, rule_snapshot, entity_id, entity_type,
                         violated_fields, action_taken, severity)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
                    "#,
                )
                .bind(tenant_id)
                .bind(v.rule_id)
                .bind(&v.rule_snapshot)
                .bind(entity_id)
                .bind(&entity_type)
                .bind(&fields_json)
                .bind(&v.action)
                .bind(&v.severity)
                .execute(&db)
                .await
                {
                    warn!(error=%e, entity_id=%entity_id, rule_id=%v.rule_id,
                          "quality violation save failed");
                }
            }
        });
    }

    // ── Rule CRUD ─────────────────────────────────────────────────────────────

    pub async fn list_rules(
        &self,
        tenant_id: Uuid,
    ) -> Result<Vec<QualityRule>, sqlx::Error> {
        let rows = sqlx::query(
            r#"
            SELECT id, tenant_id, name, entity_type, dimension,
                   conditions, logical_op, action, severity, priority,
                   is_active, created_by, created_at, updated_at
            FROM core_mdm.quality_rules
            WHERE tenant_id = $1
            ORDER BY priority ASC, created_at DESC
            "#,
        )
        .bind(tenant_id)
        .fetch_all(&self.db)
        .await?;

        Ok(rows
            .iter()
            .filter_map(|r| self.row_to_rule(r).ok())
            .collect())
    }

    pub async fn create_rule(
        &self,
        tenant_id:   Uuid,
        name:        String,
        entity_type: String,
        dimension:   String,
        conditions:  Value,
        logical_op:  String,
        action:      String,
        severity:    String,
        priority:    i32,
        created_by:  Option<Uuid>,
    ) -> Result<QualityRule, sqlx::Error> {
        let id = Uuid::new_v4();
        sqlx::query(
            r#"
            INSERT INTO core_mdm.quality_rules
                (id, tenant_id, name, entity_type, dimension, conditions,
                 logical_op, action, severity, priority, created_by)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
            "#,
        )
        .bind(id)
        .bind(tenant_id)
        .bind(&name)
        .bind(&entity_type)
        .bind(&dimension)
        .bind(&conditions)
        .bind(&logical_op)
        .bind(&action)
        .bind(&severity)
        .bind(priority)
        .bind(created_by)
        .execute(&self.db)
        .await?;

        let row = sqlx::query(
            r#"SELECT id, tenant_id, name, entity_type, dimension, conditions,
                      logical_op, action, severity, priority, is_active,
                      created_by, created_at, updated_at
               FROM core_mdm.quality_rules WHERE id = $1"#,
        )
        .bind(id)
        .fetch_one(&self.db)
        .await?;

        self.row_to_rule(&row)
    }

    pub async fn update_rule(
        &self,
        tenant_id:   Uuid,
        rule_id:     Uuid,
        name:        Option<String>,
        entity_type: Option<String>,
        dimension:   Option<String>,
        conditions:  Option<Value>,
        logical_op:  Option<String>,
        action:      Option<String>,
        severity:    Option<String>,
        priority:    Option<i32>,
        is_active:   Option<bool>,
    ) -> Result<Option<QualityRule>, sqlx::Error> {
        let updated = sqlx::query_scalar::<_, i64>(
            r#"
            UPDATE core_mdm.quality_rules SET
                name        = COALESCE($3,  name),
                entity_type = COALESCE($4,  entity_type),
                dimension   = COALESCE($5,  dimension),
                conditions  = COALESCE($6,  conditions),
                logical_op  = COALESCE($7,  logical_op),
                action      = COALESCE($8,  action),
                severity    = COALESCE($9,  severity),
                priority    = COALESCE($10, priority),
                is_active   = COALESCE($11, is_active),
                updated_at  = NOW()
            WHERE id = $1 AND tenant_id = $2
            RETURNING 1
            "#,
        )
        .bind(rule_id)
        .bind(tenant_id)
        .bind(name)
        .bind(entity_type)
        .bind(dimension)
        .bind(conditions)
        .bind(logical_op)
        .bind(action)
        .bind(severity)
        .bind(priority)
        .bind(is_active)
        .fetch_optional(&self.db)
        .await?;

        if updated.is_none() {
            return Ok(None);
        }

        let row = sqlx::query(
            r#"SELECT id, tenant_id, name, entity_type, dimension, conditions,
                      logical_op, action, severity, priority, is_active,
                      created_by, created_at, updated_at
               FROM core_mdm.quality_rules WHERE id = $1"#,
        )
        .bind(rule_id)
        .fetch_one(&self.db)
        .await?;

        Ok(Some(self.row_to_rule(&row)?))
    }

    pub async fn delete_rule(
        &self,
        tenant_id: Uuid,
        rule_id:   Uuid,
    ) -> Result<bool, sqlx::Error> {
        let n = sqlx::query_scalar::<_, i64>(
            "DELETE FROM core_mdm.quality_rules WHERE id=$1 AND tenant_id=$2 RETURNING 1",
        )
        .bind(rule_id)
        .bind(tenant_id)
        .fetch_optional(&self.db)
        .await?;
        Ok(n.is_some())
    }

    pub async fn reorder_rules(
        &self,
        tenant_id: Uuid,
        order:     Vec<(Uuid, i32)>,
    ) -> Result<(), sqlx::Error> {
        for (id, priority) in order {
            sqlx::query(
                "UPDATE core_mdm.quality_rules SET priority=$1, updated_at=NOW() \
                 WHERE id=$2 AND tenant_id=$3",
            )
            .bind(priority)
            .bind(id)
            .bind(tenant_id)
            .execute(&self.db)
            .await?;
        }
        Ok(())
    }

    // ── Violations CRUD ───────────────────────────────────────────────────────

    pub async fn list_violations(
        &self,
        tenant_id:   Uuid,
        entity_type: Option<&str>,
        severity:    Option<&str>,
        resolved:    Option<bool>,
        limit:       i64,
        offset:      i64,
    ) -> Result<Vec<Value>, sqlx::Error> {
        let rows = sqlx::query(
            r#"
            SELECT v.id, v.tenant_id, v.rule_id, v.rule_snapshot,
                   v.entity_id, v.entity_type, v.violated_fields,
                   v.action_taken, v.severity, v.is_resolved,
                   v.resolved_by, v.resolved_at, v.detected_at
            FROM core_mdm.quality_violations v
            WHERE v.tenant_id = $1
              AND ($2::text  IS NULL OR LOWER(v.entity_type) = LOWER($2))
              AND ($3::text  IS NULL OR v.severity = $3)
              AND ($4::bool  IS NULL OR v.is_resolved = $4)
            ORDER BY v.detected_at DESC
            LIMIT $5 OFFSET $6
            "#,
        )
        .bind(tenant_id)
        .bind(entity_type)
        .bind(severity)
        .bind(resolved)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.db)
        .await?;

        Ok(rows
            .iter()
            .map(|r| {
                json!({
                    "id":              r.get::<Uuid, _>("id").to_string(),
                    "rule_id":         r.get::<Option<Uuid>, _>("rule_id").map(|u| u.to_string()),
                    "rule_snapshot":   r.get::<Value, _>("rule_snapshot"),
                    "entity_id":       r.get::<Option<Uuid>, _>("entity_id").map(|u| u.to_string()),
                    "entity_type":     r.get::<String, _>("entity_type"),
                    "violated_fields": r.get::<Value, _>("violated_fields"),
                    "action_taken":    r.get::<String, _>("action_taken"),
                    "severity":        r.get::<String, _>("severity"),
                    "is_resolved":     r.get::<bool, _>("is_resolved"),
                    "resolved_by":     r.get::<Option<Uuid>, _>("resolved_by").map(|u| u.to_string()),
                    "resolved_at":     r.get::<Option<chrono::DateTime<chrono::Utc>>, _>("resolved_at")
                                        .map(|t| t.to_rfc3339()),
                    "detected_at":     r.get::<chrono::DateTime<chrono::Utc>, _>("detected_at").to_rfc3339(),
                })
            })
            .collect())
    }

    pub async fn resolve_violation(
        &self,
        tenant_id:    Uuid,
        violation_id: Uuid,
        resolved_by:  Option<Uuid>,
    ) -> Result<bool, sqlx::Error> {
        let n = sqlx::query_scalar::<_, i64>(
            r#"
            UPDATE core_mdm.quality_violations
            SET is_resolved=true, resolved_by=$3, resolved_at=NOW()
            WHERE id=$1 AND tenant_id=$2 AND is_resolved=false
            RETURNING 1
            "#,
        )
        .bind(violation_id)
        .bind(tenant_id)
        .bind(resolved_by)
        .fetch_optional(&self.db)
        .await?;
        Ok(n.is_some())
    }

    pub async fn bulk_resolve(
        &self,
        tenant_id:     Uuid,
        violation_ids: &[Uuid],
        resolved_by:   Option<Uuid>,
    ) -> Result<i64, sqlx::Error> {
        let n = sqlx::query_scalar::<_, i64>(
            r#"
            UPDATE core_mdm.quality_violations
            SET is_resolved=true, resolved_by=$3, resolved_at=NOW()
            WHERE tenant_id=$1 AND id=ANY($2) AND is_resolved=false
            RETURNING 1
            "#,
        )
        .bind(tenant_id)
        .bind(violation_ids)
        .bind(resolved_by)
        .fetch_optional(&self.db)
        .await?
        .unwrap_or(0);
        Ok(n)
    }

    // ── Batch run ─────────────────────────────────────────────────────────────

    /// Run all active rules against all non-deleted entities for the tenant.
    /// Runs in a background Tokio task — returns immediately.
    pub fn run_all_rules_background(&self, tenant_id: Uuid) {
        let db = self.db.clone();
        tokio::spawn(async move {
            if let Err(e) = run_batch(&db, tenant_id).await {
                warn!(error=%e, tenant_id=%tenant_id, "batch quality run failed");
            }
        });
    }
}

// ── Batch execution (standalone async fn, keeps the struct impl clean) ────────

async fn run_batch(db: &PgPool, tenant_id: Uuid) -> Result<(), sqlx::Error> {
    let svc = DataQualityService { db: db.clone() };

    // Load all active rules once
    let all_rules = sqlx::query(
        r#"SELECT id, tenant_id, name, entity_type, dimension, conditions,
                  logical_op, action, severity, priority, is_active,
                  created_by, created_at, updated_at
           FROM core_mdm.quality_rules
           WHERE tenant_id=$1 AND is_active=true
           ORDER BY priority ASC"#,
    )
    .bind(tenant_id)
    .fetch_all(db)
    .await?;

    let rules: Vec<QualityRule> = all_rules
        .iter()
        .filter_map(|r| svc.row_to_rule(r).ok())
        .collect();

    if rules.is_empty() {
        return Ok(());
    }

    // Stream entities in pages of 200 to avoid memory pressure
    let mut offset: i64 = 0;
    loop {
        let entities = sqlx::query(
            r#"
            SELECT e.id, e.entity_type::TEXT AS entity_type,
                   COALESCE(
                       jsonb_object_agg(ea.attribute_key, ea.value)
                       FILTER (WHERE ea.attribute_key IS NOT NULL AND ea.encrypted IS NOT TRUE),
                       '{}'::jsonb
                   ) AS attrs
            FROM core_mdm.entities e
            LEFT JOIN core_mdm.entity_attributes ea
                   ON ea.entity_id = e.entity_id AND ea.tenant_id = e.tenant_id
            WHERE e.tenant_id   = $1
              AND e.is_deleted IS NOT TRUE
            GROUP BY e.id, e.entity_type
            ORDER BY e.created_at DESC
            LIMIT 200 OFFSET $2
            "#,
        )
        .bind(tenant_id)
        .bind(offset)
        .fetch_all(db)
        .await?;

        if entities.is_empty() {
            break;
        }

        for row in &entities {
            let entity_id:   Uuid   = row.get("id");
            let entity_type: String = row.get("entity_type");
            let attrs_val:   Value  = row.try_get("attrs").unwrap_or(Value::Object(Default::default()));

            let attrs: HashMap<String, Value> = match attrs_val.as_object() {
                Some(m) => m.iter().map(|(k, v)| (k.clone(), v.clone())).collect(),
                None    => HashMap::new(),
            };

            let applicable: Vec<&QualityRule> = rules
                .iter()
                .filter(|r| {
                    r.entity_type == "all"
                        || r.entity_type.to_lowercase() == entity_type.to_lowercase()
                })
                .collect();

            for rule in applicable {
                if let Some(result) = evaluate_rule(rule, &attrs, db).await {
                    let fields_json = serde_json::to_value(&result.violated_fields)
                        .unwrap_or(Value::Array(vec![]));
                    let _ = sqlx::query(
                        r#"
                        INSERT INTO core_mdm.quality_violations
                            (tenant_id, rule_id, rule_snapshot, entity_id, entity_type,
                             violated_fields, action_taken, severity)
                        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
                        "#,
                    )
                    .bind(tenant_id)
                    .bind(result.rule_id)
                    .bind(&result.rule_snapshot)
                    .bind(entity_id)
                    .bind(&entity_type)
                    .bind(&fields_json)
                    .bind(&result.action)
                    .bind(&result.severity)
                    .execute(db)
                    .await;
                }
            }
        }

        offset += 200;
    }

    Ok(())
}
