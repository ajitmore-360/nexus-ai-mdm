use std::sync::Arc;

use axum::{
    extract::{Path, Query, State},
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    Extension, Json,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::handlers::{entities::extract_request_context, ApiResponse};
use crate::middleware::tenant::TenantContext;
use crate::AppState;

#[derive(Deserialize)]
pub struct ReviewQueueParams {
    pub limit:  Option<i64>,
    pub offset: Option<i64>,
}

#[derive(Deserialize)]
pub struct ReviewDecisionBody {
    pub notes: Option<String>,
}

/// GET /match/review-queue?limit=&offset=
/// Returns all match candidates that require human review, newest first.
pub async fn get_review_queue(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Query(params):         Query<ReviewQueueParams>,
) -> impl IntoResponse {
    let limit  = params.limit.unwrap_or(20).clamp(1, 100);
    let offset = params.offset.unwrap_or(0).max(0);

    match state.review_service.get_queue(tenant_ctx.tenant_id, limit, offset).await {
        Ok(queue) => (
            StatusCode::OK,
            Json(ApiResponse {
                success: true,
                data:    Some(serde_json::json!({ "items": queue, "limit": limit, "offset": offset })),
                error:   None,
            }),
        ),
        Err(err) => {
            tracing::error!(error=?err, "review queue fetch failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<serde_json::Value> {
                    success: false,
                    data:    None,
                    error:   Some(err.to_string()),
                }),
            )
        }
    }
}

/// POST /match/:request_id/candidates/:candidate_id/approve
/// Steward approves a match candidate — marks it Matched and emits a feedback event.
pub async fn approve_match(
    State(state):              State<Arc<AppState>>,
    Extension(tenant_ctx):     Extension<TenantContext>,
    headers:                   HeaderMap,
    Path((request_id, candidate_id)): Path<(Uuid, Uuid)>,
    body: Option<Json<ReviewDecisionBody>>,
) -> impl IntoResponse {
    let ctx   = extract_request_context(&tenant_ctx, &headers);
    let notes = body.and_then(|b| b.notes.clone());

    match state.review_service.approve(ctx, request_id, candidate_id, notes).await {
        Ok(()) => (
            StatusCode::OK,
            Json(ApiResponse::<serde_json::Value> {
                success: true,
                data:    Some(serde_json::json!({ "request_id": request_id, "candidate_id": candidate_id, "status": "Matched" })),
                error:   None,
            }),
        ),
        Err(err) => {
            tracing::error!(error=?err, "match approve failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<serde_json::Value> {
                    success: false,
                    data:    None,
                    error:   Some(err.to_string()),
                }),
            )
        }
    }
}

