use std::sync::Arc;

use axum::{
    extract::State,
    http::StatusCode,
    response::IntoResponse,
    Extension, Json,
};
use serde::Serialize;
use serde_json::{json, Value};
use sqlx::Row;

use crate::{
    handlers::ApiResponse,
    middleware::tenant::TenantContext,
    AppState,
};

// ── Serialisable response types ───────────────────────────────────────────────

#[derive(Debug, Serialize)]
pub struct DashboardStats {
    total_entities:            i64,
    total_golden_records:      i64,
    pending_review:            i64,
    ai_match_score:            f64,
    entity_growth_rate:        f64,
    golden_record_growth_rate: f64,
    pending_review_delta:      i64,
    ai_score_delta:            f64,
    match_activity:            Vec<MatchActivityPoint>,
    top_duplicate_sources:     Vec<DuplicateSourcePoint>,
    merged_today:              i64,
    new_entities_today:        i64,
    overall_data_quality:      f64,
}

#[derive(Debug, Serialize)]
pub struct MatchActivityPoint {
    date:          String,
    auto_merged:   i64,
    manual_merged: i64,
    rejected:      i64,
    pending:       i64,
}

#[derive(Debug, Serialize)]
pub struct DuplicateSourcePoint {
    source:     String,
    count:      i64,
    percentage: f64,
}

// ── /dashboard/stats ──────────────────────────────────────────────────────────

pub async fn get_dashboard_stats(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
) -> impl IntoResponse {
    let tid = tenant_ctx.tenant_id;

    let total_entities: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM core_mdm.entities WHERE tenant_id = $1",
    )
    .bind(tid)
    .fetch_one(&state.db)
    .await
    .unwrap_or(0);

    let total_golden_records: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM core_mdm.golden_records WHERE tenant_id = $1",
    )
    .bind(tid)
    .fetch_one(&state.db)
    .await
    .unwrap_or(0);

    let pending_review: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*) FROM core_mdm.match_review_queue
           WHERE tenant_id = $1 AND review_status = 'Pending'"#,
    )
    .bind(tid)
    .fetch_one(&state.db)
    .await
    .unwrap_or(0);

    let new_entities_today: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*) FROM core_mdm.entities
           WHERE tenant_id = $1 AND created_at >= CURRENT_DATE"#,
    )
    .bind(tid)
    .fetch_one(&state.db)
    .await
    .unwrap_or(0);

    let merged_today: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*) FROM core_mdm.match_candidates
           WHERE tenant_id = $1
             AND match_status = 'AutoMerged'
             AND updated_at >= CURRENT_DATE"#,
    )
    .bind(tid)
    .fetch_one(&state.db)
    .await
    .unwrap_or(0);

    // Average AI confidence (0–1) scaled to 0–100
    let ai_match_score: f64 = sqlx::query_scalar(
        r#"SELECT COALESCE(AVG(ai_score) * 100.0, 0.0)::double precision
           FROM core_mdm.match_candidates
           WHERE tenant_id = $1 AND ai_score IS NOT NULL"#,
    )
    .bind(tid)
    .fetch_one(&state.db)
    .await
    .unwrap_or(0.0_f64);

    // Average trust score as overall data quality proxy (0–1 → 0–100)
    let overall_data_quality: f64 = sqlx::query_scalar(
        r#"SELECT COALESCE(AVG(trust_score::double precision) * 100.0, 0.0)::double precision
           FROM core_mdm.entities
           WHERE tenant_id = $1 AND trust_score IS NOT NULL"#,
    )
    .bind(tid)
    .fetch_one(&state.db)
    .await
    .unwrap_or(0.0_f64);

    // 14-day daily match activity breakdown
    let activity_rows = sqlx::query(
        r#"
        SELECT
            DATE(created_at)                                                         AS day,
            COUNT(*) FILTER (WHERE match_status = 'AutoMerged')                     AS auto_merged,
            COUNT(*) FILTER (WHERE match_status = 'Matched' AND NOT auto_approved)  AS manual_merged,
            COUNT(*) FILTER (WHERE match_status = 'Rejected')                       AS rejected,
            COUNT(*) FILTER (WHERE match_status IN ('Pending','RequiresReview'))     AS pending
        FROM core_mdm.match_candidates
        WHERE tenant_id = $1
          AND created_at >= CURRENT_DATE - INTERVAL '14 days'
        GROUP BY DATE(created_at)
        ORDER BY day
        "#,
    )
    .bind(tid)
    .fetch_all(&state.db)
    .await
    .unwrap_or_default();

    let match_activity: Vec<MatchActivityPoint> = activity_rows
        .iter()
        .map(|r| MatchActivityPoint {
            date:          r.get::<chrono::NaiveDate, _>("day").to_string(),
            auto_merged:   r.get::<i64, _>("auto_merged"),
            manual_merged: r.get::<i64, _>("manual_merged"),
            rejected:      r.get::<i64, _>("rejected"),
            pending:       r.get::<i64, _>("pending"),
        })
        .collect();

    // Top 5 source systems by entity count
    let source_rows = sqlx::query(
        r#"
        SELECT
            COALESCE(source_system, 'Unknown') AS source,
            COUNT(*)                           AS cnt
        FROM core_mdm.entities
        WHERE tenant_id = $1
        GROUP BY source
        ORDER BY cnt DESC
        LIMIT 5
        "#,
    )
    .bind(tid)
    .fetch_all(&state.db)
    .await
    .unwrap_or_default();

    let source_total: i64 = source_rows
        .iter()
        .map(|r| r.get::<i64, _>("cnt"))
        .sum::<i64>()
        .max(1);

    let top_duplicate_sources: Vec<DuplicateSourcePoint> = source_rows
        .iter()
        .map(|r| {
            let cnt = r.get::<i64, _>("cnt");
            DuplicateSourcePoint {
                source:     r.get::<String, _>("source"),
                count:      cnt,
                percentage: (cnt as f64 / source_total as f64 * 1000.0).round() / 1000.0,
            }
        })
        .collect();

    let stats = DashboardStats {
        total_entities,
        total_golden_records,
        pending_review,
        ai_match_score:            (ai_match_score * 10.0).round() / 10.0,
        entity_growth_rate:        0.0,
        golden_record_growth_rate: 0.0,
        pending_review_delta:      0,
        ai_score_delta:            0.0,
        match_activity,
        top_duplicate_sources,
        merged_today,
        new_entities_today,
        overall_data_quality:      (overall_data_quality * 10.0).round() / 10.0,
    };

    (
        StatusCode::OK,
        Json(ApiResponse {
            success: true,
            data:    Some(stats),
            error:   None,
        }),
    )
}

