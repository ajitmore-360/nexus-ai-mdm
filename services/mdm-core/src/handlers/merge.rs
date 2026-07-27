use std::sync::Arc;

use axum::{
    extract::State,
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use tracing::error;
use uuid::Uuid;

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

    // Enforce review-before-merge: block if any candidate in the merge set still
    // has an open human-review flag.  Data Owners must approve via the match
    // review queue before a merge can proceed.
    let candidate_ids: Vec<Uuid> = request.candidate_entities
        .iter()
        .map(|c| c.entity_id)
        .collect();

    for &candidate_id in &candidate_ids {
        let pending: i64 = match sqlx::query_scalar(
            "SELECT COUNT(*) \
             FROM   core_mdm.match_candidates \
             WHERE  tenant_id           = $1 \
               AND  (   source_entity_id    = $2 \
                     OR candidate_entity_id = $2) \
               AND  requires_human_review = TRUE \
               AND  match_status          = 'RequiresReview'",
        )
        .bind(tenant_ctx.tenant_id)
        .bind(candidate_id)
        .fetch_one(&state.db)
        .await
        {
            Ok(n) => n,
            Err(e) => {
                error!(error=?e, "merge gate: failed to check pending reviews");
                return (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ApiResponse::<serde_json::Value> {
                        success: false,
                        data:    None,
                        error:   Some("failed to verify review status".to_string()),
                    }),
                ).into_response();
            }
        };

        if pending > 0 {
            return (
                StatusCode::CONFLICT,
                Json(ApiResponse::<serde_json::Value> {
                    success: false,
                    data:    None,
                    error:   Some(format!(
                        "Merge blocked: {} match candidate{} for entity {} still require{} \
                         Data Owner approval. Please review and approve in the match queue first.",
                        pending,
                        if pending == 1 { "" } else { "s" },
                        candidate_id,
                        if pending == 1 { "s" } else { "" },
                    )),
                }),
            ).into_response();
        }
    }

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
