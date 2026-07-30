use std::collections::HashMap;
use std::sync::Arc;

use axum::{
    extract::{Path, Query, State},
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    Extension, Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::handlers::{entities::extract_request_context, ApiResponse};
use crate::middleware::tenant::TenantContext;
use crate::services::audit_service::AuditEvent;
use crate::AppState;

#[derive(Deserialize)]
pub struct ReviewQueueParams {
    pub limit:     Option<i64>,
    pub offset:    Option<i64>,
    // Flutter sends page/page_size — support both conventions
    pub page:      Option<i64>,
    pub page_size: Option<i64>,
    pub entity_type: Option<String>,
}

#[derive(Deserialize)]
pub struct ReviewDecisionBody {
    pub notes: Option<String>,
}

/// GET /match/review-queue?limit=&offset=
/// Returns all match candidates that require human review with enriched entity names.
pub async fn get_review_queue(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
    Query(params):         Query<ReviewQueueParams>,
) -> impl IntoResponse {
    let page_size = params.page_size.or(params.limit).unwrap_or(20).clamp(1, 100);
    let page      = params.page.unwrap_or(1).max(1);
    let limit     = page_size;
    let offset    = params.offset.unwrap_or_else(|| (page - 1) * page_size).max(0);
    let tenant_id = tenant_ctx.tenant_id;

    // Optional entity_type scope (steward clients pass this)
    let entity_type_filter = params.entity_type
        .as_deref()
        .map(|s| s.trim().to_lowercase())
        .filter(|s| !s.is_empty());

    let rows = match sqlx::query(
        r#"
        SELECT
            mc.match_candidate_id                               AS review_id,
            mc.request_id,
            mc.match_candidate_id                               AS candidate_id,
            mc.source_entity_id,
            mc.matched_entity_id                                AS candidate_entity_id,
            COALESCE(
                NULLIF(src_e.current_attributes->>'legal_name', ''),
                NULLIF(src_e.current_attributes->>'name', ''),
                NULLIF(src_e.current_attributes->>'company_name', ''),
                NULLIF(src_e.current_attributes->>'full_name', ''),
                NULLIF(src_e.current_attributes->>'display_name', ''),
                mc.source_entity_id::text
            )                                                   AS source_entity_name,
            COALESCE(
                NULLIF(tgt_e.current_attributes->>'legal_name', ''),
                NULLIF(tgt_e.current_attributes->>'name', ''),
                NULLIF(tgt_e.current_attributes->>'company_name', ''),
                NULLIF(tgt_e.current_attributes->>'full_name', ''),
                NULLIF(tgt_e.current_attributes->>'display_name', ''),
                mc.matched_entity_id::text
            )                                                   AS target_entity_name,
            mc.match_score,
            mc.confidence_score,
            mc.match_status,
            mc.recommended_for_merge,
            mc.requires_human_review,
            mc.explanations,
            COALESCE(src_e.entity_type, '')                     AS entity_type,
            mc.created_at,
            fm.field_name,
            fm.source_value    #>> '{}'                         AS source_value,
            fm.candidate_value #>> '{}'                         AS target_value,
            fm.score                                            AS fm_score
        FROM (
            SELECT
                match_candidate_id,
                request_id,
                source_entity_id,
                matched_entity_id,
                match_score,
                confidence_score,
                match_status,
                recommended_for_merge,
                requires_human_review,
                explanations,
                created_at
            FROM core_mdm.match_candidates
            WHERE tenant_id = $1
              AND requires_human_review = TRUE
            ORDER BY match_score DESC
            LIMIT $2 OFFSET $3
        ) mc
        LEFT JOIN core_mdm.entities src_e
            ON  src_e.entity_id = mc.source_entity_id
            AND src_e.tenant_id = $1
            AND src_e.valid_to  = 'infinity'
        LEFT JOIN core_mdm.entities tgt_e
            ON  tgt_e.entity_id = mc.matched_entity_id
            AND tgt_e.tenant_id = $1
            AND tgt_e.valid_to  = 'infinity'
        LEFT JOIN core_mdm.field_match_results fm
            ON  fm.tenant_id         = $1
            AND fm.request_id        = mc.request_id
            AND fm.matched_entity_id = mc.matched_entity_id
        WHERE ($4::text IS NULL OR LOWER(COALESCE(src_e.entity_type, '')) = $4)
        ORDER BY mc.match_score DESC, fm.created_at ASC NULLS LAST
        "#,
    )
    .bind(tenant_id)
    .bind(limit)
    .bind(offset)
    .bind(entity_type_filter)
    .fetch_all(&state.db)
    .await
    {
        Ok(r) => r,
        Err(e) => {
            tracing::error!(error=?e, "review queue fetch failed");
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<serde_json::Value> {
                    success: false,
                    data:    None,
                    error:   Some(e.to_string()),
                }),
            ).into_response();
        }
    };

    // Group rows by review_id (match_candidate_id), collecting field matches per candidate.
    let mut order:      Vec<Uuid>                    = Vec::new();
    let mut header_idx: HashMap<Uuid, usize>         = HashMap::new();
    let mut field_map:  HashMap<Uuid, Vec<serde_json::Value>> = HashMap::new();

    for (i, row) in rows.iter().enumerate() {
        let review_id: Uuid = row.try_get("review_id").unwrap_or_default();
        if let std::collections::hash_map::Entry::Vacant(e) = header_idx.entry(review_id) {
            order.push(review_id);
            e.insert(i);
        }
        let field_name: Option<String> = row.try_get("field_name").ok().flatten();
        if let Some(fname) = field_name {
            let src_val:  String = row.try_get::<Option<String>, _>("source_value").ok().flatten().unwrap_or_default();
            let tgt_val:  String = row.try_get::<Option<String>, _>("target_value").ok().flatten().unwrap_or_default();
            let fm_score: f32    = row.try_get::<Option<f32>, _>("fm_score").ok().flatten().unwrap_or(0.0);
            field_map.entry(review_id).or_default().push(serde_json::json!({
                "field":        fname,
                "field_name":   fname,
                "source_value": src_val,
                "target_value": tgt_val,
                "score":        fm_score,
            }));
        }
    }

    let mut items: Vec<serde_json::Value> = Vec::with_capacity(order.len());
    for review_id in &order {
        let row               = &rows[header_idx[review_id]];
        let request_id: Uuid       = row.try_get("request_id").unwrap_or_default();
        let candidate_id: Uuid     = row.try_get("candidate_id").unwrap_or_default();
        let source_entity_id: Uuid = row.try_get("source_entity_id").unwrap_or_default();
        let cand_entity_id: Uuid   = row.try_get("candidate_entity_id").unwrap_or_default();
        let src_name:  String      = row.try_get("source_entity_name").unwrap_or_default();
        let tgt_name:  String      = row.try_get("target_entity_name").unwrap_or_default();
        let score: f32             = row.try_get::<f32, _>("match_score").unwrap_or(0.0);
        let entity_type: String    = row.try_get("entity_type").unwrap_or_default();
        let created_at: chrono::DateTime<chrono::Utc> =
            row.try_get("created_at").unwrap_or_else(|_| chrono::Utc::now());
        let status: String = row.try_get("match_status").unwrap_or_default();
        let explanations: sqlx::types::Json<Vec<String>> =
            row.try_get("explanations").unwrap_or_else(|_| sqlx::types::Json(vec![]));
        let ai_explanation    = explanations.0.first().cloned();
        let field_matches     = field_map.get(review_id).cloned().unwrap_or_default();

        let priority = if score >= 0.95_f32 { "critical" }
            else if score >= 0.85_f32 { "high" }
            else { "normal" };

        items.push(serde_json::json!({
            // Fields for ReviewItem (match_queue_repository.dart)
            "review_id":           review_id,
            "request_id":          request_id,
            "candidate_id":        candidate_id,
            "source_entity_name":  src_name,
            "target_entity_name":  tgt_name,
            "overall_score":       score,
            "priority":            priority,
            "entity_type":         entity_type,
            "created_at":          created_at.to_rfc3339(),
            "ai_explanation":      ai_explanation,
            "field_matches":       field_matches,
            // Fields for ReviewQueueItem (match_repository.dart)
            "source_entity_id":    source_entity_id,
            "candidate_entity_id": cand_entity_id,
            "score":               score,
            "status":              status,
            "ai_confidence":       score,
        }));
    }

    (
        StatusCode::OK,
        Json(ApiResponse {
            success: true,
            data:    Some(serde_json::json!({
                "items":  items,
                "limit":  limit,
                "offset": offset,
            })),
            error:   None,
        }),
    ).into_response()
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
    let ctx      = extract_request_context(&tenant_ctx, &headers);
    let notes    = body.and_then(|b| b.notes.clone());
    let actor_id = headers.get("x-user-id")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| Uuid::parse_str(s).ok());

    match state.review_service.approve(ctx, request_id, candidate_id, notes.clone()).await {
        Ok(()) => {
            state.audit_service.log_background(AuditEvent {
                tenant_id:     tenant_ctx.tenant_id,
                event_type:    "match.approved".to_string(),
                actor_id,
                resource_type: "match_candidate".to_string(),
                resource_id:   candidate_id.to_string(),
                metadata:      serde_json::json!({
                    "request_id":   request_id,
                    "candidate_id": candidate_id,
                    "notes":        notes,
                }),
                before: None,
                after:  None,
            });
            if let Some(pubsub) = &state.pubsub {
                let pubsub = std::sync::Arc::clone(pubsub);
                let tid    = tenant_ctx.tenant_id.to_string();
                tokio::spawn(async move {
                    let _ = pubsub.publish_to_tenant(&tid, &serde_json::json!({
                        "type":         "match.approved",
                        "candidate_id": candidate_id,
                        "request_id":   request_id,
                    })).await;
                });
            }
            (
                StatusCode::OK,
                Json(ApiResponse::<serde_json::Value> {
                    success: true,
                    data:    Some(serde_json::json!({ "request_id": request_id, "candidate_id": candidate_id, "status": "Matched" })),
                    error:   None,
                }),
            )
        },
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
    let ctx      = extract_request_context(&tenant_ctx, &headers);
    let notes    = body.and_then(|b| b.notes.clone());
    let actor_id = headers.get("x-user-id")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| Uuid::parse_str(s).ok());

    match state.review_service.reject(ctx, request_id, candidate_id, notes.clone()).await {
        Ok(()) => {
            state.audit_service.log_background(AuditEvent {
                tenant_id:     tenant_ctx.tenant_id,
                event_type:    "match.rejected".to_string(),
                actor_id,
                resource_type: "match_candidate".to_string(),
                resource_id:   candidate_id.to_string(),
                metadata:      serde_json::json!({
                    "request_id":   request_id,
                    "candidate_id": candidate_id,
                    "notes":        notes,
                }),
                before: None,
                after:  None,
            });
            if let Some(pubsub) = &state.pubsub {
                let pubsub = std::sync::Arc::clone(pubsub);
                let tid    = tenant_ctx.tenant_id.to_string();
                tokio::spawn(async move {
                    let _ = pubsub.publish_to_tenant(&tid, &serde_json::json!({
                        "type":         "match.rejected",
                        "candidate_id": candidate_id,
                        "request_id":   request_id,
                    })).await;
                });
            }
            (
                StatusCode::OK,
                Json(ApiResponse::<serde_json::Value> {
                    success: true,
                    data:    Some(serde_json::json!({ "request_id": request_id, "candidate_id": candidate_id, "status": "Rejected" })),
                    error:   None,
                }),
            )
        },
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
            state.audit_service.log_background(AuditEvent {
                tenant_id:     tenant_id,
                event_type:    "match.bulk_approved".to_string(),
                actor_id:      user_id,
                resource_type: "match_review_queue".to_string(),
                resource_id:   tenant_id.to_string(),
                metadata:      serde_json::json!({ "approved": approved, "failed": failed, "candidate_ids": body.candidate_ids }),
                before:        None,
                after:         None,
            });
            if let Some(pubsub) = &state.pubsub {
                let pubsub = std::sync::Arc::clone(pubsub);
                let tid    = tenant_id.to_string();
                tokio::spawn(async move {
                    let _ = pubsub.publish_to_tenant(&tid, &serde_json::json!({
                        "type":     "match.bulk_approved",
                        "approved": approved,
                    })).await;
                });
            }
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
            state.audit_service.log_background(AuditEvent {
                tenant_id:     tenant_id,
                event_type:    "match.bulk_rejected".to_string(),
                actor_id:      user_id,
                resource_type: "match_review_queue".to_string(),
                resource_id:   tenant_id.to_string(),
                metadata:      serde_json::json!({ "rejected": rejected, "failed": failed, "candidate_ids": body.candidate_ids }),
                before:        None,
                after:         None,
            });
            if let Some(pubsub) = &state.pubsub {
                let pubsub = std::sync::Arc::clone(pubsub);
                let tid    = tenant_id.to_string();
                tokio::spawn(async move {
                    let _ = pubsub.publish_to_tenant(&tid, &serde_json::json!({
                        "type":     "match.bulk_rejected",
                        "rejected": rejected,
                    })).await;
                });
            }
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
    #[allow(dead_code)]
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
