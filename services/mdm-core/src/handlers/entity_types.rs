use std::{collections::HashMap, sync::Arc};

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::IntoResponse,
    Json,
};
use chrono::Datelike;
use serde_json::json;
use sqlx::Row;
use tracing::error;
use uuid::Uuid;

use crate::AppState;

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Replace format tokens in a sequence format string.
///
/// Recognised tokens:
/// - `{PREFIX}`  → seq_prefix
/// - `{YYYY}`    → current UTC year (4 digits)
/// - `{YY}`      → current UTC year (2 digits)
/// - `{MM}`      → current UTC month (zero-padded)
/// - `{SEQ3}`    → seq_value zero-padded to 3 digits
/// - `{SEQ4}`    → seq_value zero-padded to 4 digits
/// - `{SEQ5}`    → seq_value zero-padded to 5 digits
/// - `{SEQ6}`    → seq_value zero-padded to 6 digits
/// - `{SEQ}`     → seq_value with no padding (fallback)
fn format_sequence_id(
    seq_format: &str,
    seq_prefix: &str,
    seq_value:  i64,
) -> String {
    let now    = chrono::Utc::now();
    let year   = now.year();
    let month  = now.month();

    seq_format
        .replace("{PREFIX}", seq_prefix)
        .replace("{YYYY}",   &format!("{:04}", year))
        .replace("{YY}",     &format!("{:02}", year % 100))
        .replace("{MM}",     &format!("{:02}", month))
        .replace("{SEQ6}",   &format!("{:06}", seq_value))
        .replace("{SEQ5}",   &format!("{:05}", seq_value))
        .replace("{SEQ4}",   &format!("{:04}", seq_value))
        .replace("{SEQ3}",   &format!("{:03}", seq_value))
        .replace("{SEQ}",    &seq_value.to_string())
}

// ── GET /entity-types?tenant_id=... ──────────────────────────────────────────

pub async fn list_entity_types(
    State(state):   State<Arc<AppState>>,
    Query(params):  Query<HashMap<String, String>>,
) -> impl IntoResponse {
    let tenant_id = match params
        .get("tenant_id")
        .and_then(|s| Uuid::parse_str(s).ok())
    {
        Some(id) => id,
        None => {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({ "success": false, "error": "tenant_id query param is required" })),
            )
                .into_response();
        }
    };

    let rows = sqlx::query(
        r#"
        SELECT
            id, tenant_id, name, code, description, icon, color,
            seq_prefix, seq_format, default_match_threshold,
            is_system, is_active,
            created_at, updated_at
        FROM core_mdm.entity_type_configs
        WHERE tenant_id = $1
        ORDER BY name
        "#,
    )
    .bind(tenant_id)
    .fetch_all(&state.db)
    .await;

    match rows {
        Ok(rows) => {
            let items: Vec<serde_json::Value> = rows
                .iter()
                .map(|r| {
                    json!({
                        "id":                      r.get::<Uuid, _>("id").to_string(),
                        "tenant_id":               r.get::<Uuid, _>("tenant_id").to_string(),
                        "name":                    r.get::<String, _>("name"),
                        "code":                    r.get::<String, _>("code"),
                        "description":             r.get::<Option<String>, _>("description"),
                        "icon":                    r.get::<Option<String>, _>("icon"),
                        "color":                   r.get::<Option<String>, _>("color"),
                        "seq_prefix":              r.get::<Option<String>, _>("seq_prefix"),
                        "seq_format":              r.get::<Option<String>, _>("seq_format"),
                        "default_match_threshold": r.get::<Option<f64>, _>("default_match_threshold"),
                        "is_system":               r.get::<bool, _>("is_system"),
                        "is_active":               r.get::<bool, _>("is_active"),
                        "created_at":              r.get::<chrono::DateTime<chrono::Utc>, _>("created_at").to_rfc3339(),
                        "updated_at":              r.get::<chrono::DateTime<chrono::Utc>, _>("updated_at").to_rfc3339(),
                    })
                })
                .collect();

            (
                StatusCode::OK,
                Json(json!({ "success": true, "data": items })),
            )
                .into_response()
        }
        Err(err) => {
            error!(error=?err, "list_entity_types failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": "failed to list entity types" })),
            )
                .into_response()
        }
    }
}