// ── /dashboard/activity ───────────────────────────────────────────────────────

pub async fn get_activity_feed(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
) -> impl IntoResponse {
    let tid = tenant_ctx.tenant_id;

    let rows = sqlx::query(
        r#"
        SELECT
            event_id,
            event_type,
            aggregate_type,
            aggregate_id,
            event_payload,
            event_timestamp
        FROM event_store.outbox_events
        WHERE tenant_id = $1
        ORDER BY event_timestamp DESC
        LIMIT 20
        "#,
    )
    .bind(tid)
    .fetch_all(&state.db)
    .await
    .unwrap_or_default();

    let items: Vec<Value> = rows
        .iter()
        .map(|r| {
            let event_id:   String = r.get::<uuid::Uuid, _>("event_id").to_string();
            let event_type: String = r.get("event_type");
            let agg_type:   String = r.get("aggregate_type");
            let agg_id:     String = r.get::<uuid::Uuid, _>("aggregate_id").to_string();
            let payload:    Value  =
                r.get::<sqlx::types::Json<Value>, _>("event_payload").0;
            let ts: chrono::DateTime<chrono::Utc> = r.get("event_timestamp");

            let (activity_type, title, description) =
                map_event_type(&event_type, &agg_type, &payload);

            let entity_name = payload
                .get("display_name")
                .or_else(|| payload.get("name"))
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_owned();

            let source_system = payload
                .get("source_system")
                .and_then(|v| v.as_str())
                .unwrap_or("Nexus AI")
                .to_owned();

            json!({
                "id":            event_id,
                "type":          activity_type,
                "title":         title,
                "description":   description,
                "entity_id":     agg_id,
                "entity_name":   entity_name,
                "user_id":       null,
                "user_name":     "System",
                "source_system": source_system,
                "timestamp":     ts.to_rfc3339(),
                "metadata":      {},
                "is_read":       false,
            })
        })
        .collect();

    (
        StatusCode::OK,
        Json(json!({ "items": items, "total": items.len() })),
    )
}

fn map_event_type(
    event_type: &str,
    agg_type:   &str,
    _payload:   &Value,
) -> (String, String, String) {
    match event_type {
        "EntityCreated" => (
            "entityCreated".into(),
            "Entity Created".into(),
            format!("New {} entity registered in the MDM system", agg_type),
        ),
        "EntityUpdated" => (
            "entityUpdated".into(),
            "Entity Updated".into(),
            format!("{} entity attributes updated", agg_type),
        ),
        "EntityMerged" | "MergeExecuted" => (
            "entityMerged".into(),
            "Entities Merged".into(),
            "Duplicate records merged into a single golden record".into(),
        ),
        "MatchFound" | "MatchCandidateCreated" => (
            "matchFound".into(),
            "Match Detected".into(),
            "High confidence match found by the AI matching engine".into(),
        ),
        "MatchReviewed" | "MatchApproved" | "MatchRejected" => (
            "matchReviewed".into(),
            "Match Reviewed".into(),
            "Match candidate reviewed by a data steward".into(),
        ),
        "GoldenRecordCreated" => (
            "goldenRecordCreated".into(),
            "Golden Record Created".into(),
            format!("{} entity elevated to golden record status", agg_type),
        ),
        "GoldenRecordUpdated" => (
            "goldenRecordUpdated".into(),
            "Golden Record Updated".into(),
            "Golden record survivorship attributes recalculated".into(),
        ),
        _ => (
            "userAction".into(),
            "System Event".into(),
            format!("{} event processed by Nexus AI MDM", event_type),
        ),
    }
}
