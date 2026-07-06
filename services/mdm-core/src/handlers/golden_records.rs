use std::sync::Arc;

use axum::{
    extract::{Path, Query, State},
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    Extension, Json,
};
use chrono::Utc;
use serde::Deserialize;
use serde_json::json;
use uuid::Uuid;

use crate::handlers::{entities::extract_request_context, ApiResponse};
use crate::middleware::tenant::TenantContext;
use crate::AppState;

// ── GET /golden-records ───────────────────────────────────────────────────────

#[derive(Deserialize)]
pub struct ListGoldenRecordsParams {
    pub page:        Option<i64>,
    pub page_size:   Option<i64>,
    pub entity_type: Option<String>,
}

pub async fn list_golden_records(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Query(params):         Query<ListGoldenRecordsParams>,
) -> impl IntoResponse {
    let page      = params.page.unwrap_or(1).max(1);
    let page_size = params.page_size.unwrap_or(20).clamp(1, 100);
    let offset    = (page - 1) * page_size;

    match state
        .golden_record_service
        .list(
            tenant_ctx.tenant_id,
            params.entity_type.as_deref(),
            page_size,
            offset,
        )
        .await
    {
        Ok(records) => (
            StatusCode::OK,
            Json(json!({
                "success":   true,
                "items":     records,
                "page":      page,
                "page_size": page_size,
            })),
        ).into_response(),
        Err(e) => {
            tracing::error!(error=%e, "list golden records failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": e.to_string() })),
            ).into_response()
        }
    }
}

// ── GET /golden-records/:id ───────────────────────────────────────────────────

pub async fn get_golden_record(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(id):              Path<Uuid>,
) -> impl IntoResponse {
    match state.golden_record_service.get(tenant_ctx.tenant_id, id).await {
        Ok(Some(record)) => (
            StatusCode::OK,
            Json(ApiResponse { success: true, data: Some(record), error: None }),
        ).into_response(),
        Ok(None) => (
            StatusCode::NOT_FOUND,
            Json(json!({ "success": false, "error": "golden record not found" })),
        ).into_response(),
        Err(e) => {
            tracing::error!(error=%e, "get golden record failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": e.to_string() })),
            ).into_response()
        }
    }
}

// ── PATCH /golden-records/:id/attributes ─────────────────────────────────────

#[derive(Deserialize)]
pub struct AttributeOverride {
    pub attribute_key: String,
    pub value:         serde_json::Value,
    pub reason:        Option<String>,
}

#[derive(Deserialize)]
pub struct PatchAttributesRequest {
    pub overrides: Vec<AttributeOverride>,
}

/// Apply manual attribute-level survivorship overrides to a golden record.
///
/// For each override in the request:
/// - Updates `attribute_value`, `overridden_by_user`, `overridden_at`,
///   `override_reason`, and `survivorship_strategy = 'Override'`
/// - Records an outbox event for downstream consumers
pub async fn patch_golden_record_attributes(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    headers:               HeaderMap,
    Path(id):              Path<Uuid>,
    Json(req):             Json<PatchAttributesRequest>,
) -> impl IntoResponse {
    if req.overrides.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({ "success": false, "error": "overrides array must not be empty" })),
        ).into_response();
    }

    let ctx = extract_request_context(&tenant_ctx, &headers);

    // Verify the golden record exists and belongs to this tenant.
    let exists = match state
        .golden_record_service
        .get(tenant_ctx.tenant_id, id)
        .await
    {
        Ok(Some(_)) => true,
        Ok(None) => false,
        Err(e) => {
            tracing::error!(error=%e, "golden record lookup failed");
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": e.to_string() })),
            ).into_response();
        }
    };

    if !exists {
        return (
            StatusCode::NOT_FOUND,
            Json(json!({ "success": false, "error": "golden record not found" })),
        ).into_response();
    }

    let now = Utc::now();
    let mut applied   = Vec::new();
    let mut not_found = Vec::new();

    for ov in &req.overrides {
        let normalized = ov.value.as_str().map(str::to_owned)
            .unwrap_or_else(|| ov.value.to_string());

        let result = sqlx::query(
            r#"
            UPDATE core_mdm.golden_record_attributes
               SET attribute_value       = $1,
                   normalized_value      = $2,
                   survivorship_strategy = 'Override',
                   overridden_by_user    = $3,
                   overridden_at         = $4,
                   override_reason       = $5,
                   updated_at            = $4
             WHERE golden_record_id = $6
               AND tenant_id        = $7
               AND attribute_key    = $8
               AND is_current       = true
            "#,
        )
        .bind(serde_json::Value::String(normalized.clone()))
        .bind(&normalized)
        .bind(ctx.user_id)
        .bind(now)
        .bind(ov.reason.as_deref())
        .bind(id)
        .bind(tenant_ctx.tenant_id)
        .bind(&ov.attribute_key)
        .execute(&state.db)
        .await;

        match result {
            Ok(r) if r.rows_affected() > 0 => applied.push(&ov.attribute_key),
            Ok(_) => not_found.push(&ov.attribute_key),
            Err(e) => {
                tracing::error!(
                    error=%e,
                    attribute_key=%ov.attribute_key,
                    "attribute override update failed"
                );
                return (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(json!({ "success": false, "error": e.to_string() })),
                ).into_response();
            }
        }
    }

    // Touch the golden record's updated_at so caches/subscribers see a change.
    let _ = sqlx::query(
        "UPDATE core_mdm.golden_records SET updated_at = $1 WHERE golden_record_id = $2 AND tenant_id = $3",
    )
    .bind(now)
    .bind(id)
    .bind(tenant_ctx.tenant_id)
    .execute(&state.db)
    .await;

    // Emit an outbox event so downstream services (search index, Kafka consumers)
    // learn about the manual override without polling.
    let _ = sqlx::query(
        r#"
        INSERT INTO event_store.outbox_events
            (tenant_id, aggregate_type, aggregate_id, event_type, event_payload, topic_name)
        VALUES ($1, 'golden_record', $2, 'GoldenRecordAttributesOverridden',
                $3::jsonb, 'mdm.golden.events')
        "#,
    )
    .bind(tenant_ctx.tenant_id)
    .bind(id)
    .bind(serde_json::json!({
        "golden_record_id": id,
        "overridden_keys":  applied,
        "user_id":          ctx.user_id,
    }).to_string())
    .execute(&state.db)
    .await;

    (
        StatusCode::OK,
        Json(json!({
            "success":   true,
            "applied":   applied,
            "not_found": not_found,
        })),
    ).into_response()
}
