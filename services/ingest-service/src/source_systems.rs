use std::sync::Arc;

use axum::{
    extract::{Path, Query, State},
    Json,
};
use serde::Deserialize;
use serde_json::json;
use uuid::Uuid;

use crate::state::AppState;

// ─────────────────────────────────────────────────────────────────────────────
// REQUEST / RESPONSE TYPES
// ─────────────────────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct ListSourceSystemsParams {
    pub tenant_id: Uuid,
    pub limit:     Option<i64>,
    pub offset:    Option<i64>,
}

#[derive(Debug, Deserialize)]
pub struct CreateSourceSystemRequest {
    pub tenant_id:      Uuid,
    pub name:           String,
    pub code:           String,
    pub connector_type: String,
    pub description:    Option<String>,
    pub icon:           Option<String>,
    pub trust_weight:   Option<f64>,
    pub priority:       Option<i32>,
    pub entity_types:   Option<Vec<String>>,
    pub sync_mode:      Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct UpdateSourceSystemRequest {
    pub name:           Option<String>,
    pub description:    Option<String>,
    pub icon:           Option<String>,
    pub trust_weight:   Option<f64>,
    pub priority:       Option<i32>,
    pub entity_types:   Option<Vec<String>>,
    pub sync_mode:      Option<String>,
    pub sync_schedule:  Option<String>,
    pub is_active:      Option<bool>,
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

const VALID_CONNECTOR_TYPES: &[&str] = &[
    "salesforce", "sap", "csv", "kafka", "rest_api", "database", "hubspot", "custom",
];

const VALID_SYNC_MODES: &[&str] = &["manual", "scheduled", "realtime"];

fn validate_connector_type(ct: &str) -> Result<(), String> {
    if VALID_CONNECTOR_TYPES.contains(&ct) {
        Ok(())
    } else {
        Err(format!(
            "invalid connector_type '{}': must be one of {:?}",
            ct, VALID_CONNECTOR_TYPES
        ))
    }
}

fn validate_sync_mode(sm: &str) -> Result<(), String> {
    if VALID_SYNC_MODES.contains(&sm) {
        Ok(())
    } else {
        Err(format!(
            "invalid sync_mode '{}': must be one of {:?}",
            sm, VALID_SYNC_MODES
        ))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// HANDLERS
// ─────────────────────────────────────────────────────────────────────────────

/// GET /source-systems?tenant_id=&limit=&offset=
///
/// List all source systems registered for the given tenant.
pub async fn list_source_systems(
    State(state): State<Arc<AppState>>,
    Query(params): Query<ListSourceSystemsParams>,
) -> Json<serde_json::Value> {
    let limit  = params.limit.unwrap_or(50).min(500);
    let offset = params.offset.unwrap_or(0).max(0);

    match sqlx::query_as::<_, (
        Uuid,
        Uuid,
        String,
        String,
        String,
        Option<String>,
        Option<String>,
        f64,
        i32,
        Vec<String>,
        String,
        bool,
        bool,
        chrono::DateTime<chrono::Utc>,
    )>(
        "SELECT
             id, tenant_id, name, code, connector_type,
             description, icon,
             trust_weight, priority,
             entity_types, sync_mode,
             is_active, is_connected,
             created_at
         FROM core_mdm.source_systems_registry
         WHERE tenant_id = $1
         ORDER BY priority ASC, created_at ASC
         LIMIT $2 OFFSET $3",
    )
    .bind(params.tenant_id)
    .bind(limit)
    .bind(offset)
    .fetch_all(&state.pool)
    .await
    {
        Ok(rows) => {
            let systems: Vec<serde_json::Value> = rows
                .into_iter()
                .map(|(id, tid, name, code, connector_type, description, icon,
                        trust_weight, priority, entity_types, sync_mode,
                        is_active, is_connected, created_at)| {
                    json!({
                        "id":             id,
                        "tenant_id":      tid,
                        "name":           name,
                        "code":           code,
                        "connector_type": connector_type,
                        "description":    description,
                        "icon":           icon,
                        "trust_weight":   trust_weight,
                        "priority":       priority,
                        "entity_types":   entity_types,
                        "sync_mode":      sync_mode,
                        "is_active":      is_active,
                        "is_connected":   is_connected,
                        "created_at":     created_at,
                    })
                })
                .collect();
            Json(json!({ "success": true, "data": systems }))
        }
        Err(e) => Json(json!({ "success": false, "error": e.to_string() })),
    }
}

/// POST /source-systems — register a new source system
pub async fn create_source_system(
    State(state): State<Arc<AppState>>,
    Json(body): Json<CreateSourceSystemRequest>,
) -> Json<serde_json::Value> {
    if body.name.trim().is_empty() {
        return Json(json!({ "success": false, "error": "name is required" }));
    }
    if body.code.trim().is_empty() {
        return Json(json!({ "success": false, "error": "code is required" }));
    }
    if let Err(e) = validate_connector_type(&body.connector_type) {
        return Json(json!({ "success": false, "error": e }));
    }

    let sync_mode = body.sync_mode.as_deref().unwrap_or("manual");
    if let Err(e) = validate_sync_mode(sync_mode) {
        return Json(json!({ "success": false, "error": e }));
    }

    let id           = Uuid::new_v4();
    let trust_weight = body.trust_weight.unwrap_or(1.0);
    let priority     = body.priority.unwrap_or(100);
    let entity_types = body.entity_types.as_deref().unwrap_or(&[]);
    let icon         = body.icon.as_deref().unwrap_or("🔌");

    match sqlx::query(
        "INSERT INTO core_mdm.source_systems_registry (
             id, tenant_id, name, code, connector_type,
             description, icon, connection_config,
             trust_weight, priority, entity_types,
             sync_mode, is_active, is_connected,
             created_at, updated_at
         ) VALUES (
             $1, $2, $3, $4, $5,
             $6, $7, '{}',
             $8, $9, $10,
             $11, TRUE, FALSE,
             NOW(), NOW()
         )",
    )
    .bind(id)
    .bind(body.tenant_id)
    .bind(&body.name)
    .bind(&body.code)
    .bind(&body.connector_type)
    .bind(body.description.as_deref())
    .bind(icon)
    .bind(trust_weight)
    .bind(priority)
    .bind(entity_types)
    .bind(sync_mode)
    .execute(&state.pool)
    .await
    {
        Ok(_) => Json(json!({
            "success": true,
            "data": {
                "id":             id,
                "tenant_id":      body.tenant_id,
                "name":           body.name,
                "code":           body.code,
                "connector_type": body.connector_type,
                "sync_mode":      sync_mode,
                "trust_weight":   trust_weight,
                "priority":       priority,
                "is_active":      true,
                "is_connected":   false,
            }
        })),
        Err(e) => Json(json!({ "success": false, "error": e.to_string() })),
    }
}

/// PUT /source-systems/:id — update a source system
pub async fn update_source_system(
    State(state): State<Arc<AppState>>,
    Path(id): Path<Uuid>,
    Json(body): Json<UpdateSourceSystemRequest>,
) -> Json<serde_json::Value> {
    // Validate optional fields that have restricted value sets
    if let Some(ref sm) = body.sync_mode {
        if let Err(e) = validate_sync_mode(sm) {
            return Json(json!({ "success": false, "error": e }));
        }
    }

    // Use COALESCE so unprovided fields are left untouched — simpler than
    // building a dynamic SET clause and equally correct for sparse updates.
    match sqlx::query_scalar::<_, Uuid>(
        "UPDATE core_mdm.source_systems_registry SET
             name           = COALESCE($1, name),
             description    = COALESCE($2, description),
             icon           = COALESCE($3, icon),
             trust_weight   = COALESCE($4, trust_weight),
             priority       = COALESCE($5, priority),
             entity_types   = COALESCE($6, entity_types),
             sync_mode      = COALESCE($7, sync_mode),
             sync_schedule  = COALESCE($8, sync_schedule),
             is_active      = COALESCE($9, is_active),
             updated_at     = NOW()
         WHERE id = $10
         RETURNING id",
    )
    .bind(body.name.as_deref())
    .bind(body.description.as_deref())
    .bind(body.icon.as_deref())
    .bind(body.trust_weight)
    .bind(body.priority)
    .bind(body.entity_types.as_deref())
    .bind(body.sync_mode.as_deref())
    .bind(body.sync_schedule.as_deref())
    .bind(body.is_active)
    .bind(id)
    .fetch_optional(&state.pool)
    .await
    {
        Ok(Some(updated_id)) => Json(json!({
            "success": true,
            "data": { "id": updated_id }
        })),
        Ok(None) => Json(json!({
            "success": false,
            "error":   format!("source system {} not found", id),
        })),
        Err(e) => Json(json!({ "success": false, "error": e.to_string() })),
    }
}

/// DELETE /source-systems/:id — remove a source system
pub async fn delete_source_system(
    State(state): State<Arc<AppState>>,
    Path(id): Path<Uuid>,
) -> Json<serde_json::Value> {
    match sqlx::query_scalar::<_, Uuid>(
        "DELETE FROM core_mdm.source_systems_registry
         WHERE id = $1
         RETURNING id",
    )
    .bind(id)
    .fetch_optional(&state.pool)
    .await
    {
        Ok(Some(deleted_id)) => Json(json!({
            "success": true,
            "data": { "id": deleted_id, "deleted": true }
        })),
        Ok(None) => Json(json!({
            "success": false,
            "error":   format!("source system {} not found", id),
        })),
        Err(e) => Json(json!({ "success": false, "error": e.to_string() })),
    }
}

/// POST /source-systems/:id/test — test connectivity for a source system
///
/// Returns a mock success response for now.  When real connectors are
/// implemented each `connector_type` will have its own probe logic here.
pub async fn test_connection(
    State(state): State<Arc<AppState>>,
    Path(id): Path<Uuid>,
) -> Json<serde_json::Value> {
    // Verify the source system exists and fetch its type for a useful response.
    match sqlx::query_as::<_, (Uuid, String, String)>(
        "SELECT id, name, connector_type
         FROM core_mdm.source_systems_registry
         WHERE id = $1",
    )
    .bind(id)
    .fetch_optional(&state.pool)
    .await
    {
        Ok(Some((sid, name, connector_type))) => {
            // Mark is_connected = true after a successful test.
            let _ = sqlx::query(
                "UPDATE core_mdm.source_systems_registry
                 SET is_connected = TRUE, updated_at = NOW()
                 WHERE id = $1",
            )
            .bind(sid)
            .execute(&state.pool)
            .await;

            Json(json!({
                "success": true,
                "data": {
                    "id":             sid,
                    "name":           name,
                    "connector_type": connector_type,
                    "connected":      true,
                    "latency_ms":     0,
                    "message":        "Connection test successful (mock)",
                }
            }))
        }
        Ok(None) => Json(json!({
            "success": false,
            "error":   format!("source system {} not found", id),
        })),
        Err(e) => Json(json!({ "success": false, "error": e.to_string() })),
    }
}