// ── POST /entity-types ────────────────────────────────────────────────────────

pub async fn create_entity_type(
    State(state): State<Arc<AppState>>,
    Json(body):   Json<serde_json::Value>,
) -> impl IntoResponse {
    let tenant_id = match body
        .get("tenant_id")
        .and_then(|v| v.as_str())
        .and_then(|s| Uuid::parse_str(s).ok())
    {
        Some(id) => id,
        None => {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({ "success": false, "error": "tenant_id is required" })),
            )
                .into_response();
        }
    };

    let name = match body.get("name").and_then(|v| v.as_str()) {
        Some(s) => s.to_owned(),
        None => {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({ "success": false, "error": "name is required" })),
            )
                .into_response();
        }
    };

    let code = match body.get("code").and_then(|v| v.as_str()) {
        Some(s) => s.to_owned(),
        None => {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({ "success": false, "error": "code is required" })),
            )
                .into_response();
        }
    };

    let description             = body.get("description").and_then(|v| v.as_str()).map(str::to_owned);
    let icon                    = body.get("icon").and_then(|v| v.as_str()).map(str::to_owned);
    let color                   = body.get("color").and_then(|v| v.as_str()).map(str::to_owned);
    let seq_prefix              = body.get("seq_prefix").and_then(|v| v.as_str()).map(str::to_owned);
    let seq_format              = body.get("seq_format").and_then(|v| v.as_str()).map(str::to_owned);
    let default_match_threshold = body.get("default_match_threshold").and_then(|v| v.as_f64());

    let row = sqlx::query(
        r#"
        INSERT INTO core_mdm.entity_type_configs
            (tenant_id, name, code, description, icon, color,
             seq_prefix, seq_format, default_match_threshold)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        RETURNING
            id, tenant_id, name, code, description, icon, color,
            seq_prefix, seq_format, default_match_threshold,
            is_system, is_active, created_at, updated_at
        "#,
    )
    .bind(tenant_id)
    .bind(&name)
    .bind(&code)
    .bind(&description)
    .bind(&icon)
    .bind(&color)
    .bind(&seq_prefix)
    .bind(&seq_format)
    .bind(default_match_threshold)
    .fetch_one(&state.db)
    .await;

    match row {
        Ok(r) => {
            let data = json!({
                "id":                      r.get::<Uuid, _>("id").to_string(),
                "tenant_id":               r.get::<Uuid, _>("tenant_id").to_string(),
                "name":                    r.get::<String, _>("name"),
                "code":                    r.get::<String, _>("code"),
                "description":             r.get::<Option<String>, _>("description"),
                "icon":                    r.get::<Option<String>, _>("icon"),
                "color":                   r.get::<Option<String>, _>("color"),
                "seq_prefix":              r.get::<Option<String>, _>("seq_prefix"),
                "seq_format":              r.get::<Option<String>, _>("seq_format"),
                "default_match_threshold": r.get::<Option<f64>, _>("default_match_threshold"),
                "is_system":               r.get::<bool, _>("is_system"),
                "is_active":               r.get::<bool, _>("is_active"),
                "created_at":              r.get::<chrono::DateTime<chrono::Utc>, _>("created_at").to_rfc3339(),
                "updated_at":              r.get::<chrono::DateTime<chrono::Utc>, _>("updated_at").to_rfc3339(),
            });
            (
                StatusCode::CREATED,
                Json(json!({ "success": true, "data": data })),
            )
                .into_response()
        }
        Err(err) => {
            error!(error=?err, "create_entity_type failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": "failed to create entity type" })),
            )
                .into_response()
        }
    }
}

