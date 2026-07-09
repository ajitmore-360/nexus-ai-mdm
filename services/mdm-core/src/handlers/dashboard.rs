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

// â”€â”€ Serialisable response types â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

// â”€â”€ /dashboard/stats â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

    // Average AI confidence (0â€“1) scaled to 0â€“100
    let ai_match_score: f64 = sqlx::query_scalar(
        r#"SELECT COALESCE(AVG(ai_score) * 100.0, 0.0)::double precision
           FROM core_mdm.match_candidates
           WHERE tenant_id = $1 AND ai_score IS NOT NULL"#,
    )
    .bind(tid)
    .fetch_one(&state.db)
    .await
    .unwrap_or(0.0_f64);

    // Average trust score as overall data quality proxy (0â€“1 â†’ 0â€“100)
    let overall_data_quality: f64 = sqlx::query_scalar(
        r#"SELECT COALESCE(AVG(trust_score::double precision) * 100.0, 0.0)::double precision
           FROM core_mdm.entities
           WHERE tenant_id = $1 AND trust_score IS NOT NULL"#,
    )
    .bind(tid)
    .fetch_one(&state.db)
    .await
    .unwrap_or(0.0_f64);

    // 30-day growth rates: compare this-period vs prior-period entity/golden-record counts.
    let entities_this_period: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*) FROM core_mdm.entities
           WHERE tenant_id = $1 AND created_at >= CURRENT_DATE - INTERVAL '30 days'"#,
    )
    .bind(tid).fetch_one(&state.db).await.unwrap_or(0);

    let entities_prev_period: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*) FROM core_mdm.entities
           WHERE tenant_id = $1
             AND created_at >= CURRENT_DATE - INTERVAL '60 days'
             AND created_at <  CURRENT_DATE - INTERVAL '30 days'"#,
    )
    .bind(tid).fetch_one(&state.db).await.unwrap_or(0);

    let entity_growth_rate: f64 = if entities_prev_period == 0 {
        if entities_this_period > 0 { 100.0 } else { 0.0 }
    } else {
        ((entities_this_period - entities_prev_period) as f64
            / entities_prev_period as f64 * 1000.0)
            .round() / 10.0
    };

    let gr_this_period: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*) FROM core_mdm.golden_records
           WHERE tenant_id = $1 AND created_at >= CURRENT_DATE - INTERVAL '30 days'"#,
    )
    .bind(tid).fetch_one(&state.db).await.unwrap_or(0);

    let gr_prev_period: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*) FROM core_mdm.golden_records
           WHERE tenant_id = $1
             AND created_at >= CURRENT_DATE - INTERVAL '60 days'
             AND created_at <  CURRENT_DATE - INTERVAL '30 days'"#,
    )
    .bind(tid).fetch_one(&state.db).await.unwrap_or(0);

    let golden_record_growth_rate: f64 = if gr_prev_period == 0 {
        if gr_this_period > 0 { 100.0 } else { 0.0 }
    } else {
        ((gr_this_period - gr_prev_period) as f64
            / gr_prev_period as f64 * 1000.0)
            .round() / 10.0
    };

    let pending_prev: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*) FROM core_mdm.match_review_queue
           WHERE tenant_id = $1
             AND review_status = 'Pending'
             AND created_at < CURRENT_DATE - INTERVAL '7 days'"#,
    )
    .bind(tid).fetch_one(&state.db).await.unwrap_or(0);
    let pending_review_delta = pending_review - pending_prev;

    let ai_score_prev: f64 = sqlx::query_scalar(
        r#"SELECT COALESCE(AVG(ai_score) * 100.0, 0.0)::double precision
           FROM core_mdm.match_candidates
           WHERE tenant_id = $1
             AND ai_score IS NOT NULL
             AND created_at < CURRENT_DATE - INTERVAL '7 days'"#,
    )
    .bind(tid).fetch_one(&state.db).await.unwrap_or(0.0_f64);
    let ai_score_delta = ((ai_match_score - ai_score_prev) * 10.0).round() / 10.0;

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
        entity_growth_rate,
        golden_record_growth_rate,
        pending_review_delta,
        ai_score_delta,
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

// â”€â”€ /dashboard/activity â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
                .unwrap_or("Azile AI")
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

// â”€â”€ /dashboard/steward-performance â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

pub async fn get_steward_performance(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
) -> impl IntoResponse {
    let tid = tenant_ctx.tenant_id;

    // Per-reviewer stats: total reviews, approved count, avg minutes to review
    let rows = sqlx::query(
        r#"
        SELECT
            i.identity_id,
            COALESCE(i.display_name, i.email) AS display_name,
            i.email,
            COUNT(*)                                                               AS total_reviews,
            COUNT(*) FILTER (WHERE r.status = 'approved')                         AS approved_count,
            COUNT(*) FILTER (WHERE r.status = 'rejected')                         AS rejected_count,
            ROUND(
                EXTRACT(EPOCH FROM AVG(
                    r.reviewed_at - r.submitted_at
                )) / 60.0
            , 1)                                                                   AS avg_minutes
        FROM   core_mdm.entity_approval_requests r
        JOIN   core_mdm.identities                i ON i.identity_id = r.reviewed_by
        WHERE  r.tenant_id  = $1
          AND  r.reviewed_at IS NOT NULL
        GROUP  BY i.identity_id, i.display_name, i.email
        ORDER  BY total_reviews DESC
        LIMIT  10
        "#,
    )
    .bind(tid)
    .fetch_all(&state.db)
    .await
    .unwrap_or_default();

    let stewards: Vec<Value> = rows.iter().map(|r| {
        let total:    i64 = r.try_get("total_reviews").unwrap_or(0);
        let approved: i64 = r.try_get("approved_count").unwrap_or(0);
        let rejected: i64 = r.try_get("rejected_count").unwrap_or(0);
        let avg_min:  f64 = r.try_get::<Option<f64>, _>("avg_minutes")
                             .ok().flatten().unwrap_or(0.0);
        let approval_pct = if total > 0 {
            (approved as f64 / total as f64 * 1000.0).round() / 10.0
        } else {
            0.0
        };
        json!({
            "identity_id":   r.get::<uuid::Uuid, _>("identity_id"),
            "display_name":  r.get::<String, _>("display_name"),
            "email":         r.get::<String, _>("email"),
            "total_reviews": total,
            "approved_count": approved,
            "rejected_count": rejected,
            "approval_pct":  approval_pct,
            "avg_review_min": avg_min,
        })
    }).collect();

    (
        StatusCode::OK,
        Json(json!({ "success": true, "stewards": stewards })),
    )
}

