/// Generic passthrough routes for services that need no payload transformation.
///
/// Each handler extracts the raw JSON body and proxies it unchanged to the
/// appropriate upstream, forwarding the upstream HTTP status to the caller.
use axum::{
    extract::{Query, State},
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use serde_json::Value;

use crate::{proxy::mdm_proxy::{mdm_service_auth, proxy_mdm_post}, state::AppState};

// ── Helper ────────────────────────────────────────────────────────────────────

/// Forward a GET to an upstream service, optionally overriding the
/// Authorization header with a service-to-service token.
async fn forward_get(
    http:         &reqwest::Client,
    base_url:     &str,
    path:         &str,
    headers:      &HeaderMap,
) -> Response {
    forward_get_with_auth(http, base_url, path, headers, None).await
}

async fn forward_get_with_service_auth(
    http:     &reqwest::Client,
    base_url: &str,
    path:     &str,
    headers:  &HeaderMap,
) -> Response {
    forward_get_with_auth(http, base_url, path, headers, Some(mdm_service_auth())).await
}

async fn forward_get_with_auth(
    http:      &reqwest::Client,
    base_url:  &str,
    path:      &str,
    headers:   &HeaderMap,
    auth:      Option<String>,
) -> Response {
    let url = format!("{}{}", base_url.trim_end_matches('/'), path);
    let mut req = http.get(&url);

    // Apply service auth override first; client headers are added after.
    if let Some(ref token) = auth {
        req = req.header("authorization", token.as_str());
    }

    for (k, v) in headers.iter() {
        let key = k.as_str();
        if key == "authorization" && auth.is_some() {
            // Skip the client JWT — service token is already set.
            continue;
        }
        if let Ok(v) = v.to_str() {
            req = req.header(key, v);
        }
    }

    match req.send().await {
        Ok(resp) => {
            let status = resp.status();
            let body: Value = resp.json().await.unwrap_or(Value::Null);
            (status, Json(body)).into_response()
        }
        Err(e) => {
            tracing::error!(error=%e, url=%url, "upstream GET failed");
            (StatusCode::BAD_GATEWAY, Json(serde_json::json!({ "success": false, "error": "upstream unavailable" }))).into_response()
        }
    }
}

async fn forward_post(
    http:     &reqwest::Client,
    base_url: &str,
    path:     &str,
    headers:  &HeaderMap,
    body:     Value,
) -> Response {
    match proxy_mdm_post(http, base_url, path, headers, body).await {
        Ok((status, b)) => (status, Json(b)).into_response(),
        Err(e) => {
            tracing::error!(error=%e, "upstream POST failed");
            (StatusCode::BAD_GATEWAY, Json(serde_json::json!({ "success": false, "error": "upstream unavailable" }))).into_response()
        }
    }
}

async fn forward_patch(
    http:     &reqwest::Client,
    base_url: &str,
    path:     &str,
    headers:  &HeaderMap,
    body:     Value,
) -> Response {
    let url = format!(
        "{}/{}",
        base_url.trim_end_matches('/'),
        path.trim_start_matches('/')
    );
    let svc_auth = crate::proxy::mdm_proxy::mdm_service_auth();
    let mut req = http
        .patch(&url)
        .json(&body)
        .header("authorization", svc_auth.as_str());

    // Only forward validated context headers — never forward connection/encoding
    // headers from the browser, which would conflict with reqwest's own headers.
    for (name, value) in headers.iter() {
        let key = name.as_str();
        if matches!(key, "x-tenant-id" | "x-user-id" | "x-user-role" | "x-correlation-id") {
            if let Ok(v) = value.to_str() {
                req = req.header(key, v);
            }
        }
    }

    match req.send().await {
        Ok(resp) => {
            let status = resp.status();
            let body: Value = resp.json().await.unwrap_or(Value::Null);
            (status, Json(body)).into_response()
        }
        Err(e) => {
            tracing::error!(error=%e, url=%url, "upstream PATCH failed");
            (StatusCode::BAD_GATEWAY, Json(serde_json::json!({ "success": false, "error": "upstream unavailable" }))).into_response()
        }
    }
}

// ── Search routes ─────────────────────────────────────────────────────────────

pub async fn search(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Query(params): Query<Value>,
) -> Response {
    let mut map = params.as_object().cloned().unwrap_or_default();

    // Flutter UI sends `q=` while the search-service expects `query=`.
    if !map.contains_key("query") {
        if let Some(q) = map.remove("q") {
            map.insert("query".to_string(), q);
        }
    }

    // Inject tenant_id from the validated header when the caller omits it.
    if !map.contains_key("tenant_id") {
        if let Some(tid) = headers.get("x-tenant-id").and_then(|v| v.to_str().ok()) {
            map.insert("tenant_id".to_string(), serde_json::Value::String(tid.to_owned()));
        }
    }

    let qs: String = map.iter()
        .filter_map(|(k, v)| v.as_str().map(|s| format!("{}={}", k, s)))
        .collect::<Vec<_>>()
        .join("&");
    let path = if qs.is_empty() { "/search".to_string() } else { format!("/search?{}", qs) };
    forward_get(&state.services.http, &state.settings.search_service_url, &path, &headers).await
}

pub async fn autocomplete(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Query(params): Query<Value>,
) -> Response {
    let mut map = params.as_object().cloned().unwrap_or_default();

    // Inject tenant_id from header when caller omits it.
    if !map.contains_key("tenant_id") {
        if let Some(tid) = headers.get("x-tenant-id").and_then(|v| v.to_str().ok()) {
            map.insert("tenant_id".to_string(), serde_json::Value::String(tid.to_owned()));
        }
    }

    let qs: String = map.iter()
        .filter_map(|(k, v)| v.as_str().map(|s| format!("{}={}", k, s)))
        .collect::<Vec<_>>()
        .join("&");
    let path = format!("/search/autocomplete?{}", qs);
    forward_get(&state.services.http, &state.settings.search_service_url, &path, &headers).await
}

// ── Policy routes ─────────────────────────────────────────────────────────────

pub async fn evaluate_policy(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Json(body):   Json<Value>,
) -> Response {
    forward_post(&state.services.http, &state.settings.policy_service_url, "/policy/evaluate", &headers, body).await
}

pub async fn list_policy_rules(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Query(params): Query<Value>,
) -> Response {
    let qs: String = params.as_object()
        .map(|m| m.iter()
            .filter_map(|(k, v)| v.as_str().map(|s| format!("{}={}", k, s)))
            .collect::<Vec<_>>().join("&"))
        .unwrap_or_default();
    let path = format!("/policy/rules?{}", qs);
    forward_get(&state.services.http, &state.settings.policy_service_url, &path, &headers).await
}

pub async fn create_policy_rule(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Json(body):   Json<Value>,
) -> Response {
    forward_post(&state.services.http, &state.settings.policy_service_url, "/policy/rules", &headers, body).await
}

pub async fn gdpr_erasure(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Json(body):   Json<Value>,
) -> Response {
    forward_post(&state.services.http, &state.settings.policy_service_url, "/policy/gdpr/erasure", &headers, body).await
}

pub async fn gdpr_access(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Json(body):   Json<Value>,
) -> Response {
    forward_post(&state.services.http, &state.settings.policy_service_url, "/policy/gdpr/access", &headers, body).await
}

// ── Distribution routes ───────────────────────────────────────────────────────

pub async fn enqueue_distribution(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Json(body):   Json<Value>,
) -> Response {
    forward_post(&state.services.http, &state.settings.distribution_service_url, "/jobs", &headers, body).await
}

pub async fn list_distribution_jobs(
    State(state):  State<AppState>,
    headers:       HeaderMap,
    Query(params): Query<Value>,
) -> Response {
    let qs = params.as_object()
        .map(|m| m.iter()
            .filter_map(|(k, v)| v.as_str().map(|s| format!("{}={}", k, s)))
            .collect::<Vec<_>>().join("&"))
        .unwrap_or_default();
    let path = if qs.is_empty() { "/jobs".to_string() } else { format!("/jobs?{}", qs) };
    forward_get(&state.services.http, &state.settings.distribution_service_url, &path, &headers).await
}

pub async fn get_distribution_job(
    State(state):                      State<AppState>,
    headers:                           HeaderMap,
    axum::extract::Path(job_id):       axum::extract::Path<String>,
    Query(params):                     Query<Value>,
) -> Response {
    let qs = params.as_object()
        .map(|m| m.iter()
            .filter_map(|(k, v)| v.as_str().map(|s| format!("{}={}", k, s)))
            .collect::<Vec<_>>().join("&"))
        .unwrap_or_default();
    let path = if qs.is_empty() {
        format!("/jobs/{}", job_id)
    } else {
        format!("/jobs/{}?{}", job_id, qs)
    };
    forward_get(&state.services.http, &state.settings.distribution_service_url, &path, &headers).await
}

// ── Match review queue routes ─────────────────────────────────────────────────

pub async fn get_match_review_queue(
    State(state):  State<AppState>,
    headers:       HeaderMap,
    Query(params): Query<Value>,
) -> Response {
    let qs = params.as_object()
        .map(|m| m.iter()
            .filter_map(|(k, v)| v.as_str().map(|s| format!("{}={}", k, s)))
            .collect::<Vec<_>>().join("&"))
        .unwrap_or_default();
    let path = if qs.is_empty() {
        "/match/review-queue".to_string()
    } else {
        format!("/match/review-queue?{}", qs)
    };
    forward_get_with_service_auth(&state.services.http, &state.settings.mdm_core_url, &path, &headers).await
}

pub async fn approve_match_candidate(
    State(state):  State<AppState>,
    headers:       HeaderMap,
    axum::extract::Path((request_id, candidate_id)): axum::extract::Path<(String, String)>,
    body:          Option<Json<Value>>,
) -> Response {
    let path = format!("/match/{}/candidates/{}/approve", request_id, candidate_id);
    let body = body.map(|b| b.0).unwrap_or(Value::Null);
    forward_post(&state.services.http, &state.settings.mdm_core_url, &path, &headers, body).await
}

pub async fn reject_match_candidate(
    State(state):  State<AppState>,
    headers:       HeaderMap,
    axum::extract::Path((request_id, candidate_id)): axum::extract::Path<(String, String)>,
    body:          Option<Json<Value>>,
) -> Response {
    let path = format!("/match/{}/candidates/{}/reject", request_id, candidate_id);
    let body = body.map(|b| b.0).unwrap_or(Value::Null);
    forward_post(&state.services.http, &state.settings.mdm_core_url, &path, &headers, body).await
}

// ── Policy weights (expose mdm-core internal route via gateway) ───────────────

pub async fn get_policy_weights(
    State(state): State<AppState>,
    headers:      HeaderMap,
) -> Response {
    forward_get_with_service_auth(&state.services.http, &state.settings.mdm_core_url, "/policy/weights", &headers).await
}

pub async fn update_policy_weights(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Json(body):   Json<Value>,
) -> Response {
    forward_patch(&state.services.http, &state.settings.mdm_core_url, "/policy/weights", &headers, body).await
}

// ── Ingest routes ─────────────────────────────────────────────────────────────

pub async fn ingest_batch(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Json(body):   Json<Value>,
) -> Response {
    forward_post(&state.services.http, &state.settings.ingest_service_url, "/ingest/batch", &headers, body).await
}

pub async fn ingest_entities(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Json(body):   Json<Value>,
) -> Response {
    forward_post(&state.services.http, &state.settings.ingest_service_url, "/ingest/entities", &headers, body).await
}

pub async fn ingest_csv(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Json(body):   Json<Value>,
) -> Response {
    forward_post(&state.services.http, &state.settings.ingest_service_url, "/ingest/csv", &headers, body).await
}

// ── Entity routes (proxied to mdm-core with service auth) ────────────────────

pub async fn list_entities(
    State(state):   State<AppState>,
    headers:        HeaderMap,
    Query(params):  Query<Value>,
) -> Response {
    let qs: String = params
        .as_object()
        .map(|m| {
            m.iter()
                .filter_map(|(k, v)| v.as_str().map(|s| format!("{}={}", k, s)))
                .collect::<Vec<_>>()
                .join("&")
        })
        .unwrap_or_default();
    let path = if qs.is_empty() {
        "/entities".to_string()
    } else {
        format!("/entities?{}", qs)
    };
    forward_get_with_service_auth(&state.services.http, &state.settings.mdm_core_url, &path, &headers).await
}

pub async fn get_entity_by_id(
    State(state):         State<AppState>,
    headers:              HeaderMap,
    axum::extract::Path(entity_id): axum::extract::Path<String>,
) -> Response {
    let path = format!("/entities/{}", entity_id);
    forward_get_with_service_auth(&state.services.http, &state.settings.mdm_core_url, &path, &headers).await
}

pub async fn patch_entity(
    State(state):         State<AppState>,
    headers:              HeaderMap,
    axum::extract::Path(entity_id): axum::extract::Path<String>,
    Json(body):           Json<Value>,
) -> Response {
    let path = format!("/entities/{}", entity_id);
    forward_patch(&state.services.http, &state.settings.mdm_core_url, &path, &headers, body).await
}

// ── Dashboard routes (aggregated from mdm-core) ───────────────────────────────

pub async fn dashboard_stats(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Query(params): Query<Value>,
) -> Response {
    let qs: String = params.as_object()
        .map(|m| m.iter()
            .filter_map(|(k, v)| v.as_str().map(|s| format!("{}={}", k, s)))
            .collect::<Vec<_>>().join("&"))
        .unwrap_or_default();
    let path = if qs.is_empty() {
        "/dashboard/stats".to_string()
    } else {
        format!("/dashboard/stats?{}", qs)
    };
    forward_get_with_service_auth(&state.services.http, &state.settings.mdm_core_url, &path, &headers).await
}

pub async fn dashboard_activity(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Query(params): Query<Value>,
) -> Response {
    let qs: String = params.as_object()
        .map(|m| m.iter()
            .filter_map(|(k, v)| v.as_str().map(|s| format!("{}={}", k, s)))
            .collect::<Vec<_>>().join("&"))
        .unwrap_or_default();
    let path = if qs.is_empty() {
        "/dashboard/activity".to_string()
    } else {
        format!("/dashboard/activity?{}", qs)
    };
    forward_get_with_service_auth(&state.services.http, &state.settings.mdm_core_url, &path, &headers).await
}

// ── Consent routes ────────────────────────────────────────────────────────────

pub async fn record_consent(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Json(body):   Json<Value>,
) -> Response {
    forward_post(&state.services.http, &state.settings.policy_service_url, "/policy/consent", &headers, body).await
}

pub async fn list_consent(
    State(state):  State<AppState>,
    headers:       HeaderMap,
    Query(params): Query<Value>,
) -> Response {
    let qs: String = params.as_object()
        .map(|m| m.iter()
            .filter_map(|(k, v)| v.as_str().map(|s| format!("{}={}", k, s)))
            .collect::<Vec<_>>().join("&"))
        .unwrap_or_default();
    let path = if qs.is_empty() {
        "/policy/consent".to_string()
    } else {
        format!("/policy/consent?{}", qs)
    };
    forward_get(&state.services.http, &state.settings.policy_service_url, &path, &headers).await
}

pub async fn withdraw_consent(
    State(state):         State<AppState>,
    headers:              HeaderMap,
    axum::extract::Path(consent_id): axum::extract::Path<String>,
    Query(params):        Query<Value>,
) -> Response {
    let qs: String = params.as_object()
        .map(|m| m.iter()
            .filter_map(|(k, v)| v.as_str().map(|s| format!("{}={}", k, s)))
            .collect::<Vec<_>>().join("&"))
        .unwrap_or_default();
    let path = format!("/policy/consent/{}/withdraw?{}", consent_id, qs);
    forward_post(&state.services.http, &state.settings.policy_service_url, &path, &headers, Value::Null).await
}

// ── Lineage routes ────────────────────────────────────────────────────────────

pub async fn get_entity_lineage(
    State(state):         State<AppState>,
    headers:              HeaderMap,
    axum::extract::Path(entity_id): axum::extract::Path<String>,
    Query(params):        Query<Value>,
) -> Response {
    let qs: String = params.as_object()
        .map(|m| m.iter()
            .filter_map(|(k, v)| v.as_str().map(|s| format!("{}={}", k, s)))
            .collect::<Vec<_>>().join("&"))
        .unwrap_or_default();
    let path = format!("/entities/{}/lineage?{}", entity_id, qs);
    forward_get_with_service_auth(&state.services.http, &state.settings.mdm_core_url, &path, &headers).await
}

// ── Merge routes ─────────────────────────────────────────────────────────────

pub async fn execute_merge(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Json(body):   Json<Value>,
) -> Response {
    forward_post(&state.services.http, &state.settings.mdm_core_url, "/merge", &headers, body).await
}

// ── AI service routes ─────────────────────────────────────────────────────────

pub async fn recommend_weights(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Query(params): Query<Value>,
) -> Response {
    let qs: String = params.as_object()
        .map(|m| m.iter()
            .filter_map(|(k, v)| v.as_str().map(|s| format!("{}={}", k, s)))
            .collect::<Vec<_>>().join("&"))
        .unwrap_or_default();
    let path = format!("/weights/recommend?{}", qs);
    forward_get(&state.services.http, &state.settings.ai_service_url, &path, &headers).await
}

pub async fn scan_anomalies(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Query(params): Query<Value>,
) -> Response {
    let qs: String = params.as_object()
        .map(|m| m.iter()
            .filter_map(|(k, v)| v.as_str().map(|s| format!("{}={}", k, s)))
            .collect::<Vec<_>>().join("&"))
        .unwrap_or_default();
    let path = format!("/anomalies?{}", qs);
    forward_get(&state.services.http, &state.settings.ai_service_url, &path, &headers).await
}
