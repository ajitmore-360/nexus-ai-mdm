use std::sync::Arc;

use axum::{
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    Extension, Json,
};
use serde_json::json;
use sqlx::Row;
use tracing::error;
use uuid::Uuid;

use crate::middleware::tenant::TenantContext;
use crate::services::audit_service::AuditEvent;
use crate::AppState;

// ── Role guard helper ─────────────────────────────────────────────────────────

fn require_admin_role(headers: &HeaderMap) -> Result<(), axum::response::Response> {
    let role = headers
        .get("x-user-role")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("viewer");
    if matches!(role, "admin" | "business_admin") {
        Ok(())
    } else {
        Err((
            StatusCode::FORBIDDEN,
            Json(json!({
                "success": false,
                "error": "Only Business Admin or Admin can manage reference data"
            })),
        )
            .into_response())
    }
}

fn actor_id(headers: &HeaderMap) -> Option<Uuid> {
    headers
        .get("x-user-id")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| Uuid::parse_str(s).ok())
}

// ── GET /submasters ────────────────────────────────────────────────────────────

pub async fn list_submaster_types(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
) -> impl IntoResponse {
    let rows = sqlx::query(
        r#"
        SELECT id, tenant_id, code, name, description, is_active, is_system, created_at, updated_at
        FROM core_mdm.submaster_types
        WHERE tenant_id = $1
        ORDER BY name
        "#,
    )
    .bind(tenant_ctx.tenant_id)
    .fetch_all(&state.db)
    .await;

    match rows {
        Ok(rows) => {
            let items: Vec<serde_json::Value> = rows
                .iter()
                .map(|r| json!({
                    "id":          r.get::<Uuid, _>("id").to_string(),
                    "tenant_id":   r.get::<Uuid, _>("tenant_id").to_string(),
                    "code":        r.get::<String, _>("code"),
                    "name":        r.get::<String, _>("name"),
                    "description": r.get::<Option<String>, _>("description"),
                    "is_active":   r.get::<bool, _>("is_active"),
                    "is_system":   r.get::<bool, _>("is_system"),
                    "created_at":  r.get::<chrono::DateTime<chrono::Utc>, _>("created_at").to_rfc3339(),
                    "updated_at":  r.get::<chrono::DateTime<chrono::Utc>, _>("updated_at").to_rfc3339(),
                }))
                .collect();
            (StatusCode::OK, Json(json!({ "success": true, "data": items }))).into_response()
        }
        Err(err) => {
            error!(error=?err, "list_submaster_types failed");
            (StatusCode::INTERNAL_SERVER_ERROR,
             Json(json!({ "success": false, "error": "failed to list reference data types" }))).into_response()
        }
    }
}

// ── POST /submasters ───────────────────────────────────────────────────────────

pub async fn create_submaster_type(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    headers:               HeaderMap,
    Json(body):            Json<serde_json::Value>,
) -> impl IntoResponse {
    if let Err(resp) = require_admin_role(&headers) {
        return resp;
    }

    let code = match body.get("code").and_then(|v| v.as_str()) {
        Some(s) => s.to_owned(),
        None => return (StatusCode::BAD_REQUEST,
                        Json(json!({ "success": false, "error": "code is required" }))).into_response(),
    };
    let name = match body.get("name").and_then(|v| v.as_str()) {
        Some(s) => s.to_owned(),
        None => return (StatusCode::BAD_REQUEST,
                        Json(json!({ "success": false, "error": "name is required" }))).into_response(),
    };
    let description = body.get("description").and_then(|v| v.as_str()).map(str::to_owned);

    let row = sqlx::query(
        r#"
        INSERT INTO core_mdm.submaster_types (tenant_id, code, name, description, created_by)
        VALUES ($1, $2, $3, $4, $5)
        RETURNING id, tenant_id, code, name, description, is_active, is_system, created_at, updated_at
        "#,
    )
    .bind(tenant_ctx.tenant_id)
    .bind(&code)
    .bind(&name)
    .bind(&description)
    .bind(actor_id(&headers))
    .fetch_one(&state.db)
    .await;

    match row {
        Ok(r) => {
            let type_id = r.get::<Uuid, _>("id");
            state.audit_service.log_background(AuditEvent {
                tenant_id:     tenant_ctx.tenant_id,
                event_type:    "submaster_type.created".to_string(),
                actor_id:      actor_id(&headers),
                resource_type: "submaster_type".to_string(),
                resource_id:   type_id.to_string(),
                metadata:      json!({ "code": code, "name": name }),
                before:        None,
                after:         None,
            });
            (StatusCode::CREATED, Json(json!({ "success": true, "data": {
                "id":          type_id.to_string(),
                "tenant_id":   r.get::<Uuid, _>("tenant_id").to_string(),
                "code":        r.get::<String, _>("code"),
                "name":        r.get::<String, _>("name"),
                "description": r.get::<Option<String>, _>("description"),
                "is_active":   r.get::<bool, _>("is_active"),
                "is_system":   r.get::<bool, _>("is_system"),
                "created_at":  r.get::<chrono::DateTime<chrono::Utc>, _>("created_at").to_rfc3339(),
                "updated_at":  r.get::<chrono::DateTime<chrono::Utc>, _>("updated_at").to_rfc3339(),
            }}))).into_response()
        }
        Err(err) => {
            let msg = err.to_string();
            if msg.contains("duplicate key") || msg.contains("unique") {
                return (StatusCode::CONFLICT,
                        Json(json!({ "success": false, "error": "a reference data type with this code already exists" }))).into_response();
            }
            error!(error=?err, "create_submaster_type failed");
            (StatusCode::INTERNAL_SERVER_ERROR,
             Json(json!({ "success": false, "error": "failed to create reference data type" }))).into_response()
        }
    }
}

