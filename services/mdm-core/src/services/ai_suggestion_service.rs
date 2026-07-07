// services/mdm-core/src/services/ai_suggestion_service.rs
//
// Orchestrates LLM-powered suggestions with a strict approval gate.
//
// Flow:
//   1. trigger_*()  — strips PII, calls ai-service /internal/suggest,
//                     stores result as status='pending' in ai_suggestions
//   2. list_*()     — returns pending suggestions for user review
//   3. approve()    — marks approved + applies field changes via entity_service
//   4. reject()     — marks rejected, no entity change

use serde_json::{json, Value};
use sqlx::{PgPool, Row};
use uuid::Uuid;

// ── PII field names that must never be sent to the LLM ───────────────────────

static PII_FIELDS: &[&str] = &[
    "name", "first_name", "last_name", "full_name", "display_name",
    "email", "email_address",
    "phone", "mobile", "fax", "telephone",
    "tax_id", "ssn", "national_id", "passport", "passport_number",
    "bank_account", "iban", "account_number", "routing_number", "sort_code",
    "credit_card", "card_number", "cvv",
    "date_of_birth", "birth_date", "dob",
    "salary", "income", "wage",
    "password", "pin", "secret",
    "ip_address", "mac_address",
];

fn is_pii(field: &str) -> bool {
    let lower = field.to_lowercase();
    PII_FIELDS.iter().any(|p| lower.contains(p))
}

/// Strip PII from a JSONB attributes map before sending to the LLM.
/// Returns only fields whose names are safe.
fn strip_pii(attrs: &Value) -> serde_json::Map<String, Value> {
    match attrs.as_object() {
        Some(m) => m.iter()
            .filter(|(k, _)| !is_pii(k))
            .map(|(k, v)| (k.clone(), v.clone()))
            .collect(),
        None => serde_json::Map::new(),
    }
}

// ── Service ───────────────────────────────────────────────────────────────────

#[derive(Clone)]
pub struct AiSuggestionService {
    db:          PgPool,
    http:        reqwest::Client,
    ai_base_url: String,
}

impl AiSuggestionService {
    pub fn new(db: PgPool, ai_base_url: String) -> Self {
        Self {
            db,
            http: reqwest::Client::new(),
            ai_base_url,
        }
    }

    // ── Trigger helpers ───────────────────────────────────────────────────────

    /// Trigger an address-parse suggestion for an entity.
    /// `raw_address_field` is the attribute key containing the free-form string.
    pub async fn trigger_address_parse(
        &self,
        tenant_id:         Uuid,
        entity_id:         Uuid,
        entity_type:       &str,
        attrs:             &Value,
        raw_address_field: &str,
    ) -> Result<Uuid, String> {
        let raw_addr = attrs
            .get(raw_address_field)
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();

        if raw_addr.trim().is_empty() {
            return Err("raw address field is empty".to_string());
        }

        // Only send the address string — no other fields
        let mut safe = serde_json::Map::new();
        safe.insert(raw_address_field.to_string(), json!(raw_addr));

        self.call_and_store(
            tenant_id,
            entity_id,
            entity_type,
            "address_parse",
            safe,
            vec![],
        )
        .await
    }

    /// Trigger an anomaly-detection suggestion.
    /// Sends non-PII fields only.
    pub async fn trigger_anomaly(
        &self,
        tenant_id:   Uuid,
        entity_id:   Uuid,
        entity_type: &str,
        attrs:       &Value,
    ) -> Result<Uuid, String> {
        let safe = strip_pii(attrs);
        if safe.is_empty() {
            return Err("no safe fields available after PII stripping".to_string());
        }
        self.call_and_store(tenant_id, entity_id, entity_type, "anomaly", safe, vec![])
            .await
    }

    /// Trigger an enrichment suggestion for specific missing fields.
    pub async fn trigger_enrichment(
        &self,
        tenant_id:      Uuid,
        entity_id:      Uuid,
        entity_type:    &str,
        attrs:          &Value,
        missing_fields: Vec<String>,
    ) -> Result<Uuid, String> {
        // Strip PII from known fields (context), exclude PII from missing list too
        let safe: serde_json::Map<String, Value> = strip_pii(attrs)
            .into_iter()
            .filter(|(k, _)| {
                // Only send non-empty fields as context
                attrs.get(k).map(|v| !v.is_null()).unwrap_or(false)
            })
            .collect();

        let safe_targets: Vec<String> = missing_fields
            .into_iter()
            .filter(|f| !is_pii(f))
            .collect();

        if safe_targets.is_empty() {
            return Err("all target fields are PII — cannot request enrichment via LLM".to_string());
        }

        self.call_and_store(
            tenant_id,
            entity_id,
            entity_type,
            "enrichment",
            safe,
            safe_targets,
        )
        .await
    }

    // ── Core LLM call + storage ───────────────────────────────────────────────