// ── PATCH /entity-types/:id ───────────────────────────────────────────────────

pub async fn update_entity_type(
    State(state): State<Arc<AppState>>,
    Path(id):     Path<Uuid>,
    Json(body):   Json<serde_json::Value>,
) -> impl IntoResponse {
    // Build SET clause dynamically from whichever fields are present.
    // We always touch updated_at so the RETURNING row reflects the change.

    let mut set_clauses: Vec<String> = vec!["updated_at = NOW()".to_owned()];
    let mut idx: i32 = 1; // $1 is reserved for the WHERE id

    // Collect each optional field; we'll bind them in order below.
    // To keep the borrow-checker happy we collect Option<String> for each field.

    let name                    = body.get("name").and_then(|v| v.as_str()).map(str::to_owned);
    let description             = body.get("description").and_then(|v| v.as_str()).map(str::to_owned);
    let icon                    = body.get("icon").and_then(|v| v.as_str()).map(str::to_owned);
    let color                   = body.get("color").and_then(|v| v.as_str()).map(str::to_owned);
    let seq_prefix              = body.get("seq_prefix").and_then(|v| v.as_str()).map(str::to_owned);
    let seq_format              = body.get("seq_format").and_then(|v| v.as_str()).map(str::to_owned);
    let default_match_threshold = body.get("default_match_threshold").and_then(|v| v.as_f64());
    let is_active               = body.get("is_active").and_then(|v| v.as_bool());

    // Helper to bump idx for each bound parameter
    macro_rules! maybe_clause {
        ($opt:expr, $col:literal) => {
            if $opt.is_some() {
                idx += 1;
                set_clauses.push(format!("{} = ${}", $col, idx));
            }
        };
    }

    maybe_clause!(name,                    "name");
    maybe_clause!(description,             "description");
    maybe_clause!(icon,                    "icon");
    maybe_clause!(color,                   "color");
    maybe_clause!(seq_prefix,              "seq_prefix");
    maybe_clause!(seq_format,              "seq_format");
    maybe_clause!(default_match_threshold, "default_match_threshold");
    maybe_clause!(is_active,               "is_active");

    if set_clauses.len() == 1 {
        // Only updated_at — nothing actually changed
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({ "success": false, "error": "no fields provided for update" })),
        )
            .into_response();
    }

    let sql = format!(
        r#"
        UPDATE core_mdm.entity_type_configs
        SET {}
        WHERE id = $1 AND is_system = false
        RETURNING
            id, tenant_id, name, code, description, icon, color,
            seq_prefix, seq_format, default_match_threshold,
            is_system, is_active, created_at, updated_at
        "#,
        set_clauses.join(", ")
    );

    // Bind parameters in the same order they were added.
    let mut query = sqlx::query(&sql).bind(id);

    if let Some(v) = &name                    { query = query.bind(v); }
    if let Some(v) = &description             { query = query.bind(v); }
    if let Some(v) = &icon                    { query = query.bind(v); }
    if let Some(v) = &color                   { query = query.bind(v); }
    if let Some(v) = &seq_prefix              { query = query.bind(v); }
    if let Some(v) = &seq_format              { query = query.bind(v); }
    if let Some(v) = default_match_threshold  { query = query.bind(v); }
    if let Some(v) = is_active               { query = query.bind(v); }

    match query.fetch_optional(&state.db).await {
        Ok(Some(r)) => {
            let data = json!({
                "id":                      r.get::<Uuid, _>("id").to_string(),
                "tenant_id":               r.get::<Uuid, _>("tenant_id").to_string(),
                "name":                    r.get::<String, _>("name"),
                "code":                    r.get::<String, _>("code"),
                "description":             r.get::<Option<String>, _>("description"),
                "icon":                    r.get::<Option<String>, _>("icon"),
                "color":                   r.get::<Option<String>, _>("color"),
                "seq_prefix":              r.get::<Option<String>, _>("seq_prefix"),
                "seq_format":              r.get::<Option<String>, _>("seq_format"),
                "default_match_threshold": r.get::<Option<f64>, _>("default_match_threshold"),
                "is_system":               r.get::<bool, _>("is_system"),
                "is_active":               r.get::<bool, _>("is_active"),
                "created_at":              r.get::<chrono::DateTime<chrono::Utc>, _>("created_at").to_rfc3339(),
                "updated_at":              r.get::<chrono::DateTime<chrono::Utc>, _>("updated_at").to_rfc3339(),
            });
            (
                StatusCode::OK,
                Json(json!({ "success": true, "data": data })),
            )
                .into_response()
        }
        Ok(None) => (
            StatusCode::NOT_FOUND,
            Json(json!({ "success": false, "error": "entity type not found or is a system type" })),
        )
            .into_response(),
        Err(err) => {
            error!(error=?err, "update_entity_type failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": "failed to update entity type" })),
            )
                .into_response()
        }
    }
}

