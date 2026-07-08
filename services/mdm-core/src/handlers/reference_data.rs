use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::IntoResponse,
    Extension, Json,
};
use serde::Deserialize;
use serde_json::json;
use std::sync::Arc;
use uuid::Uuid;

use crate::middleware::tenant::TenantContext;
use crate::services::reference_data_service::{CreateListInput, UpsertValueInput};
use crate::AppState;

#[derive(Deserialize)]
pub struct ValueListParams {
    pub search:      Option<String>,
    pub parent_code: Option<String>,
    pub limit:       Option<i64>,
    pub offset:      Option<i64>,
}

#[derive(Deserialize)]
pub struct BulkImportBody {
    pub values: Vec<UpsertValueInput>,
}

/// GET /reference-data — list all code lists for this tenant
pub async fn list_reference_lists(
    State(state): State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
) -> impl IntoResponse {
    match state.reference_data_service.list_lists(tenant_ctx.tenant_id).await {
        Ok(data) => (StatusCode::OK, Json(json!({ "success": true, "data": data }))).into_response(),
        Err(e)   => (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

/// POST /reference-data — create or update a code list
pub async fn create_reference_list(
    State(state): State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Json(body): Json<CreateListInput>,
) -> impl IntoResponse {
    match state.reference_data_service.create_list(tenant_ctx.tenant_id, body).await {
        Ok(id) => (StatusCode::CREATED, Json(json!({ "success": true, "data": { "id": id } }))).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

/// GET /reference-data/:list_id/values
pub async fn get_reference_values(
    State(state): State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(list_id): Path<Uuid>,
    Query(params): Query<ValueListParams>,
) -> impl IntoResponse {
    let limit  = params.limit.unwrap_or(100).min(1000);
    let offset = params.offset.unwrap_or(0);

    match state.reference_data_service.get_values(
        tenant_ctx.tenant_id,
        list_id,
        params.search.as_deref(),
        params.parent_code.as_deref(),
        limit,
        offset,
    ).await {
        Ok(data) => (StatusCode::OK, Json(json!({ "success": true, "data": data }))).into_response(),
        Err(e)   => (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

/// POST /reference-data/:list_id/values — upsert a single value
pub async fn upsert_reference_value(
    State(state): State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(list_id): Path<Uuid>,
    Json(body): Json<UpsertValueInput>,
) -> impl IntoResponse {
    match state.reference_data_service.upsert_value(tenant_ctx.tenant_id, list_id, body).await {
        Ok(id) => (StatusCode::OK, Json(json!({ "success": true, "data": { "id": id } }))).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

/// POST /reference-data/:list_id/values/bulk — bulk import
pub async fn bulk_import_values(
    State(state): State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(list_id): Path<Uuid>,
    Json(body): Json<BulkImportBody>,
) -> impl IntoResponse {
    if body.values.is_empty() {
        return (StatusCode::BAD_REQUEST, Json(json!({ "success": false, "error": "values array is empty" }))).into_response();
    }

    match state.reference_data_service.bulk_import_values(tenant_ctx.tenant_id, list_id, body.values).await {
        Ok(count) => (StatusCode::OK, Json(json!({ "success": true, "data": { "imported": count } }))).into_response(),
        Err(e)    => (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}

/// DELETE /reference-data/:list_id/values/:value_id
pub async fn delete_reference_value(
    State(state): State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path((_list_id, value_id)): Path<(Uuid, Uuid)>,
) -> impl IntoResponse {
    match state.reference_data_service.delete_value(tenant_ctx.tenant_id, value_id).await {
        Ok(true)  => (StatusCode::OK, Json(json!({ "success": true, "data": { "deleted": true } }))).into_response(),
        Ok(false) => (StatusCode::NOT_FOUND, Json(json!({ "success": false, "error": "Value not found" }))).into_response(),
        Err(e)    => (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "success": false, "error": e.to_string() }))).into_response(),
    }
}