    async fn call_and_store(
        &self,
        tenant_id:       Uuid,
        entity_id:       Uuid,
        entity_type:     &str,
        suggestion_type: &str,
        safe_fields:     serde_json::Map<String, Value>,
        target_fields:   Vec<String>,
    ) -> Result<Uuid, String> {
        let url = format!("{}/internal/suggest", self.ai_base_url.trim_end_matches('/'));

        let body = json!({
            "suggestion_type": suggestion_type,
            "entity_type":     entity_type,
            "safe_fields":     safe_fields,
            "target_fields":   target_fields,
        });

        let resp = self.http
            .post(&url)
            .json(&body)
            .send()
            .await
            .map_err(|e| format!("ai-service unreachable: {e}"))?;

        let status = resp.status();
        let json: Value = resp.json().await.map_err(|e| format!("bad JSON: {e}"))?;

        if !status.is_success() {
            return Err(json["error"].as_str().unwrap_or("ai-service error").to_string());
        }

        let suggestions = json["suggestions"].clone();
        let rationale   = json["rationale"].as_str().unwrap_or("").to_string();
        let confidence  = suggestions
            .as_array()
            .and_then(|arr| {
                if arr.is_empty() { return None; }
                let avg = arr.iter()
                    .filter_map(|s| s["confidence"].as_f64())
                    .sum::<f64>() / arr.len() as f64;
                Some(avg)
            })
            .unwrap_or(0.5);

        let suggestion_id: Uuid = sqlx::query_scalar(
            r#"
            INSERT INTO core_mdm.ai_suggestions
                (tenant_id, entity_id, entity_type, suggestion_type,
                 safe_input, suggestion, rationale, confidence)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            RETURNING id
            "#,
        )
        .bind(tenant_id)
        .bind(entity_id)
        .bind(entity_type)
        .bind(suggestion_type)
        .bind(json!({ "fields": body["safe_fields"] }))
        .bind(&suggestions)
        .bind(&rationale)
        .bind(confidence)
        .fetch_one(&self.db)
        .await
        .map_err(|e| format!("db insert failed: {e}"))?;

        Ok(suggestion_id)
    }

    // ── List ──────────────────────────────────────────────────────────────────

    pub async fn list_suggestions(
        &self,
        tenant_id:       Uuid,
        entity_id:       Option<Uuid>,
        suggestion_type: Option<&str>,
        status:          Option<&str>,
        limit:           i64,
        offset:          i64,
    ) -> Result<Vec<Value>, sqlx::Error> {
        let rows = sqlx::query(
            r#"
            SELECT id, entity_id, entity_type, suggestion_type,
                   status, suggestion, rationale, confidence,
                   reviewed_by, reviewed_at, applied_at, created_at
            FROM core_mdm.ai_suggestions
            WHERE tenant_id = $1
              AND ($2::uuid   IS NULL OR entity_id        = $2)
              AND ($3::text   IS NULL OR suggestion_type  = $3)
              AND ($4::text   IS NULL OR status           = $4)
            ORDER BY created_at DESC
            LIMIT $5 OFFSET $6
            "#,
        )
        .bind(tenant_id)
        .bind(entity_id)
        .bind(suggestion_type)
        .bind(status)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.db)
        .await?;

        Ok(rows.iter().map(|r| json!({
            "id":              r.get::<Uuid, _>("id"),
            "entity_id":       r.get::<Option<Uuid>, _>("entity_id"),
            "entity_type":     r.get::<String, _>("entity_type"),
            "suggestion_type": r.get::<String, _>("suggestion_type"),
            "status":          r.get::<String, _>("status"),
            "suggestion":      r.get::<Value, _>("suggestion"),
            "rationale":       r.get::<String, _>("rationale"),
            "confidence":      r.get::<Option<f64>, _>("confidence"),
            "reviewed_by":     r.get::<Option<Uuid>, _>("reviewed_by"),
            "reviewed_at":     r.get::<Option<chrono::DateTime<chrono::Utc>>, _>("reviewed_at")
                                .map(|t| t.to_rfc3339()),
            "applied_at":      r.get::<Option<chrono::DateTime<chrono::Utc>>, _>("applied_at")
                                .map(|t| t.to_rfc3339()),
            "created_at":      r.get::<chrono::DateTime<chrono::Utc>, _>("created_at").to_rfc3339(),
        })).collect())
    }

    // ── Approve ───────────────────────────────────────────────────────────────
    // Returns the field changes to apply so the caller (handler) can patch the entity.

    pub async fn approve(
        &self,
        tenant_id:     Uuid,
        suggestion_id: Uuid,
        reviewer_id:   Option<Uuid>,
    ) -> Result<Option<(Uuid, Value)>, sqlx::Error> {
        let row = sqlx::query(
            r#"
            UPDATE core_mdm.ai_suggestions
            SET status      = 'approved',
                reviewed_by = $3,
                reviewed_at = NOW()
            WHERE id = $1 AND tenant_id = $2 AND status = 'pending'
            RETURNING entity_id, suggestion
            "#,
        )
        .bind(suggestion_id)
        .bind(tenant_id)
        .bind(reviewer_id)
        .fetch_optional(&self.db)
        .await?;

        Ok(row.map(|r| {
            let entity_id:  Uuid  = r.get("entity_id");
            let suggestion: Value = r.get("suggestion");
            (entity_id, suggestion)
        }))
    }

    /// Mark the suggestion as applied after the caller successfully patched the entity.
    pub async fn mark_applied(
        &self,
        tenant_id:     Uuid,
        suggestion_id: Uuid,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            "UPDATE core_mdm.ai_suggestions \
             SET status='applied', applied_at=NOW() \
             WHERE id=$1 AND tenant_id=$2",
        )
        .bind(suggestion_id)
        .bind(tenant_id)
        .execute(&self.db)
        .await?;
        Ok(())
    }

    // ── Reject ────────────────────────────────────────────────────────────────

    pub async fn reject(
        &self,
        tenant_id:     Uuid,
        suggestion_id: Uuid,
        reviewer_id:   Option<Uuid>,
    ) -> Result<bool, sqlx::Error> {
        let n = sqlx::query_scalar::<_, i64>(
            r#"
            UPDATE core_mdm.ai_suggestions
            SET status      = 'rejected',
                reviewed_by = $3,
                reviewed_at = NOW()
            WHERE id = $1 AND tenant_id = $2 AND status = 'pending'
            RETURNING 1
            "#,
        )
        .bind(suggestion_id)
        .bind(tenant_id)
        .bind(reviewer_id)
        .fetch_optional(&self.db)
        .await?;
        Ok(n.is_some())
    }
}
