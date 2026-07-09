use std::sync::Arc;

use axum::{
    extract::{Extension, Path, Query, State},
    Json,
};
use azile_auth::Claims;
use serde::Deserialize;
use serde_json::json;
use uuid::Uuid;

use crate::crypto::{encrypt_config, decrypt_config};
use crate::state::AppState;

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// REQUEST / RESPONSE TYPES
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

#[derive(Debug, Deserialize)]
pub struct ListSourceSystemsParams {
    pub limit:  Option<i64>,
    pub offset: Option<i64>,
}

#[derive(Debug, Deserialize)]
pub struct CreateSourceSystemRequest {
    pub name:             String,
    pub code:             String,
    pub connector_type:   String,
    pub description:      Option<String>,
    pub icon:             Option<String>,
    pub trust_weight:     Option<f64>,
    pub priority:         Option<i32>,
    pub entity_types:     Option<Vec<String>>,
    pub sync_mode:        Option<String>,
    pub connection_config: Option<serde_json::Value>,
}

#[derive(Debug, Deserialize)]
pub struct UpdateSourceSystemRequest {
    pub name:              Option<String>,
    pub description:       Option<String>,
    pub icon:              Option<String>,
    pub trust_weight:      Option<f64>,
    pub priority:          Option<i32>,
    pub entity_types:      Option<Vec<String>>,
    pub sync_mode:         Option<String>,
    pub sync_schedule:     Option<String>,
    pub is_active:         Option<bool>,
    pub connection_config: Option<serde_json::Value>,
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// HELPERS
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

const VALID_CONNECTOR_TYPES: &[&str] = &[
    "salesforce", "sap", "csv", "kafka", "rest_api", "database", "hubspot", "custom",
    "oracle", "jdbc", "s3", "manual",
];

const VALID_SYNC_MODES: &[&str] = &["manual", "scheduled", "realtime"];

fn validate_connector_type(ct: &str) -> Result<(), String> {
    let ct_lower = ct.to_lowercase();
    if VALID_CONNECTOR_TYPES.contains(&ct_lower.as_str()) {
        Ok(())
    } else {
        Err(format!(
            "invalid connector_type '{}': must be one of {:?}",
            ct, VALID_CONNECTOR_TYPES
        ))
    }
}

fn validate_sync_mode(sm: &str) -> Result<(), String> {
    let sm_lower = sm.to_lowercase();
    if VALID_SYNC_MODES.contains(&sm_lower.as_str()) {
        Ok(())
    } else {
        Err(format!(
            "invalid sync_mode '{}': must be one of {:?}",
            sm, VALID_SYNC_MODES
        ))
    }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// HANDLERS
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

/// GET /source-systems?tenant_id=&limit=&offset=
///
/// List all source systems registered for the given tenant.
pub async fn list_source_systems(
    State(state):      State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Query(params):     Query<ListSourceSystemsParams>,
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
             trust_weight::float8, priority,
             entity_types, sync_mode,
             is_active, is_connected,
             created_at
         FROM core_mdm.source_systems_registry
         WHERE tenant_id = $1
         ORDER BY priority ASC, created_at ASC
         LIMIT $2 OFFSET $3",
    )
    .bind(claims.nxs_tenant_id)
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

/// POST /source-systems â€” register a new source system
pub async fn create_source_system(
    State(state):      State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Json(body):        Json<CreateSourceSystemRequest>,
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

    let connector_type_lc = body.connector_type.to_lowercase();
    let sync_mode = body.sync_mode.as_deref().unwrap_or("manual").to_lowercase();
    let sync_mode = sync_mode.as_str();
    if let Err(e) = validate_sync_mode(sync_mode) {
        return Json(json!({ "success": false, "error": e }));
    }

    let id           = Uuid::new_v4();
    let trust_weight = body.trust_weight.unwrap_or(1.0);
    let priority     = body.priority.unwrap_or(100);
    let entity_types = body.entity_types.as_deref().unwrap_or(&[]);
    let icon         = body.icon.as_deref().unwrap_or("ðŸ”Œ");

    let raw_config    = body.connection_config.unwrap_or_else(|| serde_json::json!({}));
    let stored_config = encrypt_config(&raw_config);

    match sqlx::query(
        "INSERT INTO core_mdm.source_systems_registry (
             id, tenant_id, name, code, connector_type,
             description, icon, connection_config,
             trust_weight, priority, entity_types,
             sync_mode, is_active, is_connected,
             created_at, updated_at
         ) VALUES (
             $1, $2, $3, $4, $5,
             $6, $7, $8,
             $9, $10, $11,
             $12, TRUE, FALSE,
             NOW(), NOW()
         )",
    )
    .bind(id)
    .bind(claims.nxs_tenant_id)
    .bind(&body.name)
    .bind(&body.code)
    .bind(&connector_type_lc)
    .bind(body.description.as_deref())
    .bind(icon)
    .bind(sqlx::types::Json(&stored_config))
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
                "tenant_id":      claims.nxs_tenant_id,
                "name":           body.name,
                "code":           body.code,
                "connector_type": connector_type_lc,
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

/// PUT /source-systems/:id â€” update a source system
pub async fn update_source_system(
    State(state):      State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(id):          Path<Uuid>,
    Json(body):        Json<UpdateSourceSystemRequest>,
) -> Json<serde_json::Value> {
    // Validate optional fields that have restricted value sets
    if let Some(ref sm) = body.sync_mode {
        if let Err(e) = validate_sync_mode(sm) {
            return Json(json!({ "success": false, "error": e }));
        }
    }

    // Encrypt connection_config if provided before storing
    let encrypted_config: Option<serde_json::Value> =
        body.connection_config.as_ref().map(|cfg| encrypt_config(cfg));

    // Use COALESCE so unprovided fields are left untouched â€” simpler than
    // building a dynamic SET clause and equally correct for sparse updates.
    match sqlx::query_scalar::<_, Uuid>(
        "UPDATE core_mdm.source_systems_registry SET
             name              = COALESCE($1, name),
             description       = COALESCE($2, description),
             icon              = COALESCE($3, icon),
             trust_weight      = COALESCE($4, trust_weight),
             priority          = COALESCE($5, priority),
             entity_types      = COALESCE($6, entity_types),
             sync_mode         = COALESCE($7, sync_mode),
             sync_schedule     = COALESCE($8, sync_schedule),
             is_active         = COALESCE($9, is_active),
             connection_config = COALESCE($10, connection_config),
             updated_at        = NOW()
         WHERE id = $11 AND tenant_id = $12
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
    .bind(encrypted_config.as_ref().map(sqlx::types::Json))
    .bind(id)
    .bind(claims.nxs_tenant_id)
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

/// DELETE /source-systems/:id â€” remove a source system
pub async fn delete_source_system(
    State(state):      State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(id):          Path<Uuid>,
) -> Json<serde_json::Value> {
    match sqlx::query_scalar::<_, Uuid>(
        "DELETE FROM core_mdm.source_systems_registry
         WHERE id = $1 AND tenant_id = $2
         RETURNING id",
    )
    .bind(id)
    .bind(claims.nxs_tenant_id)
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

/// POST /source-systems/:id/test â€” probe actual connectivity for a source system.
///
/// Fetches `connector_type` and decrypted `connection_config`, then dispatches
/// to a per-connector probe. Updates `is_connected` based on the outcome.
pub async fn test_connection(
    State(state):      State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Path(id):          Path<Uuid>,
) -> Json<serde_json::Value> {
    // Fetch name, type, and stored (possibly encrypted) connection_config.
    match sqlx::query_as::<_, (Uuid, String, String, serde_json::Value)>(
        "SELECT id, name, connector_type, connection_config
         FROM core_mdm.source_systems_registry
         WHERE id = $1 AND tenant_id = $2",
    )
    .bind(id)
    .bind(claims.nxs_tenant_id)
    .fetch_optional(&state.pool)
    .await
    {
        Ok(Some((sid, name, connector_type, stored_cfg))) => {
            let config = decrypt_config(&stored_cfg);
            let sw = std::time::Instant::now();
            let probe = probe_connector(&connector_type, &config).await;
            let latency_ms = sw.elapsed().as_millis() as u64;

            let connected = probe.is_ok();
            let message   = probe.unwrap_or_else(|e| e);

            let _ = sqlx::query(
                "UPDATE core_mdm.source_systems_registry
                 SET is_connected = $1, updated_at = NOW()
                 WHERE id = $2",
            )
            .bind(connected)
            .bind(sid)
            .execute(&state.pool)
            .await;

            if connected {
                Json(json!({
                    "success": true,
                    "data": {
                        "id":             sid,
                        "name":           name,
                        "connector_type": connector_type,
                        "connected":      true,
                        "latency_ms":     latency_ms,
                        "message":        message,
                    }
                }))
            } else {
                Json(json!({
                    "success": false,
                    "error": message,
                    "data": {
                        "id":        sid,
                        "connected": false,
                        "latency_ms": latency_ms,
                    }
                }))
            }
        }
        Ok(None) => Json(json!({
            "success": false,
            "error": format!("source system {} not found", id),
        })),
        Err(e) => Json(json!({ "success": false, "error": e.to_string() })),
    }
}

/// Connector-specific probe logic. Returns `Ok(message)` on success, `Err(reason)` on failure.
async fn probe_connector(
    connector_type: &str,
    config: &serde_json::Value,
) -> Result<String, String> {
    match connector_type {
        "rest_api" => probe_rest_api(config).await,
        "s3"       => probe_s3(config).await,
        "database" | "jdbc" | "oracle" => probe_tcp(config, connector_type).await,
        "kafka"    => probe_tcp_host_port(
            config.get("bootstrap_servers")
                  .and_then(|v| v.as_str())
                  .unwrap_or("localhost:9092"),
        ).await,
        "salesforce" => probe_rest_api_url(
            config.get("instance_url").and_then(|v| v.as_str()).unwrap_or(""),
        ).await,
        "hubspot" => probe_rest_api_url("https://api.hubapi.com").await,
        "sap" => probe_tcp_host_port(
            &format!(
                "{}:{}",
                config.get("host").and_then(|v| v.as_str()).unwrap_or(""),
                config.get("port").and_then(|v| v.as_str()).unwrap_or("3300"),
            )
        ).await,
        // CSV, manual, custom â€” no live probe possible
        _ => Ok("No live probe for this connector type (config saved)".to_string()),
    }
}

async fn probe_rest_api(config: &serde_json::Value) -> Result<String, String> {
    let url = config.get("base_url")
        .and_then(|v| v.as_str())
        .ok_or_else(|| "base_url not configured".to_string())?;
    if url.is_empty() {
        return Err("URL not configured".to_string());
    }
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(8))
        .build()
        .map_err(|e| e.to_string())?;
    let req = crate::scheduler::apply_auth(client.get(url), config);
    match req.send().await {
        Ok(resp) => Ok(format!("HTTP {} â€” reachable", resp.status())),
        Err(e) if e.is_timeout() => Err("Connection timed out".to_string()),
        Err(e) if e.is_connect() => Err(format!("Cannot connect: {}", e)),
        Err(e) => Err(e.to_string()),
    }
}

async fn probe_rest_api_url(url: &str) -> Result<String, String> {
    if url.is_empty() {
        return Err("URL not configured".to_string());
    }
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(8))
        .build()
        .map_err(|e| e.to_string())?;

    match client.get(url).send().await {
        Ok(resp) => Ok(format!("HTTP {} â€” reachable", resp.status())),
        Err(e) if e.is_timeout() => Err("Connection timed out".to_string()),
        Err(e) if e.is_connect() => Err(format!("Cannot connect: {}", e)),
        Err(e) => Err(e.to_string()),
    }
}

async fn probe_tcp(config: &serde_json::Value, kind: &str) -> Result<String, String> {
    let host = config.get("host").and_then(|v| v.as_str()).unwrap_or("");
    let default_port = match kind {
        "oracle" => "1521",
        "jdbc"   => "5432",
        _        => "5432",
    };
    let port = config.get("port").and_then(|v| v.as_str()).unwrap_or(default_port);
    probe_tcp_host_port(&format!("{}:{}", host, port)).await
}

async fn probe_tcp_host_port(addr: &str) -> Result<String, String> {
    if addr.starts_with(':') || addr.is_empty() {
        return Err("Host not configured".to_string());
    }
    use tokio::net::TcpStream;
    use tokio::time::timeout;
    match timeout(
        std::time::Duration::from_secs(5),
        TcpStream::connect(addr),
    )
    .await
    {
        Ok(Ok(_))  => Ok(format!("TCP connection to {} succeeded", addr)),
        Ok(Err(e)) => Err(format!("TCP connect failed: {}", e)),
        Err(_)     => Err(format!("Connection to {} timed out", addr)),
    }
}

async fn probe_s3(config: &serde_json::Value) -> Result<String, String> {
    let bucket = config.get("bucket").and_then(|v| v.as_str()).unwrap_or("");
    let region = config.get("region").and_then(|v| v.as_str()).unwrap_or("us-east-1");
    if bucket.is_empty() {
        return Err("S3 bucket not configured".to_string());
    }
    // Probe S3 endpoint reachability (no SDK required)
    let url = format!("https://{}.s3.{}.amazonaws.com/", bucket, region);
    probe_rest_api_url(&url).await
}