/// POST /match/:request_id/candidates/:candidate_id/reject
/// Steward rejects a match candidate — marks it Rejected and emits a feedback event.
pub async fn reject_match(
    State(state):              State<Arc<AppState>>,
    Extension(tenant_ctx):     Extension<TenantContext>,
    headers:                   HeaderMap,
    Path((request_id, candidate_id)): Path<(Uuid, Uuid)>,
    body: Option<Json<ReviewDecisionBody>>,
) -> impl IntoResponse {
    let ctx   = extract_request_context(&tenant_ctx, &headers);
    let notes = body.and_then(|b| b.notes.clone());

    match state.review_service.reject(ctx, request_id, candidate_id, notes).await {
        Ok(()) => (
            StatusCode::OK,
            Json(ApiResponse::<serde_json::Value> {
                success: true,
                data:    Some(serde_json::json!({ "request_id": request_id, "candidate_id": candidate_id, "status": "Rejected" })),
                error:   None,
            }),
        ),
        Err(err) => {
            tracing::error!(error=?err, "match reject failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<serde_json::Value> {
                    success: false,
                    data:    None,
                    error:   Some(err.to_string()),
                }),
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Queue metrics
// ---------------------------------------------------------------------------

#[derive(Serialize)]
pub struct QueueMetrics {
    pub pending_total:        i64,
    pub pending_by_domain:    serde_json::Value,
    pub pending_by_priority:  PriorityBreakdown,
    pub sla_breached:         i64,
    pub avg_age_hours:        f64,
    pub oldest_pending_hours: f64,
}

#[derive(Serialize, Default)]
pub struct PriorityBreakdown {
    pub critical: i64,
    pub high:     i64,
    pub normal:   i64,
    pub low:      i64,
}

/// GET /match/queue-metrics
/// Returns aggregate queue health metrics for the calling tenant.
pub async fn queue_metrics(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
) -> impl IntoResponse {
    let tenant_id = tenant_ctx.tenant_id;
    let pool      = &state.db;

    // Total pending
    let pending_total: i64 = sqlx::query_scalar::<_, i64>(
        "SELECT COUNT(*) FROM core_mdm.match_review_queue \
         WHERE tenant_id = $1 AND review_status = 'Pending'",
    )
    .bind(tenant_id)
    .fetch_one(pool)
    .await
    .unwrap_or(0);

    // By priority
    let priority_rows: Vec<(String, i64)> = sqlx::query_as::<_, (String, i64)>(
        "SELECT priority, COUNT(*) \
         FROM core_mdm.match_review_queue \
         WHERE tenant_id = $1 AND review_status = 'Pending' \
         GROUP BY priority",
    )
    .bind(tenant_id)
    .fetch_all(pool)
    .await
    .unwrap_or_default();

    let mut breakdown = PriorityBreakdown::default();
    for (priority, count) in priority_rows {
        match priority.to_lowercase().as_str() {
            "critical" => breakdown.critical = count,
            "high"     => breakdown.high     = count,
            "normal"   => breakdown.normal   = count,
            "low"      => breakdown.low      = count,
            _          => {}
        }
    }

    // SLA breached (pending > 24 h)
    let sla_breached: i64 = sqlx::query_scalar::<_, i64>(
        "SELECT COUNT(*) FROM core_mdm.match_review_queue \
         WHERE tenant_id = $1 AND review_status = 'Pending' \
           AND created_at < NOW() - INTERVAL '24 hours'",
    )
    .bind(tenant_id)
    .fetch_one(pool)
    .await
    .unwrap_or(0);

    // Average age in hours
    let avg_age_hours: f64 = sqlx::query_scalar::<_, f64>(
        "SELECT COALESCE(EXTRACT(EPOCH FROM AVG(NOW() - created_at)) / 3600, 0) \
         FROM core_mdm.match_review_queue \
         WHERE tenant_id = $1 AND review_status = 'Pending'",
    )
    .bind(tenant_id)
    .fetch_one(pool)
    .await
    .unwrap_or(0.0_f64);

    // Oldest pending item in hours
    let oldest_pending_hours: f64 = sqlx::query_scalar::<_, f64>(
        "SELECT COALESCE(EXTRACT(EPOCH FROM MAX(NOW() - created_at)) / 3600, 0) \
         FROM core_mdm.match_review_queue \
         WHERE tenant_id = $1 AND review_status = 'Pending'",
    )
    .bind(tenant_id)
    .fetch_one(pool)
    .await
    .unwrap_or(0.0_f64);

    let metrics = QueueMetrics {
        pending_total,
        pending_by_domain:   serde_json::json!({}),
        pending_by_priority: breakdown,
        sla_breached,
        avg_age_hours,
        oldest_pending_hours,
    };

    (
        StatusCode::OK,
        Json(ApiResponse {
            success: true,
            data:    Some(metrics),
            error:   None,
        }),
    )
}

// ---------------------------------------------------------------------------
// Bulk approve / reject
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct BulkCandidatesBody {
    pub candidate_ids: Vec<Uuid>,
}

/// POST /match/bulk-approve
/// Atomically approves all supplied review-queue rows that are still Pending.
pub async fn bulk_approve_matches(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    headers:               HeaderMap,
    Json(body):            Json<BulkCandidatesBody>,
) -> impl IntoResponse {
    let tenant_id = tenant_ctx.tenant_id;
    let ctx       = extract_request_context(&tenant_ctx, &headers);
    let user_id   = ctx.user_id;

    let result = sqlx::query(
        "UPDATE core_mdm.match_review_queue \
         SET review_status = 'Approved', reviewed_at = NOW(), reviewed_by = $3 \
         WHERE review_id = ANY($1::uuid[]) \
           AND tenant_id = $2 \
           AND review_status = 'Pending'",
    )
    .bind(body.candidate_ids.as_slice())
    .bind(tenant_id)
    .bind(user_id)
    .execute(&state.db)
    .await;

    match result {
        Ok(pg) => {
            let approved = pg.rows_affected() as i64;
            let failed   = body.candidate_ids.len() as i64 - approved;
            (
                StatusCode::OK,
                Json(ApiResponse {
                    success: true,
                    data:    Some(serde_json::json!({ "approved": approved, "failed": failed })),
                    error:   None,
                }),
            )
        }
        Err(err) => {
            tracing::error!(error=?err, "bulk approve failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<serde_json::Value> {
                    success: false,
                    data:    None,
                    error:   Some(err.to_string()),
                }),
            )
        }
    }
}