// ── DELETE /entity-types/:id ──────────────────────────────────────────────────

pub async fn delete_entity_type(
    State(state): State<Arc<AppState>>,
    Path(id):     Path<Uuid>,
) -> impl IntoResponse {
    let result = sqlx::query(
        r#"
        DELETE FROM core_mdm.entity_type_configs
        WHERE id = $1 AND is_system = false
        RETURNING id
        "#,
    )
    .bind(id)
    .fetch_optional(&state.db)
    .await;

    match result {
        Ok(Some(_)) => (
            StatusCode::OK,
            Json(json!({ "success": true, "data": { "id": id.to_string() } })),
        )
            .into_response(),
        Ok(None) => (
            StatusCode::NOT_FOUND,
            Json(json!({ "success": false, "error": "entity type not found or is a system type" })),
        )
            .into_response(),
        Err(err) => {
            error!(error=?err, "delete_entity_type failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": "failed to delete entity type" })),
            )
                .into_response()
        }
    }
}

// ── GET /entity-types/:code/attributes?tenant_id=... ─────────────────────────

pub async fn list_attributes(
    State(state):   State<Arc<AppState>>,
    Path(code):     Path<String>,
    Query(params):  Query<HashMap<String, String>>,
) -> impl IntoResponse {
    let tenant_id = match params
        .get("tenant_id")
        .and_then(|s| Uuid::parse_str(s).ok())
    {
        Some(id) => id,
        None => {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({ "success": false, "error": "tenant_id query param is required" })),
            )
                .into_response();
        }
    };

    let rows = sqlx::query(
        r#"
        SELECT
            a.id, a.tenant_id, a.entity_type_code, a.attribute_key,
            a.display_name, a.description, a.data_type,
            a.is_required, a.is_pii, a.is_searchable, a.is_system,
            a.display_order, a.enum_values, a.default_value, a.validation_regex,
            a.created_at, a.updated_at
        FROM core_mdm.attribute_schemas a
        WHERE a.tenant_id = $1
          AND a.entity_type_code = $2
        ORDER BY a.display_order ASC, a.attribute_key ASC
        "#,
    )
    .bind(tenant_id)
    .bind(&code)
    .fetch_all(&state.db)
    .await;

    match rows {
        Ok(rows) => {
            let items: Vec<serde_json::Value> = rows
                .iter()
                .map(|r| {
                    let enum_values: Option<serde_json::Value> = r
                        .try_get::<sqlx::types::Json<serde_json::Value>, _>("enum_values")
                        .ok()
                        .map(|j| j.0);

                    json!({
                        "id":               r.get::<Uuid, _>("id").to_string(),
                        "tenant_id":        r.get::<Uuid, _>("tenant_id").to_string(),
                        "entity_type_code": r.get::<String, _>("entity_type_code"),
                        "attribute_key":    r.get::<String, _>("attribute_key"),
                        "display_name":     r.get::<String, _>("display_name"),
                        "description":      r.get::<Option<String>, _>("description"),
                        "data_type":        r.get::<String, _>("data_type"),
                        "is_required":      r.get::<bool, _>("is_required"),
                        "is_pii":           r.get::<bool, _>("is_pii"),
                        "is_searchable":    r.get::<bool, _>("is_searchable"),
                        "is_system":        r.get::<bool, _>("is_system"),
                        "display_order":    r.get::<i32, _>("display_order"),
                        "enum_values":      enum_values,
                        "default_value":    r.get::<Option<String>, _>("default_value"),
                        "validation_regex": r.get::<Option<String>, _>("validation_regex"),
                        "created_at":       r.get::<chrono::DateTime<chrono::Utc>, _>("created_at").to_rfc3339(),
                        "updated_at":       r.get::<chrono::DateTime<chrono::Utc>, _>("updated_at").to_rfc3339(),
                    })
                })
                .collect();

            (
                StatusCode::OK,
                Json(json!({ "success": true, "data": items })),
            )
                .into_response()
        }
        Err(err) => {
            error!(error=?err, "list_attributes failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": "failed to list attributes" })),
            )
                .into_response()
        }
    }
}