// ── PATCH /submasters/:code ────────────────────────────────────────────────────

pub async fn update_submaster_type(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    headers:               HeaderMap,
    Path(code):            Path<String>,
    Json(body):            Json<serde_json::Value>,
) -> impl IntoResponse {
    if let Err(resp) = require_admin_role(&headers) {
        return resp;
    }

    let name        = body.get("name").and_then(|v| v.as_str()).map(str::to_owned);
    let description = body.get("description").and_then(|v| v.as_str()).map(str::to_owned);
    let is_active   = body.get("is_active").and_then(|v| v.as_bool());

    let mut set_parts: Vec<String> = vec!["updated_at = NOW()".to_owned()];
    let mut idx: i32 = 1; // $1 = WHERE code, $2 = WHERE tenant_id

    macro_rules! maybe {
        ($opt:expr, $col:literal) => {
            if $opt.is_some() {
                idx += 1;
                set_parts.push(format!("{} = ${}", $col, idx + 1));
            }
        };
    }
    maybe!(name,        "name");
    maybe!(description, "description");
    maybe!(is_active,   "is_active");

    let sql = format!(
        r#"
        UPDATE core_mdm.submaster_types
        SET {set}
        WHERE code = $1 AND tenant_id = $2 AND is_system = false
        RETURNING id, tenant_id, code, name, description, is_active, is_system, created_at, updated_at
        "#,
        set = set_parts.join(", "),
    );

    let mut query = sqlx::query(&sql).bind(&code).bind(tenant_ctx.tenant_id);
    if let Some(v) = &name        { query = query.bind(v); }
    if let Some(v) = &description { query = query.bind(v); }
    if let Some(v) = is_active    { query = query.bind(v); }

    match query.fetch_optional(&state.db).await {
        Ok(Some(r)) => {
            (StatusCode::OK, Json(json!({ "success": true, "data": {
                "id":          r.get::<Uuid, _>("id").to_string(),
                "code":        r.get::<String, _>("code"),
                "name":        r.get::<String, _>("name"),
                "description": r.get::<Option<String>, _>("description"),
                "is_active":   r.get::<bool, _>("is_active"),
                "updated_at":  r.get::<chrono::DateTime<chrono::Utc>, _>("updated_at").to_rfc3339(),
            }}))).into_response()
        }
        Ok(None) => (StatusCode::NOT_FOUND,
                     Json(json!({ "success": false, "error": "reference data type not found or is a system type" }))).into_response(),
        Err(err) => {
            error!(error=?err, "update_submaster_type failed");
            (StatusCode::INTERNAL_SERVER_ERROR,
             Json(json!({ "success": false, "error": "failed to update reference data type" }))).into_response()
        }
    }
}

// ── GET /submasters/:code/values ───────────────────────────────────────────────

