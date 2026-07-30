use std::sync::Arc;
use axum::{extract::{Path, State}, response::IntoResponse, Extension, Json, http::StatusCode};
use serde_json::json;
use sqlx::Row;
use tracing::error;
use uuid::Uuid;
use crate::middleware::tenant::TenantContext;
use crate::AppState;

// ── Helpers ───────────────────────────────────────────────────────────────────

fn default_rules_for(code: &str) -> Vec<&'static str> {
    match code {
        "customer" | "person" | "individual" | "contact" => vec![
            "exact:email",
            "exact:phone",
            "phonetic:legal_name",
            "phonetic:full_name",
            "canopy:legal_name",
            "canopy:full_name",
            "canopy:first_name",
            "canopy:last_name",
            "vector",
        ],
        "vendor" | "supplier" | "partner" => vec![
            "exact:tax_id",
            "exact:email",
            "exact:vendor_id",
            "phonetic:legal_name",
            "phonetic:company_name",
            "canopy:legal_name",
            "canopy:company_name",
            "vector",
        ],
        "employee" | "staff" => vec![
            "exact:email",
            "phonetic:full_name",
            "canopy:first_name",
            "canopy:last_name",
            "vector",
        ],
        "company" | "organization" | "account" => vec![
            "exact:tax_id",
            "exact:customer_id",
            "phonetic:legal_name",
            "phonetic:company_name",
            "canopy:legal_name",
            "canopy:company_name",
            "vector",
        ],
        _ => vec![],
    }
}

/// Validate a single blocking-rule token against
/// `^(exact|phonetic|canopy|vector)(:[a-z_]+)?$`
fn is_valid_rule(s: &str) -> bool {
    let (prefix, suffix) = match s.find(':') {
        Some(pos) => (&s[..pos], Some(&s[pos + 1..])),
        None      => (s, None),
    };
    let valid_prefix = matches!(prefix, "exact" | "phonetic" | "canopy" | "vector");
    let valid_suffix = suffix.map_or(true, |sfx| {
        !sfx.is_empty() && sfx.chars().all(|c| c.is_ascii_lowercase() || c == '_')
    });
    valid_prefix && valid_suffix
}

// ── GET /entity-types/:code/blocking-rules ────────────────────────────────────

pub async fn get_blocking_rules(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(code):            Path<String>,
) -> impl IntoResponse {
    let tenant_id = tenant_ctx.tenant_id;

    let row = sqlx::query(
        r#"
        SELECT rules
        FROM core_mdm.entity_type_blocking_rules
        WHERE tenant_id = $1 AND entity_type_code = $2
        "#,
    )
    .bind(tenant_id)
    .bind(&code)
    .fetch_optional(&state.db)
    .await;

    match row {
        Ok(Some(r)) => {
            let rules: serde_json::Value = r
                .try_get::<sqlx::types::Json<serde_json::Value>, _>("rules")
                .ok()
                .map(|j| j.0)
                .unwrap_or_else(|| serde_json::Value::Array(vec![]));

            (
                StatusCode::OK,
                Json(json!({
                    "success": true,
                    "data": {
                        "entity_type_code": code,
                        "rules":            rules,
                        "is_default":       false,
                    }
                })),
            )
                .into_response()
        }
        Ok(None) => {
            let defaults = default_rules_for(&code);
            (
                StatusCode::OK,
                Json(json!({
                    "success": true,
                    "data": {
                        "entity_type_code": code,
                        "rules":            defaults,
                        "is_default":       true,
                    }
                })),
            )
                .into_response()
        }
        Err(err) => {
            error!(error=?err, "get_blocking_rules failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": "failed to fetch blocking rules" })),
            )
                .into_response()
        }
    }
}

// ── PUT /entity-types/:code/blocking-rules ────────────────────────────────────

pub async fn put_blocking_rules(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(code):            Path<String>,
    Json(body):            Json<serde_json::Value>,
) -> impl IntoResponse {
    let tenant_id = tenant_ctx.tenant_id;

    let rules_arr = match body.get("rules").and_then(|v| v.as_array()) {
        Some(arr) => arr,
        None => {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({ "success": false, "error": "rules must be a JSON array of strings" })),
            )
                .into_response();
        }
    };

    let mut rules: Vec<String> = Vec::with_capacity(rules_arr.len());
    for item in rules_arr {
        match item.as_str() {
            Some(s) => {
                if !is_valid_rule(s) {
                    return (
                        StatusCode::BAD_REQUEST,
                        Json(json!({
                            "success": false,
                            "error": format!(
                                "invalid rule {:?}: must match ^(exact|phonetic|canopy|vector)(:[a-z_]+)?$",
                                s
                            )
                        })),
                    )
                        .into_response();
                }
                rules.push(s.to_owned());
            }
            None => {
                return (
                    StatusCode::BAD_REQUEST,
                    Json(json!({ "success": false, "error": "each rule must be a string" })),
                )
                    .into_response();
            }
        }
    }

    let rules_json = serde_json::Value::Array(
        rules.iter().map(|s| serde_json::Value::String(s.clone())).collect(),
    );

    let row = sqlx::query(
        r#"
        INSERT INTO core_mdm.entity_type_blocking_rules
            (id, tenant_id, entity_type_code, rules)
        VALUES (gen_random_uuid(), $1, $2, $3)
        ON CONFLICT (tenant_id, entity_type_code)
        DO UPDATE SET rules = EXCLUDED.rules, updated_at = now()
        RETURNING rules
        "#,
    )
    .bind(tenant_id)
    .bind(&code)
    .bind(sqlx::types::Json(&rules_json))
    .fetch_one(&state.db)
    .await;

    match row {
        Ok(r) => {
            let saved_rules: serde_json::Value = r
                .try_get::<sqlx::types::Json<serde_json::Value>, _>("rules")
                .ok()
                .map(|j| j.0)
                .unwrap_or(rules_json);

            (
                StatusCode::OK,
                Json(json!({
                    "success": true,
                    "data": {
                        "entity_type_code": code,
                        "rules":            saved_rules,
                    }
                })),
            )
                .into_response()
        }
        Err(err) => {
            error!(error=?err, "put_blocking_rules failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": "failed to save blocking rules" })),
            )
                .into_response()
        }
    }
}