// ── POST /entity-types/:code/attributes ──────────────────────────────────────

pub async fn create_attribute(
    State(state): State<Arc<AppState>>,
    Path(code):   Path<String>,
    Json(body):   Json<serde_json::Value>,
) -> impl IntoResponse {
    let tenant_id = match body
        .get("tenant_id")
        .and_then(|v| v.as_str())
        .and_then(|s| Uuid::parse_str(s).ok())
    {
        Some(id) => id,
        None => {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({ "success": false, "error": "tenant_id is required" })),
            )
                .into_response();
        }
    };

    let attribute_key = match body.get("attribute_key").and_then(|v| v.as_str()) {
        Some(s) => s.to_owned(),
        None => {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({ "success": false, "error": "attribute_key is required" })),
            )
                .into_response();
        }
    };

    let display_name = match body.get("display_name").and_then(|v| v.as_str()) {
        Some(s) => s.to_owned(),
        None => {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({ "success": false, "error": "display_name is required" })),
            )
                .into_response();
        }
    };

    let data_type = body
        .get("data_type")
        .and_then(|v| v.as_str())
        .unwrap_or("text")
        .to_owned();

    let description     = body.get("description").and_then(|v| v.as_str()).map(str::to_owned);
    let is_required     = body.get("is_required").and_then(|v| v.as_bool()).unwrap_or(false);
    let is_pii          = body.get("is_pii").and_then(|v| v.as_bool()).unwrap_or(false);
    let is_searchable   = body.get("is_searchable").and_then(|v| v.as_bool()).unwrap_or(true);
    let display_order   = body.get("display_order").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
    let default_value   = body.get("default_value").and_then(|v| v.as_str()).map(str::to_owned);
    let validation_regex = body.get("validation_regex").and_then(|v| v.as_str()).map(str::to_owned);
    let enum_values     = body.get("enum_values").cloned();

    let row = sqlx::query(
        r#"
        INSERT INTO core_mdm.attribute_schemas
            (tenant_id, entity_type_code, attribute_key, display_name, description,
             data_type, is_required, is_pii, is_searchable, display_order,
             enum_values, default_value, validation_regex)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
        RETURNING
            id, tenant_id, entity_type_code, attribute_key, display_name, description,
            data_type, is_required, is_pii, is_searchable, is_system,
            display_order, enum_values, default_value, validation_regex,
            created_at, updated_at
        "#,
    )
    .bind(tenant_id)
    .bind(&code)
    .bind(&attribute_key)
    .bind(&display_name)
    .bind(&description)
    .bind(&data_type)
    .bind(is_required)
    .bind(is_pii)
    .bind(is_searchable)
    .bind(display_order)
    .bind(enum_values.map(sqlx::types::Json))
    .bind(&default_value)
    .bind(&validation_regex)
    .fetch_one(&state.db)
    .await;

    match row {
        Ok(r) => {
            let enum_values: Option<serde_json::Value> = r
                .try_get::<sqlx::types::Json<serde_json::Value>, _>("enum_values")
                .ok()
                .map(|j| j.0);

            let data = json!({
                "id":               r.get::<Uuid, _>("id").to_string(),
                "tenant_id":        r.get::<Uuid, _>("tenant_id").to_string(),
                "entity_type_code": r.get::<String, _>("entity_type_code"),
                "attribute_key":    r.get::<String, _>("attribute_key"),
                "display_name":     r.get::<String, _>("display_name"),
                "description":      r.get::<Option<String>, _>("description"),
                "data_type":        r.get::<String, _>("data_type"),
                "is_required":      r.get::<bool, _>("is_required"),
                "is_pii":           r.get::<bool, _>("is_pii"),
                "is_searchable":    r.get::<bool, _>("is_searchable"),
                "is_system":        r.get::<bool, _>("is_system"),
                "display_order":    r.get::<i32, _>("display_order"),
                "enum_values":      enum_values,
                "default_value":    r.get::<Option<String>, _>("default_value"),
                "validation_regex": r.get::<Option<String>, _>("validation_regex"),
                "created_at":       r.get::<chrono::DateTime<chrono::Utc>, _>("created_at").to_rfc3339(),
                "updated_at":       r.get::<chrono::DateTime<chrono::Utc>, _>("updated_at").to_rfc3339(),
            });
            (
                StatusCode::CREATED,
                Json(json!({ "success": true, "data": data })),
            )
                .into_response()
        }
        Err(err) => {
            error!(error=?err, "create_attribute failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": "failed to create attribute" })),
            )
                .into_response()
        }
    }
}

