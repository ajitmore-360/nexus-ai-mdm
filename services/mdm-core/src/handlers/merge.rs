use std::sync::Arc;

use axum::{
    extract::State,
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use tracing::error;

use contracts::mdm::merge::MergeRequest;

use crate::handlers::{entities::extract_request_context, ApiResponse};
use crate::middleware::tenant::TenantContext;
use crate::AppState;

/// POST /merge
///
/// Executes a full entity merge:
/// 1. Loads entities from the database
/// 2. Applies survivorship rules (tenant-configured, with AI assist if enabled)
/// 3. Creates and persists a golden record
/// 4. Updates merged entity statuses to `Merged`
/// 5. Emits `GoldenRecordCreated` + `EntityMerged` outbox events (Kafka delivery)
///
/// This replaces the previous in-memory-only merge that called `apply_survivorship()`
/// directly without persistence or event sourcing.
pub async fn execute_merge(
    State(state):          State<Arc<AppState>>,
    axum::Extension(tenant_ctx): axum::Extension<TenantContext>,
    headers:               HeaderMap,
    Json(request):         Json<MergeRequest>,
) -> Response {
    let ctx = extract_request_context(&tenant_ctx, &headers);

    match state.merge_service.execute_merge(ctx, request).await {
        Ok(result) => (
            StatusCode::OK,
            Json(ApiResponse {
                success: true,
                data:    Some(result),
                error:   None,
            }),
        ).into_response(),
        Err(err) => {
            error!(error=?err, "merge execution failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<serde_json::Value> {
                    success: false,
                    data:    None,
                    error:   Some(err.to_string()),
                }),
            ).into_response()
        }
    }
}