pub async fn list_submaster_values(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(code):            Path<String>,
) -> impl IntoResponse {
    let rows = sqlx::query(
        r#"
        SELECT v.id, v.tenant_id, v.submaster_type_id, v.code, v.label,
               v.description, v.sort_order, v.is_active, v.created_at, v.updated_at
        FROM core_mdm.submaster_values v
        JOIN core_mdm.submaster_types  t ON t.id = v.submaster_type_id
        WHERE t.code = $1 AND t.tenant_id = $2 AND v.is_active = true
        ORDER BY v.sort_order, v.label
        "#,
    )
    .bind(&code)
    .bind(tenant_ctx.tenant_id)
    .fetch_all(&state.db)
    .await;

    match rows {
        Ok(rows) => {
            let items: Vec<serde_json::Value> = rows
                .iter()
                .map(|r| json!({
                    "id":                 r.get::<Uuid, _>("id").to_string(),
                    "submaster_type_id":  r.get::<Uuid, _>("submaster_type_id").to_string(),
                    "code":               r.get::<String, _>("code"),
                    "label":              r.get::<String, _>("label"),
                    "description":        r.get::<Option<String>, _>("description"),
                    "sort_order":         r.get::<i32, _>("sort_order"),
                    "is_active":          r.get::<bool, _>("is_active"),
                    "created_at":         r.get::<chrono::DateTime<chrono::Utc>, _>("created_at").to_rfc3339(),
                }))
                .collect();
            (StatusCode::OK, Json(json!({ "success": true, "data": items }))).into_response()
        }
        Err(err) => {
            error!(error=?err, code=%code, "list_submaster_values failed");
            (StatusCode::INTERNAL_SERVER_ERROR,
             Json(json!({ "success": false, "error": "failed to list reference data values" }))).into_response()
        }
    }
}

// ── POST /submasters/:code/values ──────────────────────────────────────────────

pub async fn create_submaster_value(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    headers:               HeaderMap,
    Path(code):            Path<String>,
    Json(body):            Json<serde_json::Value>,
) -> impl IntoResponse {
    if let Err(resp) = require_admin_role(&headers) {
        return resp;
    }

    let value_code = match body.get("code").and_then(|v| v.as_str()) {
        Some(s) => s.to_owned(),
        None => return (StatusCode::BAD_REQUEST,
                        Json(json!({ "success": false, "error": "code is required" }))).into_response(),
    };
    let label = match body.get("label").and_then(|v| v.as_str()) {
        Some(s) => s.to_owned(),
        None => return (StatusCode::BAD_REQUEST,
                        Json(json!({ "success": false, "error": "label is required" }))).into_response(),
    };
    let description = body.get("description").and_then(|v| v.as_str()).map(str::to_owned);
    let sort_order  = body.get("sort_order").and_then(|v| v.as_i64()).unwrap_or(0) as i32;

    // Resolve type_id from code
    let type_id: Option<Uuid> = sqlx::query_scalar(
        "SELECT id FROM core_mdm.submaster_types WHERE code = $1 AND tenant_id = $2 AND is_active = true",
    )
    .bind(&code)
    .bind(tenant_ctx.tenant_id)
    .fetch_optional(&state.db)
    .await
    .unwrap_or(None);

    let type_id = match type_id {
        Some(id) => id,
        None => return (StatusCode::NOT_FOUND,
                        Json(json!({ "success": false, "error": "reference data type not found" }))).into_response(),
    };

    let row = sqlx::query(
        r#"
        INSERT INTO core_mdm.submaster_values (tenant_id, submaster_type_id, code, label, description, sort_order)
        VALUES ($1, $2, $3, $4, $5, $6)
        RETURNING id, tenant_id, submaster_type_id, code, label, description, sort_order, is_active, created_at, updated_at
        "#,
    )
    .bind(tenant_ctx.tenant_id)
    .bind(type_id)
    .bind(&value_code)
    .bind(&label)
    .bind(&description)
    .bind(sort_order)
    .fetch_one(&state.db)
    .await;

    match row {
        Ok(r) => {
            let val_id = r.get::<Uuid, _>("id");
            state.audit_service.log_background(AuditEvent {
                tenant_id:     tenant_ctx.tenant_id,
                event_type:    "submaster_value.created".to_string(),
                actor_id:      actor_id(&headers),
                resource_type: "submaster_value".to_string(),
                resource_id:   val_id.to_string(),
                metadata:      json!({ "type_code": code, "value_code": value_code, "label": label }),
                before:        None,
                after:         None,
            });
            (StatusCode::CREATED, Json(json!({ "success": true, "data": {
                "id":                r.get::<Uuid, _>("id").to_string(),
                "submaster_type_id": r.get::<Uuid, _>("submaster_type_id").to_string(),
                "code":              r.get::<String, _>("code"),
                "label":             r.get::<String, _>("label"),
                "description":       r.get::<Option<String>, _>("description"),
                "sort_order":        r.get::<i32, _>("sort_order"),
                "is_active":         r.get::<bool, _>("is_active"),
                "created_at":        r.get::<chrono::DateTime<chrono::Utc>, _>("created_at").to_rfc3339(),
            }}))).into_response()
        }
        Err(err) => {
            let msg = err.to_string();
            if msg.contains("duplicate key") || msg.contains("unique") {
                return (StatusCode::CONFLICT,
                        Json(json!({ "success": false, "error": "a value with this code already exists in this reference data type" }))).into_response();
            }
            error!(error=?err, "create_submaster_value failed");
            (StatusCode::INTERNAL_SERVER_ERROR,
             Json(json!({ "success": false, "error": "failed to create reference data value" }))).into_response()
        }
    }
}