/// POST /match/bulk-reject
/// Atomically rejects all supplied review-queue rows that are still Pending.
pub async fn bulk_reject_matches(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    headers:               HeaderMap,
    Json(body):            Json<BulkCandidatesBody>,
) -> impl IntoResponse {
    let tenant_id = tenant_ctx.tenant_id;
    let ctx       = extract_request_context(&tenant_ctx, &headers);
    let user_id   = ctx.user_id;

    let result = sqlx::query(
        "UPDATE core_mdm.match_review_queue \
         SET review_status = 'Rejected', reviewed_at = NOW(), reviewed_by = $3 \
         WHERE review_id = ANY($1::uuid[]) \
           AND tenant_id = $2 \
           AND review_status = 'Pending'",
    )
    .bind(body.candidate_ids.as_slice())
    .bind(tenant_id)
    .bind(user_id)
    .execute(&state.db)
    .await;

    match result {
        Ok(pg) => {
            let rejected = pg.rows_affected() as i64;
            let failed   = body.candidate_ids.len() as i64 - rejected;
            (
                StatusCode::OK,
                Json(ApiResponse {
                    success: true,
                    data:    Some(serde_json::json!({ "rejected": rejected, "failed": failed })),
                    error:   None,
                }),
            )
        }
        Err(err) => {
            tracing::error!(error=?err, "bulk reject failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<serde_json::Value> {
                    success: false,
                    data:    None,
                    error:   Some(err.to_string()),
                }),
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Defer a single match candidate
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct DeferBody {
    pub reason:   Option<String>,
    pub due_date: Option<String>,
}

/// POST /match/:request_id/candidates/:candidate_id/defer
/// Moves a single pending review item into Deferred status.
pub async fn defer_match(
    State(state):              State<Arc<AppState>>,
    Extension(tenant_ctx):     Extension<TenantContext>,
    Path((_request_id, candidate_id)): Path<(Uuid, Uuid)>,
    body: Option<Json<DeferBody>>,
) -> impl IntoResponse {
    let tenant_id = tenant_ctx.tenant_id;
    let reason    = body.as_ref().and_then(|b| b.reason.clone());

    let result = sqlx::query(
        "UPDATE core_mdm.match_review_queue \
         SET review_status = 'Deferred', review_notes = $3 \
         WHERE tenant_id = $1 \
           AND match_candidate_id = $2 \
           AND review_status = 'Pending'",
    )
    .bind(tenant_id)
    .bind(candidate_id)
    .bind(reason)
    .execute(&state.db)
    .await;

    match result {
        Ok(pg) if pg.rows_affected() > 0 => (
            StatusCode::OK,
            Json(ApiResponse {
                success: true,
                data:    Some(serde_json::json!({ "status": "Deferred" })),
                error:   None,
            }),
        ),
        Ok(_) => (
            StatusCode::NOT_FOUND,
            Json(ApiResponse::<serde_json::Value> {
                success: false,
                data:    None,
                error:   Some("No pending review item found for that candidate".into()),
            }),
        ),
        Err(err) => {
            tracing::error!(error=?err, "defer match failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<serde_json::Value> {
                    success: false,
                    data:    None,
                    error:   Some(err.to_string()),
                }),
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Assign a review-queue item to a data steward
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct AssignReviewBody {
    pub steward_id: Uuid,
}

/// PATCH /match/review-queue/:review_id/assign
/// Assigns a specific queue item to a data steward.
pub async fn assign_review(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Path(review_id):       Path<Uuid>,
    Json(body):            Json<AssignReviewBody>,
) -> impl IntoResponse {
    let tenant_id = tenant_ctx.tenant_id;

    let result = sqlx::query(
        "UPDATE core_mdm.match_review_queue \
         SET assigned_to = $3 \
         WHERE review_id = $1 \
           AND tenant_id = $2",
    )
    .bind(review_id)
    .bind(tenant_id)
    .bind(body.steward_id)
    .execute(&state.db)
    .await;

    match result {
        Ok(pg) if pg.rows_affected() > 0 => (
            StatusCode::OK,
            Json(ApiResponse {
                success: true,
                data:    Some(serde_json::json!({ "review_id": review_id, "assigned_to": body.steward_id })),
                error:   None,
            }),
        ),
        Ok(_) => (
            StatusCode::NOT_FOUND,
            Json(ApiResponse::<serde_json::Value> {
                success: false,
                data:    None,
                error:   Some("Review item not found for this tenant".into()),
            }),
        ),
        Err(err) => {
            tracing::error!(error=?err, "assign review failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<serde_json::Value> {
                    success: false,
                    data:    None,
                    error:   Some(err.to_string()),
                }),
            )
        }
    }
}