// â”€â”€ /dashboard/quality-dimensions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//
// Computes per-dimension data quality scores from live entity data.
// Returns scores in the range [0, 1] for each of the 6 standard dimensions.

pub async fn get_quality_dimensions(
    State(state):          State<Arc<AppState>>,
    Extension(tenant_ctx): Extension<TenantContext>,
) -> impl IntoResponse {
    let tid = tenant_ctx.tenant_id;

    // Completeness: fraction of entities that have a trust_score set
    let completeness: f64 = sqlx::query_scalar(
        r#"SELECT ROUND(
               CAST(COUNT(*) FILTER (WHERE trust_score IS NOT NULL) AS DOUBLE PRECISION)
               / NULLIF(COUNT(*), 0)
           , 4)::double precision
           FROM core_mdm.entities WHERE tenant_id = $1 AND is_deleted IS NOT TRUE"#,
    )
    .bind(tid).fetch_one(&state.db).await.unwrap_or(0.0_f64);

    // Uniqueness: fraction of entities NOT involved in a duplicate match
    let uniqueness: f64 = sqlx::query_scalar(
        r#"SELECT ROUND(
               1.0 - CAST(
                   COUNT(DISTINCT entity_id_a) + COUNT(DISTINCT entity_id_b)
               AS DOUBLE PRECISION)
               / NULLIF((
                   SELECT COUNT(*) FROM core_mdm.entities
                   WHERE tenant_id = $1 AND is_deleted IS NOT TRUE
               ) * 2.0, 0)
           , 4)::double precision
           FROM core_mdm.match_candidates
           WHERE tenant_id = $1
             AND match_status NOT IN ('Rejected', 'AutoMerged')"#,
    )
    .bind(tid).bind(tid).fetch_one(&state.db).await.unwrap_or(1.0_f64);

    // Timeliness: fraction of entities updated within the last 90 days
    let timeliness: f64 = sqlx::query_scalar(
        r#"SELECT ROUND(
               CAST(COUNT(*) FILTER (WHERE updated_at >= NOW() - INTERVAL '90 days') AS DOUBLE PRECISION)
               / NULLIF(COUNT(*), 0)
           , 4)::double precision
           FROM core_mdm.entities WHERE tenant_id = $1 AND is_deleted IS NOT TRUE"#,
    )
    .bind(tid).fetch_one(&state.db).await.unwrap_or(0.0_f64);

    // Accuracy: avg AI confidence across match candidates (proxy for accuracy)
    let accuracy: f64 = sqlx::query_scalar(
        r#"SELECT COALESCE(
               ROUND(AVG(ai_score)::double precision, 4), 0.0
           )::double precision
           FROM core_mdm.match_candidates
           WHERE tenant_id = $1 AND ai_score IS NOT NULL"#,
    )
    .bind(tid).fetch_one(&state.db).await.unwrap_or(0.0_f64);

    // Consistency: fraction of entities in golden records vs total active entities
    let consistency: f64 = {
        let golden_count: i64 = sqlx::query_scalar(
            "SELECT COUNT(DISTINCT entity_id) FROM core_mdm.match_candidates WHERE tenant_id=$1 AND match_status='AutoMerged'"
        )
        .bind(tid).fetch_one(&state.db).await.unwrap_or(0i64);
        let total: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM core_mdm.entities WHERE tenant_id=$1 AND is_deleted IS NOT TRUE"
        )
        .bind(tid).fetch_one(&state.db).await.unwrap_or(0i64);
        if total == 0 { 0.9 } else {
            let base = golden_count as f64 / total as f64;
            // Invert: fewer duplicates = higher consistency
            (1.0 - base).max(0.0).min(1.0)
        }
    };

    // Validity: fraction of entities with valid source_system set
    let validity: f64 = sqlx::query_scalar(
        r#"SELECT ROUND(
               CAST(COUNT(*) FILTER (WHERE source_system IS NOT NULL AND source_system != '') AS DOUBLE PRECISION)
               / NULLIF(COUNT(*), 0)
           , 4)::double precision
           FROM core_mdm.entities WHERE tenant_id = $1 AND is_deleted IS NOT TRUE"#,
    )
    .bind(tid).fetch_one(&state.db).await.unwrap_or(0.0_f64);

    let clamp = |v: f64| -> f64 { (v * 10000.0).round() / 10000.0 };

    (
        StatusCode::OK,
        Json(json!({
            "success": true,
            "dimensions": {
                "completeness": clamp(completeness),
                "accuracy":     clamp(accuracy),
                "consistency":  clamp(consistency),
                "uniqueness":   clamp(uniqueness.max(0.0).min(1.0)),
                "timeliness":   clamp(timeliness),
                "validity":     clamp(validity),
            }
        })),
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