// ── DELETE /entity-types/:code/attributes/:attr_id ────────────────────────────

pub async fn delete_attribute(
    State(state):          State<Arc<AppState>>,
    Path((code, attr_id)): Path<(String, Uuid)>,
) -> impl IntoResponse {
    let result = sqlx::query(
        r#"
        DELETE FROM core_mdm.attribute_schemas
        WHERE id = $1
          AND entity_type_code = $2
          AND is_system = false
        RETURNING id
        "#,
    )
    .bind(attr_id)
    .bind(&code)
    .fetch_optional(&state.db)
    .await;

    match result {
        Ok(Some(_)) => (
            StatusCode::OK,
            Json(json!({ "success": true, "data": { "id": attr_id.to_string() } })),
        )
            .into_response(),
        Ok(None) => (
            StatusCode::NOT_FOUND,
            Json(json!({ "success": false, "error": "attribute not found or is a system attribute" })),
        )
            .into_response(),
        Err(err) => {
            error!(error=?err, "delete_attribute failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": "failed to delete attribute" })),
            )
                .into_response()
        }
    }
}

// ── PUT /entity-types/:code/attributes/order ──────────────────────────────────

pub async fn reorder_attributes(
    State(state): State<Arc<AppState>>,
    Path(code):   Path<String>,
    Json(body):   Json<Vec<serde_json::Value>>,
) -> impl IntoResponse {
    if body.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({ "success": false, "error": "order list cannot be empty" })),
        )
            .into_response();
    }

    // Begin a transaction so all updates succeed or none do.
    let mut tx = match state.db.begin().await {
        Ok(t)  => t,
        Err(e) => {
            error!(error=?e, "failed to begin transaction for reorder_attributes");
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": "transaction error" })),
            )
                .into_response();
        }
    };

    for item in &body {
        let attr_id = match item
            .get("id")
            .and_then(|v| v.as_str())
            .and_then(|s| Uuid::parse_str(s).ok())
        {
            Some(id) => id,
            None => {
                return (
                    StatusCode::BAD_REQUEST,
                    Json(json!({ "success": false, "error": "each item must have a valid 'id'" })),
                )
                    .into_response();
            }
        };

        let display_order = match item.get("display_order").and_then(|v| v.as_i64()) {
            Some(o) => o as i32,
            None => {
                return (
                    StatusCode::BAD_REQUEST,
                    Json(json!({ "success": false, "error": "each item must have 'display_order'" })),
                )
                    .into_response();
            }
        };

        if let Err(e) = sqlx::query(
            r#"
            UPDATE core_mdm.attribute_schemas
            SET display_order = $1, updated_at = NOW()
            WHERE id = $2 AND entity_type_code = $3
            "#,
        )
        .bind(display_order)
        .bind(attr_id)
        .bind(&code)
        .execute(&mut *tx)
        .await
        {
            error!(error=?e, "reorder_attributes update failed");
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": "failed to update display order" })),
            )
                .into_response();
        }
    }

    if let Err(e) = tx.commit().await {
        error!(error=?e, "reorder_attributes commit failed");
        return (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": "commit failed" })),
        )
            .into_response();
    }

    (
        StatusCode::OK,
        Json(json!({ "success": true, "data": { "updated": body.len() } })),
    )
        .into_response()
}