// ── PATCH /submasters/:code/values/:value_id ───────────────────────────────────

pub async fn update_submaster_value(
    State(state):                 State<Arc<AppState>>,
    Extension(tenant_ctx):        Extension<TenantContext>,
    headers:                      HeaderMap,
    Path((code, value_id)):       Path<(String, Uuid)>,
    Json(body):                   Json<serde_json::Value>,
) -> impl IntoResponse {
    if let Err(resp) = require_admin_role(&headers) {
        return resp;
    }

    let label       = body.get("label").and_then(|v| v.as_str()).map(str::to_owned);
    let description = body.get("description").and_then(|v| v.as_str()).map(str::to_owned);
    let sort_order  = body.get("sort_order").and_then(|v| v.as_i64()).map(|v| v as i32);
    let is_active   = body.get("is_active").and_then(|v| v.as_bool());

    let row = sqlx::query(
        r#"
        UPDATE core_mdm.submaster_values v
        SET label       = COALESCE($3, v.label),
            description = COALESCE($4, v.description),
            sort_order  = COALESCE($5, v.sort_order),
            is_active   = COALESCE($6, v.is_active),
            updated_at  = NOW()
        FROM core_mdm.submaster_types t
        WHERE v.id              = $1
          AND v.tenant_id       = $2
          AND t.id              = v.submaster_type_id
          AND t.code            = $7
        RETURNING v.id, v.code, v.label, v.description, v.sort_order, v.is_active, v.updated_at
        "#,
    )
    .bind(value_id)
    .bind(tenant_ctx.tenant_id)
    .bind(&label)
    .bind(&description)
    .bind(sort_order)
    .bind(is_active)
    .bind(&code)
    .fetch_optional(&state.db)
    .await;

    match row {
        Ok(Some(r)) => (StatusCode::OK, Json(json!({ "success": true, "data": {
            "id":          r.get::<Uuid, _>("id").to_string(),
            "code":        r.get::<String, _>("code"),
            "label":       r.get::<String, _>("label"),
            "description": r.get::<Option<String>, _>("description"),
            "sort_order":  r.get::<i32, _>("sort_order"),
            "is_active":   r.get::<bool, _>("is_active"),
            "updated_at":  r.get::<chrono::DateTime<chrono::Utc>, _>("updated_at").to_rfc3339(),
        }}))).into_response(),
        Ok(None) => (StatusCode::NOT_FOUND,
                     Json(json!({ "success": false, "error": "reference data value not found" }))).into_response(),
        Err(err) => {
            error!(error=?err, "update_submaster_value failed");
            (StatusCode::INTERNAL_SERVER_ERROR,
             Json(json!({ "success": false, "error": "failed to update reference data value" }))).into_response()
        }
    }
}

// ── DELETE /submasters/:code/values/:value_id — soft deactivate ────────────────

pub async fn delete_submaster_value(
    State(state):                 State<Arc<AppState>>,
    Extension(tenant_ctx):        Extension<TenantContext>,
    headers:                      HeaderMap,
    Path((code, value_id)):       Path<(String, Uuid)>,
) -> impl IntoResponse {
    if let Err(resp) = require_admin_role(&headers) {
        return resp;
    }

    let row = sqlx::query(
        r#"
        UPDATE core_mdm.submaster_values v
        SET is_active  = false,
            updated_at = NOW()
        FROM core_mdm.submaster_types t
        WHERE v.id        = $1
          AND v.tenant_id = $2
          AND t.id        = v.submaster_type_id
          AND t.code      = $3
        RETURNING v.id
        "#,
    )
    .bind(value_id)
    .bind(tenant_ctx.tenant_id)
    .bind(&code)
    .fetch_optional(&state.db)
    .await;

    match row {
        Ok(Some(_)) => {
            state.audit_service.log_background(AuditEvent {
                tenant_id:     tenant_ctx.tenant_id,
                event_type:    "submaster_value.deactivated".to_string(),
                actor_id:      actor_id(&headers),
                resource_type: "submaster_value".to_string(),
                resource_id:   value_id.to_string(),
                metadata:      json!({ "type_code": code }),
                before:        None,
                after:         None,
            });
            (StatusCode::OK, Json(json!({ "success": true, "data": { "id": value_id.to_string() } }))).into_response()
        }
        Ok(None) => (StatusCode::NOT_FOUND,
                     Json(json!({ "success": false, "error": "reference data value not found" }))).into_response(),
        Err(err) => {
            error!(error=?err, "delete_submaster_value failed");
            (StatusCode::INTERNAL_SERVER_ERROR,
             Json(json!({ "success": false, "error": "failed to deactivate reference data value" }))).into_response()
        }
    }
}