// ── GET /entity-types/:code/next-sequence?tenant_id=...&period_key=global ────

pub async fn next_sequence(
    State(state):  State<Arc<AppState>>,
    Path(code):    Path<String>,
    Query(params): Query<HashMap<String, String>>,
) -> impl IntoResponse {
    let tenant_id = match params
        .get("tenant_id")
        .and_then(|s| Uuid::parse_str(s).ok())
    {
        Some(id) => id,
        None => {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({ "success": false, "error": "tenant_id query param is required" })),
            )
                .into_response();
        }
    };

    let period_key = params
        .get("period_key")
        .cloned()
        .unwrap_or_else(|| "global".to_owned());

    // Fetch the entity type config to get seq_prefix and seq_format.
    let config_row = sqlx::query(
        r#"
        SELECT seq_prefix, seq_format
        FROM core_mdm.entity_type_configs
        WHERE tenant_id = $1 AND code = $2
        "#,
    )
    .bind(tenant_id)
    .bind(&code)
    .fetch_optional(&state.db)
    .await;

    let (seq_prefix, seq_format) = match config_row {
        Ok(Some(r)) => {
            let prefix = r
                .get::<Option<String>, _>("seq_prefix")
                .unwrap_or_else(|| code.to_uppercase());
            let format = r
                .get::<Option<String>, _>("seq_format")
                .unwrap_or_else(|| "{PREFIX}-{YYYY}-{SEQ5}".to_owned());
            (prefix, format)
        }
        Ok(None) => {
            return (
                StatusCode::NOT_FOUND,
                Json(json!({ "success": false, "error": "entity type not found" })),
            )
                .into_response();
        }
        Err(err) => {
            error!(error=?err, "next_sequence config fetch failed");
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": "failed to fetch entity type config" })),
            )
                .into_response();
        }
    };

    // Call the DB sequence function.
    let seq_result: Result<Option<i64>, _> = sqlx::query_scalar(
        r#"SELECT core_mdm.next_sequence_value($1, $2, $3)"#,
    )
    .bind(tenant_id)
    .bind(&code)
    .bind(&period_key)
    .fetch_one(&state.db)
    .await;

    match seq_result {
        Ok(Some(seq_value)) => {
            let formatted_id = format_sequence_id(&seq_format, &seq_prefix, seq_value);
            (
                StatusCode::OK,
                Json(json!({
                    "success": true,
                    "data": {
                        "sequence_value": seq_value,
                        "formatted_id":   formatted_id,
                        "entity_type_code": code,
                        "period_key":     period_key,
                    }
                })),
            )
                .into_response()
        }
        Ok(None) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": "sequence function returned null" })),
        )
            .into_response(),
        Err(err) => {
            error!(error=?err, "next_sequence_value call failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": "failed to generate sequence value" })),
            )
                .into_response()
        }
    }
}
