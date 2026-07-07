/// Generic passthrough routes for services that need no payload transformation.
///
/// Each handler extracts the raw JSON body and proxies it unchanged to the
/// appropriate upstream, forwarding the upstream HTTP status to the caller.
use axum::{
    body::Bytes,
    extract::{Extension, Path, Query, State},
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use nexus_auth::Claims;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::{
    proxy::{
        circuit_breaker::CircuitBreaker,
        mdm_proxy::{mdm_service_auth, proxy_mdm_post},
    },
    state::AppState,
};

// â"€â"€ Helper â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

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

/// Forward a GET, optionally appending a raw query string (e.g. `"key=val&key2=val2"`).
async fn forward_get_with_query(
    http:      &reqwest::Client,
    base_url:  &str,
    path:      &str,
    query:     Option<&str>,
    headers:   &HeaderMap,
) -> Response {
    let base = format!("{}{}", base_url.trim_end_matches('/'), path);
    let url = match query {
        Some(q) if !q.is_empty() => format!("{}?{}", base, q),
        _ => base,
    };
    let mut req = http.get(&url);
    for (k, v) in headers.iter() {
        if k.as_str() == "authorization" { continue; }
        if let Ok(v) = v.to_str() { req = req.header(k.as_str(), v); }
    }
    match req.send().await {
        Ok(resp) => {
            let status = resp.status();
            let body: Value = resp.json().await.unwrap_or(Value::Null);
            (status, Json(body)).into_response()
        }
        Err(e) => {
            tracing::error!(error=%e, url=%url, "upstream GET failed");
            (StatusCode::BAD_GATEWAY, Json(json!({ "error": "upstream unavailable" }))).into_response()
        }
    }
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
        if key == "authorization" {
            // Never forward client credentials to downstreams regardless of whether
            // a service-auth override is set.  Each proxy call manages its own auth header.
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

/// Build a percent-encoded query string from a JSON object map.
/// Values that are not strings are silently omitted.
fn build_qs(map: Option<&serde_json::Map<String, Value>>) -> String {
    let Some(m) = map else { return String::new() };
    url::form_urlencoded::Serializer::new(String::new())
        .extend_pairs(m.iter().filter_map(|(k, v)| v.as_str().map(|s| (k.as_str(), s))))
        .finish()
}

/// Build a percent-encoded query string from a plain string HashMap.
fn build_qs_map(map: &std::collections::HashMap<String, String>) -> String {
    url::form_urlencoded::Serializer::new(String::new())
        .extend_pairs(map.iter().map(|(k, v)| (k.as_str(), v.as_str())))
        .finish()
}

/// Select the circuit breaker that matches this upstream URL.
/// Falls back to `cb_mdm` for unknown upstreams â€" conservative but safe.
fn pick_cb<'a>(state: &'a AppState, base_url: &str) -> &'a CircuitBreaker {
    if base_url == state.settings.ai_service_url { return &state.cb_ai; }
    &state.cb_mdm
}

async fn forward_post(
    state:    &AppState,
    base_url: &str,
    path:     &str,
    headers:  &HeaderMap,
    body:     Value,
) -> Response {
    let cb = pick_cb(state, base_url);
    match proxy_mdm_post(&state.services.http, base_url, path, headers, body, cb).await {
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

    // Only forward validated context headers â€" never forward connection/encoding
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

// â"€â"€ Search routes â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

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

    // Always enforce the authenticated tenant from the gateway-validated header.
    // This prevents cross-tenant data access via a forged ?tenant_id= param.
    if let Some(tid) = headers.get("x-tenant-id").and_then(|v| v.to_str().ok()) {
        map.insert("tenant_id".to_string(), serde_json::Value::String(tid.to_owned()));
    } else {
        return (StatusCode::UNAUTHORIZED, Json(serde_json::json!({
            "success": false,
            "error": "missing tenant context"
        }))).into_response();
    }

    let qs = build_qs(Some(&map));
    let path = if qs.is_empty() { "/search".to_string() } else { format!("/search?{}", qs) };
    forward_get(&state.services.http, &state.settings.search_service_url, &path, &headers).await
}

pub async fn autocomplete(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Query(params): Query<Value>,
) -> Response {
    let mut map = params.as_object().cloned().unwrap_or_default();

    // Always enforce the authenticated tenant — never trust client-supplied tenant_id.
    if let Some(tid) = headers.get("x-tenant-id").and_then(|v| v.to_str().ok()) {
        map.insert("tenant_id".to_string(), serde_json::Value::String(tid.to_owned()));
    } else {
        return (StatusCode::UNAUTHORIZED, Json(serde_json::json!({
            "success": false,
            "error": "missing tenant context"
        }))).into_response();
    }

    let qs = build_qs(Some(&map));
    let path = format!("/search/autocomplete?{}", qs);
    forward_get(&state.services.http, &state.settings.search_service_url, &path, &headers).await
}

// â"€â"€ Policy routes â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

pub async fn evaluate_policy(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Json(body):   Json<Value>,
) -> Response {
    forward_post(&state, &state.settings.policy_service_url, "/policy/evaluate", &headers, body).await
}

pub async fn list_policy_rules(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Query(params): Query<Value>,
) -> Response {
    let qs = build_qs(params.as_object());
    let path = format!("/policy/rules?{}", qs);
    forward_get(&state.services.http, &state.settings.policy_service_url, &path, &headers).await
}

pub async fn create_policy_rule(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Json(body):   Json<Value>,
) -> Response {
    forward_post(&state, &state.settings.policy_service_url, "/policy/rules", &headers, body).await
}

pub async fn gdpr_erasure(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Json(body):   Json<Value>,
) -> Response {
    forward_post(&state, &state.settings.policy_service_url, "/policy/gdpr/erasure", &headers, body).await
}

pub async fn gdpr_access(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Json(body):   Json<Value>,
) -> Response {
    forward_post(&state, &state.settings.policy_service_url, "/policy/gdpr/access", &headers, body).await
}

pub async fn update_policy_rule(
    State(state):            State<AppState>,
    headers:                 HeaderMap,
    axum::extract::Path(id): axum::extract::Path<String>,
    Query(params):           Query<Value>,
    Json(body):              Json<Value>,
) -> Response {
    let qs = build_qs(params.as_object());
    let path = if qs.is_empty() { format!("/policy/rules/{}", id) } else { format!("/policy/rules/{}?{}", id, qs) };
    forward_put(&state.services.http, &state.settings.policy_service_url, &path, &headers, body).await
}

pub async fn delete_policy_rule(
    State(state):            State<AppState>,
    headers:                 HeaderMap,
    axum::extract::Path(id): axum::extract::Path<String>,
    Query(params):           Query<Value>,
) -> Response {
    let qs = build_qs(params.as_object());
    let path = if qs.is_empty() { format!("/policy/rules/{}", id) } else { format!("/policy/rules/{}?{}", id, qs) };
    forward_delete(&state.services.http, &state.settings.policy_service_url, &path, &headers).await
}

pub async fn toggle_policy_rule(
    State(state):            State<AppState>,
    headers:                 HeaderMap,
    axum::extract::Path(id): axum::extract::Path<String>,
    Query(params):           Query<Value>,
) -> Response {
    let qs = build_qs(params.as_object());
    let path = if qs.is_empty() { format!("/policy/rules/{}/toggle", id) } else { format!("/policy/rules/{}/toggle?{}", id, qs) };
    forward_patch(&state.services.http, &state.settings.policy_service_url, &path, &headers, Value::Null).await
}

pub async fn policy_survivorship_suggestions(
    State(state): State<AppState>,
    headers:      HeaderMap,
) -> Response {
    forward_get_with_service_auth(
        &state.services.http,
        &state.settings.mdm_core_url,
        "/policy/survivorship-suggestions",
        &headers,
    ).await
}

pub async fn policy_gdpr_requests(
    State(state): State<AppState>,
    headers:      HeaderMap,
) -> Response {
    forward_get_with_service_auth(
        &state.services.http,
        &state.settings.mdm_core_url,
        "/policy/gdpr/requests",
        &headers,
    ).await
}

// â"€â"€ Distribution routes â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

pub async fn enqueue_distribution(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Json(body):   Json<Value>,
) -> Response {
    forward_post(&state, &state.settings.distribution_service_url, "/jobs", &headers, body).await
}

pub async fn list_distribution_jobs(
    State(state):  State<AppState>,
    headers:       HeaderMap,
    Query(params): Query<Value>,
) -> Response {
    let qs = build_qs(params.as_object());
    let path = if qs.is_empty() { "/jobs".to_string() } else { format!("/jobs?{}", qs) };
    forward_get(&state.services.http, &state.settings.distribution_service_url, &path, &headers).await
}

pub async fn get_distribution_job(
    State(state):                      State<AppState>,
    headers:                           HeaderMap,
    axum::extract::Path(job_id):       axum::extract::Path<String>,
    Query(params):                     Query<Value>,
) -> Response {
    let qs = build_qs(params.as_object());
    let path = if qs.is_empty() {
        format!("/jobs/{}", job_id)
    } else {
        format!("/jobs/{}?{}", job_id, qs)
    };
    forward_get(&state.services.http, &state.settings.distribution_service_url, &path, &headers).await
}

// â"€â"€ Match review queue routes â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

pub async fn get_match_review_queue(
    State(state):  State<AppState>,
    headers:       HeaderMap,
    Query(params): Query<Value>,
) -> Response {
    let qs = build_qs(params.as_object());
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
    forward_post(&state, &state.settings.mdm_core_url, &path, &headers, body).await
}

pub async fn reject_match_candidate(
    State(state):  State<AppState>,
    headers:       HeaderMap,
    axum::extract::Path((request_id, candidate_id)): axum::extract::Path<(String, String)>,
    body:          Option<Json<Value>>,
) -> Response {
    let path = format!("/match/{}/candidates/{}/reject", request_id, candidate_id);
    let body = body.map(|b| b.0).unwrap_or(Value::Null);
    forward_post(&state, &state.settings.mdm_core_url, &path, &headers, body).await
}

// â"€â"€ Policy weights (expose mdm-core internal route via gateway) â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

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

// â"€â"€ Ingest routes â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

pub async fn ingest_batch(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Json(body):   Json<Value>,
) -> Response {
    forward_post(&state, &state.settings.ingest_service_url, "/ingest/batch", &headers, body).await
}

pub async fn ingest_entities(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Json(body):   Json<Value>,
) -> Response {
    forward_post(&state, &state.settings.ingest_service_url, "/ingest/entities", &headers, body).await
}

pub async fn ingest_csv(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Json(body):   Json<Value>,
) -> Response {
    forward_post(&state, &state.settings.ingest_service_url, "/ingest/csv", &headers, body).await
}

pub async fn list_ingest_jobs(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Query(params): Query<std::collections::HashMap<String, String>>,
) -> Response {
    let qs = build_qs_map(&params);
    let path = format!("/ingest/jobs?{}", qs);
    forward_get(&state.services.http, &state.settings.ingest_service_url, &path, &headers).await
}

pub async fn get_ingest_job(
    State(state):                     State<AppState>,
    headers:                          HeaderMap,
    axum::extract::Path(job_id):      axum::extract::Path<String>,
    Query(params):                    Query<std::collections::HashMap<String, String>>,
) -> Response {
    let qs = build_qs_map(&params);
    let path = format!("/ingest/jobs/{}?{}", job_id, qs);
    forward_get(&state.services.http, &state.settings.ingest_service_url, &path, &headers).await
}

// â"€â"€ Golden record routes (proxied to mdm-core) â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

pub async fn list_golden_records(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Query(params): Query<std::collections::HashMap<String, String>>,
) -> Response {
    let qs = build_qs_map(&params);
    let path = format!("/golden-records?{}", qs);
    forward_get(&state.services.http, &state.settings.mdm_core_url, &path, &headers).await
}

pub async fn get_golden_record(
    State(state):                State<AppState>,
    headers:                     HeaderMap,
    axum::extract::Path(id):     axum::extract::Path<String>,
) -> Response {
    let path = format!("/golden-records/{}", id);
    forward_get(&state.services.http, &state.settings.mdm_core_url, &path, &headers).await
}

pub async fn patch_golden_record_attributes(
    State(state):                State<AppState>,
    headers:                     HeaderMap,
    axum::extract::Path(id):     axum::extract::Path<String>,
    Json(body):                  Json<serde_json::Value>,
) -> Response {
    let path = format!("/golden-records/{}/attributes", id);
    forward_patch(&state.services.http, &state.settings.mdm_core_url, &path, &headers, body).await
}

// â"€â"€ Entity routes (proxied to mdm-core with service auth) â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

pub async fn list_entities(
    State(state):   State<AppState>,
    headers:        HeaderMap,
    Query(params):  Query<Value>,
) -> Response {
    let qs = build_qs(params.as_object());
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

// â"€â"€ Dashboard routes (aggregated from mdm-core) â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

pub async fn dashboard_stats(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Query(params): Query<Value>,
) -> Response {
    let qs = build_qs(params.as_object());
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
    let qs = build_qs(params.as_object());
    let path = if qs.is_empty() {
        "/dashboard/activity".to_string()
    } else {
        format!("/dashboard/activity?{}", qs)
    };
    forward_get_with_service_auth(&state.services.http, &state.settings.mdm_core_url, &path, &headers).await
}

// â"€â"€ Notification webhook subscription management â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

pub async fn dashboard_steward_performance(
    State(state): State<AppState>,
    headers:      HeaderMap,
) -> Response {
    forward_get_with_service_auth(
        &state.services.http,
        &state.settings.mdm_core_url,
        "/dashboard/steward-performance",
        &headers,
    ).await
}

pub async fn dashboard_quality_dimensions(
    State(state): State<AppState>,
    headers:      HeaderMap,
) -> Response {
    forward_get_with_service_auth(
        &state.services.http,
        &state.settings.mdm_core_url,
        "/dashboard/quality-dimensions",
        &headers,
    ).await
}

pub async fn list_webhooks(
    State(state):  State<AppState>,
    headers:       HeaderMap,
    Query(params): Query<std::collections::HashMap<String, String>>,
) -> Response {
    let qs = build_qs_map(&params);
    let path = format!("/webhooks?{}", qs);
    forward_get(&state.services.http, &state.settings.notification_service_url, &path, &headers).await
}

pub async fn create_webhook(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Json(body):   Json<Value>,
) -> Response {
    forward_post(&state, &state.settings.notification_service_url, "/webhooks", &headers, body).await
}

pub async fn delete_webhook(
    State(state):            State<AppState>,
    headers:                 HeaderMap,
    axum::extract::Path(id): axum::extract::Path<String>,
) -> Response {
    let path = format!("/webhooks/{}", id);
    forward_delete(&state.services.http, &state.settings.notification_service_url, &path, &headers).await
}

// â"€â"€ Audit routes â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

pub async fn list_audit_events(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Query(params): Query<Value>,
) -> Response {
    let qs = build_qs(params.as_object());
    let path = if qs.is_empty() {
        "/audit/events".to_string()
    } else {
        format!("/audit/events?{}", qs)
    };
    forward_get_with_service_auth(&state.services.http, &state.settings.mdm_core_url, &path, &headers).await
}

// â"€â"€ Consent routes â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

pub async fn list_lineage_events(
    State(state):  State<AppState>,
    headers:       HeaderMap,
    Query(params): Query<Value>,
) -> Response {
    let qs = build_qs(params.as_object());
    let path = if qs.is_empty() { "/lineage".to_string() } else { format!("/lineage?{}", qs) };
    forward_get_with_service_auth(&state.services.http, &state.settings.mdm_core_url, &path, &headers).await
}

pub async fn get_lineage_stats(
    State(state): State<AppState>,
    headers:      HeaderMap,
) -> Response {
    forward_get_with_service_auth(&state.services.http, &state.settings.mdm_core_url, "/lineage/stats", &headers).await
}

pub async fn get_lineage_graph(
    State(state): State<AppState>,
    headers:      HeaderMap,
) -> Response {
    forward_get_with_service_auth(&state.services.http, &state.settings.mdm_core_url, "/lineage/graph", &headers).await
}

pub async fn record_consent(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Json(body):   Json<Value>,
) -> Response {
    forward_post(&state, &state.settings.policy_service_url, "/policy/consent", &headers, body).await
}

pub async fn list_consent(
    State(state):  State<AppState>,
    headers:       HeaderMap,
    Query(params): Query<Value>,
) -> Response {
    let qs = build_qs(params.as_object());
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
    let qs = build_qs(params.as_object());
    let path = format!("/policy/consent/{}/withdraw?{}", consent_id, qs);
    forward_post(&state, &state.settings.policy_service_url, &path, &headers, Value::Null).await
}

// â"€â"€ Lineage routes â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

pub async fn get_entity_lineage(
    State(state):         State<AppState>,
    headers:              HeaderMap,
    axum::extract::Path(entity_id): axum::extract::Path<String>,
    Query(params):        Query<Value>,
) -> Response {
    let qs = build_qs(params.as_object());
    let path = format!("/entities/{}/lineage?{}", entity_id, qs);
    forward_get_with_service_auth(&state.services.http, &state.settings.mdm_core_url, &path, &headers).await
}

// â"€â"€ Merge routes â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

pub async fn execute_merge(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Json(body):   Json<Value>,
) -> Response {
    forward_post(&state, &state.settings.mdm_core_url, "/merge", &headers, body).await
}

// â"€â"€ AI service routes â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

pub async fn recommend_weights(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Query(params): Query<Value>,
) -> Response {
    let qs = build_qs(params.as_object());
    let path = format!("/weights/recommend?{}", qs);
    forward_get(&state.services.http, &state.settings.ai_service_url, &path, &headers).await
}

pub async fn scan_anomalies(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Query(params): Query<Value>,
) -> Response {
    let qs = build_qs(params.as_object());
    let path = format!("/anomalies?{}", qs);
    forward_get(&state.services.http, &state.settings.ai_service_url, &path, &headers).await
}

// â"€â"€ Admin: Tenant Management (â†' tenant-service) â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

pub async fn admin_list_tenants(
    State(state): State<AppState>,
    headers:      HeaderMap,
) -> Response {
    forward_get(&state.services.http, &state.settings.tenant_service_url, "/admin/tenants", &headers).await
}

pub async fn admin_create_tenant(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Json(body):   Json<Value>,
) -> Response {
    forward_post(&state, &state.settings.tenant_service_url, "/admin/tenants", &headers, body).await
}

pub async fn admin_create_admin_user(
    State(state): State<AppState>,
    headers:      HeaderMap,
    axum::extract::Path(tenant_id): axum::extract::Path<String>,
    Json(body):   Json<Value>,
) -> Response {
    let path = format!("/admin/tenants/{}/admin-user", tenant_id);
    forward_post(&state, &state.settings.tenant_service_url, &path, &headers, body).await
}

pub async fn admin_list_users(
    State(state):   State<AppState>,
    headers:        HeaderMap,
    Query(params):  Query<Value>,
) -> Response {
    let qs = build_qs(params.as_object());
    let path = format!("/users?{}", qs);
    forward_get_with_service_auth(&state.services.http, &state.settings.mdm_core_url, &path, &headers).await
}

pub async fn admin_invite_user(
    State(state):  State<AppState>,
    opt_claims:    Option<Extension<Claims>>,
    headers:       HeaderMap,
    Json(mut body): Json<Value>,
) -> Response {
    // Inject invited_by from the caller's JWT claims when available.
    // Falls back to "Nexus AI MDM" in AUTH_DISABLED=true dev mode.
    if body.get("invited_by").is_none() {
        if let Some(Extension(claims)) = opt_claims {
            body["invited_by"] = json!(claims.nxs_email);
        }
    }
    forward_post(&state, &state.settings.mdm_core_url, "/users/invite", &headers, body).await
}

pub async fn admin_update_user_role(
    State(state):                     State<AppState>,
    headers:                          HeaderMap,
    axum::extract::Path(user_id):     axum::extract::Path<String>,
    Json(body):                       Json<Value>,
) -> Response {
    let path = format!("/users/{}/role", user_id);
    forward_patch(&state.services.http, &state.settings.mdm_core_url, &path, &headers, body).await
}

// â"€â"€ Admin: Entity Types & Attributes (â†' mdm-core) â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

pub async fn list_entity_types(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Query(params): Query<Value>,
) -> Response {
    let qs = build_qs(params.as_object());
    let path = format!("/entity-types?{}", qs);
    forward_get_with_service_auth(&state.services.http, &state.settings.mdm_core_url, &path, &headers).await
}

pub async fn create_entity_type(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Json(body):   Json<Value>,
) -> Response {
    forward_post(&state, &state.settings.mdm_core_url, "/entity-types", &headers, body).await
}

pub async fn update_entity_type(
    State(state): State<AppState>,
    headers:      HeaderMap,
    axum::extract::Path(id): axum::extract::Path<String>,
    Json(body):   Json<Value>,
) -> Response {
    let path = format!("/entity-types/{}", id);
    forward_patch(&state.services.http, &state.settings.mdm_core_url, &path, &headers, body).await
}

pub async fn delete_entity_type(
    State(state): State<AppState>,
    headers:      HeaderMap,
    axum::extract::Path(id): axum::extract::Path<String>,
) -> Response {
    let path = format!("/entity-types/{}", id);
    forward_delete(&state.services.http, &state.settings.mdm_core_url, &path, &headers).await
}

pub async fn list_attributes(
    State(state): State<AppState>,
    headers:      HeaderMap,
    axum::extract::Path(code): axum::extract::Path<String>,
    Query(params): Query<Value>,
) -> Response {
    let qs = build_qs(params.as_object());
    let path = format!("/entity-types/{}/attributes?{}", code, qs);
    forward_get_with_service_auth(&state.services.http, &state.settings.mdm_core_url, &path, &headers).await
}

pub async fn create_attribute(
    State(state): State<AppState>,
    headers:      HeaderMap,
    axum::extract::Path(code): axum::extract::Path<String>,
    Json(body):   Json<Value>,
) -> Response {
    let path = format!("/entity-types/{}/attributes", code);
    forward_post(&state, &state.settings.mdm_core_url, &path, &headers, body).await
}

pub async fn delete_attribute(
    State(state): State<AppState>,
    headers:      HeaderMap,
    axum::extract::Path((code, attr_id)): axum::extract::Path<(String, String)>,
) -> Response {
    let path = format!("/entity-types/{}/attributes/{}", code, attr_id);
    forward_delete(&state.services.http, &state.settings.mdm_core_url, &path, &headers).await
}

pub async fn reorder_attributes(
    State(state): State<AppState>,
    headers:      HeaderMap,
    axum::extract::Path(code): axum::extract::Path<String>,
    Json(body):   Json<Value>,
) -> Response {
    let path = format!("/entity-types/{}/attributes/order", code);
    forward_put(&state.services.http, &state.settings.mdm_core_url, &path, &headers, body).await
}

pub async fn next_sequence(
    State(state): State<AppState>,
    headers:      HeaderMap,
    axum::extract::Path(code): axum::extract::Path<String>,
    Query(params): Query<Value>,
) -> Response {
    let qs = build_qs(params.as_object());
    let path = format!("/entity-types/{}/next-sequence?{}", code, qs);
    forward_get_with_service_auth(&state.services.http, &state.settings.mdm_core_url, &path, &headers).await
}

// â"€â"€ Admin: Source Systems (â†' ingest-service) â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

pub async fn list_source_systems(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Query(params): Query<Value>,
) -> Response {
    let qs = build_qs(params.as_object());
    let path = format!("/source-systems?{}", qs);
    forward_get(&state.services.http, &state.settings.ingest_service_url, &path, &headers).await
}

pub async fn create_source_system(
    State(state): State<AppState>,
    headers:      HeaderMap,
    Json(body):   Json<Value>,
) -> Response {
    forward_post(&state, &state.settings.ingest_service_url, "/source-systems", &headers, body).await
}

pub async fn update_source_system(
    State(state): State<AppState>,
    headers:      HeaderMap,
    axum::extract::Path(id): axum::extract::Path<String>,
    Json(body):   Json<Value>,
) -> Response {
    let path = format!("/source-systems/{}", id);
    forward_put(&state.services.http, &state.settings.ingest_service_url, &path, &headers, body).await
}

pub async fn delete_source_system(
    State(state): State<AppState>,
    headers:      HeaderMap,
    axum::extract::Path(id): axum::extract::Path<String>,
) -> Response {
    let path = format!("/source-systems/{}", id);
    forward_delete(&state.services.http, &state.settings.ingest_service_url, &path, &headers).await
}

pub async fn test_source_system(
    State(state): State<AppState>,
    headers:      HeaderMap,
    axum::extract::Path(id): axum::extract::Path<String>,
) -> Response {
    let path = format!("/source-systems/{}/test", id);
    forward_post(&state, &state.settings.ingest_service_url, &path, &headers, serde_json::json!({})).await
}

// â"€â"€ Auth: Accept invite (public, proxied to mdm-core) â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

/// POST /auth/accept-invite â€" public endpoint, no auth required.
/// Validates an invite token and lets the user set their initial password.
pub async fn accept_invite(
    State(state): State<AppState>,
    _headers:     HeaderMap,
    Json(body):   Json<Value>,
) -> Response {
    let url = format!("{}/auth/accept-invite", state.settings.mdm_core_url.trim_end_matches('/'));
    match state.services.http.post(&url).json(&body).send().await {
        Ok(resp) => {
            let status = resp.status();
            let b: Value = resp.json().await.unwrap_or(Value::Null);
            (status, Json(b)).into_response()
        }
        Err(e) => {
            tracing::error!(error=%e, "accept-invite upstream failed");
            (StatusCode::BAD_GATEWAY, Json(serde_json::json!({ "success": false, "error": "upstream unavailable" }))).into_response()
        }
    }
}

// â"€â"€ Auth: Invite info (public, proxied to mdm-core) â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

/// GET /auth/invite-info?token=XXX â€" no auth required.
/// Returns tenant_name, email, role for an invitation token.
pub async fn invite_info(
    State(state): State<AppState>,
    Query(params): Query<std::collections::HashMap<String, String>>,
) -> Response {
    let token = params.get("token").cloned().unwrap_or_default();
    let url = format!(
        "{}/auth/invite-info?token={}",
        state.settings.mdm_core_url.trim_end_matches('/'),
        token,
    );
    match state.services.http.get(&url).send().await {
        Ok(resp) => {
            let status = resp.status();
            let b: Value = resp.json().await.unwrap_or(Value::Null);
            (status, Json(b)).into_response()
        }
        Err(e) => {
            tracing::error!(error=%e, "invite-info upstream failed");
            (StatusCode::BAD_GATEWAY, Json(serde_json::json!({ "success": false, "error": "upstream unavailable" }))).into_response()
        }
    }
}

// â"€â"€ PUT / DELETE forwarding helpers â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

async fn forward_put(
    http:     &reqwest::Client,
    base_url: &str,
    path:     &str,
    headers:  &HeaderMap,
    body:     Value,
) -> Response {
    let url = format!("{}{}", base_url.trim_end_matches('/'), path);
    let svc_auth = crate::proxy::mdm_proxy::mdm_service_auth();
    let mut req = http.put(&url).json(&body).header("authorization", svc_auth.as_str());
    for (name, value) in headers.iter() {
        let key = name.as_str();
        if matches!(key, "x-tenant-id" | "x-user-id" | "x-user-role" | "x-correlation-id") {
            if let Ok(v) = value.to_str() { req = req.header(key, v); }
        }
    }
    match req.send().await {
        Ok(resp) => {
            let status = resp.status();
            let body: Value = resp.json().await.unwrap_or(Value::Null);
            (status, Json(body)).into_response()
        }
        Err(e) => {
            tracing::error!(error=%e, url=%url, "upstream PUT failed");
            (StatusCode::BAD_GATEWAY, Json(serde_json::json!({ "success": false, "error": "upstream unavailable" }))).into_response()
        }
    }
}

async fn forward_delete(
    http:     &reqwest::Client,
    base_url: &str,
    path:     &str,
    headers:  &HeaderMap,
) -> Response {
    let url = format!("{}{}", base_url.trim_end_matches('/'), path);
    let svc_auth = crate::proxy::mdm_proxy::mdm_service_auth();
    let mut req = http.delete(&url).header("authorization", svc_auth.as_str());
    for (name, value) in headers.iter() {
        let key = name.as_str();
        if matches!(key, "x-tenant-id" | "x-user-id" | "x-user-role" | "x-correlation-id") {
            if let Ok(v) = value.to_str() { req = req.header(key, v); }
        }
    }
    match req.send().await {
        Ok(resp) => {
            let status = resp.status();
            let body: Value = resp.json().await.unwrap_or(Value::Null);
            (status, Json(body)).into_response()
        }
        Err(e) => {
            tracing::error!(error=%e, url=%url, "upstream DELETE failed");
            (StatusCode::BAD_GATEWAY, Json(serde_json::json!({ "success": false, "error": "upstream unavailable" }))).into_response()
        }
    }
}

/// Parse a raw `Bytes` body as JSON, falling back to `Value::Null` on error.
fn bytes_to_value(body: Bytes) -> Value {
    if body.is_empty() {
        return serde_json::Value::Object(Default::default());
    }
    serde_json::from_slice(&body).unwrap_or_else(|_| serde_json::Value::Object(Default::default()))
}

// â"€â"€ Domain Policies â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

pub async fn list_domain_policies(
    State(state):  State<AppState>,
    headers:       HeaderMap,
    Query(params): Query<Value>,
) -> impl IntoResponse {
    let qs = build_qs(params.as_object());
    let path = if qs.is_empty() {
        "/domain-policies".to_string()
    } else {
        format!("/domain-policies?{}", qs)
    };
    forward_get_with_service_auth(&state.services.http, &state.settings.mdm_core_url, &path, &headers).await
}

pub async fn get_domain_policy(
    State(state):            State<AppState>,
    Path(entity_type_code):  Path<String>,
    headers:                 HeaderMap,
) -> impl IntoResponse {
    let path = format!("/domain-policies/{}", entity_type_code);
    forward_get_with_service_auth(&state.services.http, &state.settings.mdm_core_url, &path, &headers).await
}

pub async fn upsert_domain_policy(
    State(state):            State<AppState>,
    Path(entity_type_code):  Path<String>,
    headers:                 HeaderMap,
    body:                    Bytes,
) -> impl IntoResponse {
    let path = format!("/domain-policies/{}", entity_type_code);
    forward_put(&state.services.http, &state.settings.mdm_core_url, &path, &headers, bytes_to_value(body)).await
}

pub async fn delete_domain_policy(
    State(state):            State<AppState>,
    Path(entity_type_code):  Path<String>,
    headers:                 HeaderMap,
) -> impl IntoResponse {
    let path = format!("/domain-policies/{}", entity_type_code);
    forward_delete(&state.services.http, &state.settings.mdm_core_url, &path, &headers).await
}

// â"€â"€ Relationship Types â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

pub async fn list_relationship_types(
    State(state):  State<AppState>,
    headers:       HeaderMap,
    Query(params): Query<Value>,
) -> impl IntoResponse {
    let qs = build_qs(params.as_object());
    let path = if qs.is_empty() {
        "/relationship-types".to_string()
    } else {
        format!("/relationship-types?{}", qs)
    };
    forward_get_with_service_auth(&state.services.http, &state.settings.mdm_core_url, &path, &headers).await
}

pub async fn create_relationship_type(
    State(state): State<AppState>,
    headers:      HeaderMap,
    body:         Bytes,
) -> impl IntoResponse {
    forward_post(&state, &state.settings.mdm_core_url, "/relationship-types", &headers, bytes_to_value(body)).await
}

pub async fn delete_relationship_type(
    State(state):    State<AppState>,
    Path(type_id):   Path<Uuid>,
    headers:         HeaderMap,
) -> impl IntoResponse {
    let path = format!("/relationship-types/{}", type_id);
    forward_delete(&state.services.http, &state.settings.mdm_core_url, &path, &headers).await
}

// â"€â"€ Entity Relationships â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

pub async fn list_entity_relationships(
    State(state): State<AppState>,
    Path(id):     Path<Uuid>,
    headers:      HeaderMap,
) -> impl IntoResponse {
    let path = format!("/entities/{}/relationships", id);
    forward_get_with_service_auth(&state.services.http, &state.settings.mdm_core_url, &path, &headers).await
}

pub async fn create_entity_relationship(
    State(state): State<AppState>,
    Path(id):     Path<Uuid>,
    headers:      HeaderMap,
    body:         Bytes,
) -> impl IntoResponse {
    let path = format!("/entities/{}/relationships", id);
    forward_post(&state, &state.settings.mdm_core_url, &path, &headers, bytes_to_value(body)).await
}

pub async fn delete_entity_relationship(
    State(state): State<AppState>,
    Path(id):     Path<Uuid>,
    headers:      HeaderMap,
) -> impl IntoResponse {
    let path = format!("/relationships/{}", id);
    forward_delete(&state.services.http, &state.settings.mdm_core_url, &path, &headers).await
}

// â"€â"€ Review Queue Extras â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

pub async fn queue_metrics(
    State(state): State<AppState>,
    headers:      HeaderMap,
) -> impl IntoResponse {
    forward_get_with_service_auth(&state.services.http, &state.settings.mdm_core_url, "/match/queue-metrics", &headers).await
}

pub async fn bulk_approve_matches(
    State(state): State<AppState>,
    headers:      HeaderMap,
    body:         Bytes,
) -> impl IntoResponse {
    forward_post(&state, &state.settings.mdm_core_url, "/match/bulk-approve", &headers, bytes_to_value(body)).await
}

pub async fn bulk_reject_matches(
    State(state): State<AppState>,
    headers:      HeaderMap,
    body:         Bytes,
) -> impl IntoResponse {
    forward_post(&state, &state.settings.mdm_core_url, "/match/bulk-reject", &headers, bytes_to_value(body)).await
}

pub async fn defer_match(
    State(state):                   State<AppState>,
    Path((request_id, candidate_id)): Path<(Uuid, Uuid)>,
    headers:                        HeaderMap,
    body:                           Bytes,
) -> impl IntoResponse {
    let path = format!("/match/{}/candidates/{}/defer", request_id, candidate_id);
    forward_post(&state, &state.settings.mdm_core_url, &path, &headers, bytes_to_value(body)).await
}

pub async fn assign_review(
    State(state):    State<AppState>,
    Path(review_id): Path<Uuid>,
    headers:         HeaderMap,
    body:            Bytes,
) -> impl IntoResponse {
    let path = format!("/match/review-queue/{}/assign", review_id);
    forward_patch(&state.services.http, &state.settings.mdm_core_url, &path, &headers, bytes_to_value(body)).await
}

// â"€â"€ License â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

pub async fn get_my_license(
    State(state): State<AppState>,
    headers:      HeaderMap,
) -> impl IntoResponse {
    forward_get_with_service_auth(&state.services.http, &state.settings.mdm_core_url, "/license", &headers).await
}

// â"€â"€ Password Reset â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

pub async fn forgot_password(
    State(state): State<AppState>,
    headers:      HeaderMap,
    body:         Bytes,
) -> impl IntoResponse {
    forward_post(&state, &state.settings.mdm_core_url, "/auth/forgot-password", &headers, bytes_to_value(body)).await
}

pub async fn reset_password(
    State(state): State<AppState>,
    headers:      HeaderMap,
    body:         Bytes,
) -> impl IntoResponse {
    forward_post(&state, &state.settings.mdm_core_url, "/auth/reset-password", &headers, bytes_to_value(body)).await
}

/// POST /auth/change-password — protected endpoint.
///
/// The gateway's inject_user_context middleware adds `x-user-id` before
/// forwarding; mdm-core uses that header to identify which identity's password
/// to change, avoiding the "service-account" stub that appears when the gateway
/// uses service-to-service auth.
pub async fn change_password(
    State(state): State<AppState>,
    headers:      HeaderMap,
    body:         Bytes,
) -> impl IntoResponse {
    forward_post(&state, &state.settings.mdm_core_url, "/auth/change-password", &headers, bytes_to_value(body)).await
}

/// POST /auth/sso-exchange — public endpoint, no auth required.
/// Validates a third-party OIDC access token (Google, Azure AD, Okta) and
/// returns Nexus JWT tokens. Forwarded to mdm-core which calls the provider's
/// userinfo endpoint and issues tokens.
pub async fn sso_exchange(
    State(state): State<AppState>,
    headers:      HeaderMap,
    body:         Bytes,
) -> impl IntoResponse {
    forward_post(&state, &state.settings.mdm_core_url, "/auth/sso-exchange", &headers, bytes_to_value(body)).await
}

// â"€â"€ Tenant Branding â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

pub async fn get_tenant_branding(
    State(state): State<AppState>,
    headers:      HeaderMap,
) -> impl IntoResponse {
    forward_get_with_service_auth(&state.services.http, &state.settings.mdm_core_url, "/tenant/branding", &headers).await
}

pub async fn upsert_tenant_branding(
    State(state): State<AppState>,
    headers:      HeaderMap,
    body:         Bytes,
) -> impl IntoResponse {
    forward_put(&state.services.http, &state.settings.mdm_core_url, "/tenant/branding", &headers, bytes_to_value(body)).await
}

// â"€â"€ Data Governance â€" entity-type assignments â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

pub async fn list_governance_assignments(
    State(state):  State<AppState>,
    headers:       HeaderMap,
) -> impl IntoResponse {
    forward_get_with_service_auth(&state.services.http, &state.settings.mdm_core_url, "/governance/assignments", &headers).await
}

pub async fn my_governance_assigned_types(
    State(state): State<AppState>,
    headers:      HeaderMap,
) -> impl IntoResponse {
    forward_get_with_service_auth(&state.services.http, &state.settings.mdm_core_url, "/governance/assignments/my-types", &headers).await
}

pub async fn create_governance_assignment(
    State(state): State<AppState>,
    headers:      HeaderMap,
    body:         Bytes,
) -> impl IntoResponse {
    forward_post(&state, &state.settings.mdm_core_url, "/governance/assignments", &headers, bytes_to_value(body)).await
}

pub async fn delete_governance_assignment(
    State(state):    State<AppState>,
    Path(assign_id): Path<Uuid>,
    headers:         HeaderMap,
) -> impl IntoResponse {
    let path = format!("/governance/assignments/{}", assign_id);
    forward_delete(&state.services.http, &state.settings.mdm_core_url, &path, &headers).await
}

// â"€â"€ Data Governance â€" entity approval workflow â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

pub async fn list_pending_entity_approvals(
    State(state): State<AppState>,
    headers:      HeaderMap,
) -> impl IntoResponse {
    forward_get_with_service_auth(&state.services.http, &state.settings.mdm_core_url, "/entities/pending-approvals", &headers).await
}

pub async fn submit_entity_for_review(
    State(state):    State<AppState>,
    Path(entity_id): Path<Uuid>,
    headers:         HeaderMap,
    body:            Bytes,
) -> impl IntoResponse {
    let path = format!("/entities/{}/submit-for-review", entity_id);
    forward_post(&state, &state.settings.mdm_core_url, &path, &headers, bytes_to_value(body)).await
}

pub async fn approve_entity_proxy(
    State(state):    State<AppState>,
    Path(entity_id): Path<Uuid>,
    headers:         HeaderMap,
    body:            Bytes,
) -> impl IntoResponse {
    let path = format!("/entities/{}/approve", entity_id);
    forward_post(&state, &state.settings.mdm_core_url, &path, &headers, bytes_to_value(body)).await
}

pub async fn reject_entity_proxy(
    State(state):    State<AppState>,
    Path(entity_id): Path<Uuid>,
    headers:         HeaderMap,
    body:            Bytes,
) -> impl IntoResponse {
    let path = format!("/entities/{}/reject", entity_id);
    forward_post(&state, &state.settings.mdm_core_url, &path, &headers, bytes_to_value(body)).await
}

pub async fn bulk_approve_entities_proxy(
    State(state): State<AppState>,
    headers:      HeaderMap,
    body:         Bytes,
) -> impl IntoResponse {
    forward_post(&state, &state.settings.mdm_core_url, "/entities/bulk-approve", &headers, bytes_to_value(body)).await
}

pub async fn bulk_reject_entities_proxy(
    State(state): State<AppState>,
    headers:      HeaderMap,
    body:         Bytes,
) -> impl IntoResponse {
    forward_post(&state, &state.settings.mdm_core_url, "/entities/bulk-reject", &headers, bytes_to_value(body)).await
}

// ── User notification inbox ───────────────────────────────────────────────────

pub async fn list_notifications(
    State(state):  State<AppState>,
    headers:       HeaderMap,
    Query(params): Query<Value>,
) -> Response {
    let qs = build_qs(params.as_object());
    let path = if qs.is_empty() {
        "/notifications".to_string()
    } else {
        format!("/notifications?{}", qs)
    };
    forward_get_with_service_auth(&state.services.http, &state.settings.mdm_core_url, &path, &headers).await
}

pub async fn notifications_unread_count(
    State(state): State<AppState>,
    headers:      HeaderMap,
) -> Response {
    forward_get_with_service_auth(
        &state.services.http,
        &state.settings.mdm_core_url,
        "/notifications/unread-count",
        &headers,
    )
    .await
}

pub async fn mark_notification_read(
    State(state): State<AppState>,
    Path(id):     Path<Uuid>,
    headers:      HeaderMap,
    body:         Bytes,
) -> impl IntoResponse {
    let path = format!("/notifications/{}/read", id);
    forward_patch(
        &state.services.http,
        &state.settings.mdm_core_url,
        &path,
        &headers,
        bytes_to_value(body),
    )
    .await
}

pub async fn mark_all_notifications_read(
    State(state): State<AppState>,
    headers:      HeaderMap,
    body:         Bytes,
) -> impl IntoResponse {
    forward_post(&state, &state.settings.mdm_core_url, "/notifications/read-all", &headers, bytes_to_value(body)).await
}

// ── Submasters (reference data) ─────────────────────────────────────────────

pub async fn list_submaster_types(
    State(state): State<AppState>,
    headers:      HeaderMap,
) -> impl IntoResponse {
    forward_get_with_service_auth(&state.services.http, &state.settings.mdm_core_url, "/submasters", &headers).await
}

pub async fn create_submaster_type(
    State(state): State<AppState>,
    headers:      HeaderMap,
    body:         Bytes,
) -> impl IntoResponse {
    forward_post(&state, &state.settings.mdm_core_url, "/submasters", &headers, bytes_to_value(body)).await
}

pub async fn update_submaster_type(
    State(state):    State<AppState>,
    Path(code):      Path<String>,
    headers:         HeaderMap,
    body:            Bytes,
) -> impl IntoResponse {
    let path = format!("/submasters/{}", code);
    forward_patch(&state.services.http, &state.settings.mdm_core_url, &path, &headers, bytes_to_value(body)).await
}

pub async fn list_submaster_values(
    State(state): State<AppState>,
    Path(code):   Path<String>,
    headers:      HeaderMap,
) -> impl IntoResponse {
    let path = format!("/submasters/{}/values", code);
    forward_get_with_service_auth(&state.services.http, &state.settings.mdm_core_url, &path, &headers).await
}

pub async fn create_submaster_value(
    State(state): State<AppState>,
    Path(code):   Path<String>,
    headers:      HeaderMap,
    body:         Bytes,
) -> impl IntoResponse {
    let path = format!("/submasters/{}/values", code);
    forward_post(&state, &state.settings.mdm_core_url, &path, &headers, bytes_to_value(body)).await
}

pub async fn update_submaster_value(
    State(state):           State<AppState>,
    Path((code, value_id)): Path<(String, Uuid)>,
    headers:                HeaderMap,
    body:                   Bytes,
) -> impl IntoResponse {
    let path = format!("/submasters/{}/values/{}", code, value_id);
    forward_patch(&state.services.http, &state.settings.mdm_core_url, &path, &headers, bytes_to_value(body)).await
}

pub async fn delete_submaster_value(
    State(state):          State<AppState>,
    Path((code, value_id)): Path<(String, Uuid)>,
    headers:               HeaderMap,
) -> impl IntoResponse {
    let path = format!("/submasters/{}/values/{}", code, value_id);
    forward_delete(&state.services.http, &state.settings.mdm_core_url, &path, &headers).await
}

// ── Quality rules ─────────────────────────────────────────────────────────────

pub async fn list_quality_rules(
    State(state): State<AppState>,
    headers:      HeaderMap,
) -> impl IntoResponse {
    forward_get_with_service_auth(&state.services.http, &state.settings.mdm_core_url, "/quality-rules", &headers).await
}

pub async fn create_quality_rule(
    State(state): State<AppState>,
    headers:      HeaderMap,
    body:         Bytes,
) -> impl IntoResponse {
    forward_post(&state, &state.settings.mdm_core_url, "/quality-rules", &headers, bytes_to_value(body)).await
}

pub async fn update_quality_rule(
    State(state): State<AppState>,
    Path(id):     Path<Uuid>,
    headers:      HeaderMap,
    body:         Bytes,
) -> impl IntoResponse {
    let path = format!("/quality-rules/{}", id);
    forward_patch(&state.services.http, &state.settings.mdm_core_url, &path, &headers, bytes_to_value(body)).await
}

pub async fn delete_quality_rule(
    State(state): State<AppState>,
    Path(id):     Path<Uuid>,
    headers:      HeaderMap,
) -> impl IntoResponse {
    let path = format!("/quality-rules/{}", id);
    forward_delete(&state.services.http, &state.settings.mdm_core_url, &path, &headers).await
}

pub async fn reorder_quality_rules(
    State(state): State<AppState>,
    headers:      HeaderMap,
    body:         Bytes,
) -> impl IntoResponse {
    forward_post(&state, &state.settings.mdm_core_url, "/quality-rules/reorder", &headers, bytes_to_value(body)).await
}

pub async fn run_quality_rules(
    State(state): State<AppState>,
    headers:      HeaderMap,
) -> impl IntoResponse {
    forward_post(&state, &state.settings.mdm_core_url, "/quality-rules/run", &headers, serde_json::Value::Null).await
}

// ── Quality violations ────────────────────────────────────────────────────────

pub async fn list_quality_violations(
    State(state):                   State<AppState>,
    headers:                        HeaderMap,
    axum::extract::RawQuery(query): axum::extract::RawQuery,
) -> impl IntoResponse {
    forward_get_with_query(
        &state.services.http,
        &state.settings.mdm_core_url,
        "/quality-violations",
        query.as_deref(),
        &headers,
    )
    .await
}

pub async fn resolve_quality_violation(
    State(state): State<AppState>,
    Path(id):     Path<Uuid>,
    headers:      HeaderMap,
) -> impl IntoResponse {
    let path = format!("/quality-violations/{}/resolve", id);
    forward_patch(&state.services.http, &state.settings.mdm_core_url, &path, &headers, serde_json::Value::Null).await
}

pub async fn bulk_resolve_violations(
    State(state): State<AppState>,
    headers:      HeaderMap,
    body:         Bytes,
) -> impl IntoResponse {
    forward_post(&state, &state.settings.mdm_core_url, "/quality-violations/bulk-resolve", &headers, bytes_to_value(body)).await
}

// ── AI Suggestions (approval-gated LLM proposals) ────────────────────────────

pub async fn list_ai_suggestions(
    State(state):                   State<AppState>,
    headers:                        HeaderMap,
    axum::extract::RawQuery(query): axum::extract::RawQuery,
) -> impl IntoResponse {
    forward_get_with_query(
        &state.services.http,
        &state.settings.mdm_core_url,
        "/ai-suggestions",
        query.as_deref(),
        &headers,
    )
    .await
}

pub async fn approve_ai_suggestion(
    State(state): State<AppState>,
    Path(id):     Path<Uuid>,
    headers:      HeaderMap,
) -> impl IntoResponse {
    let path = format!("/ai-suggestions/{}/approve", id);
    forward_patch(&state.services.http, &state.settings.mdm_core_url, &path, &headers, serde_json::Value::Null).await
}

pub async fn reject_ai_suggestion(
    State(state): State<AppState>,
    Path(id):     Path<Uuid>,
    headers:      HeaderMap,
) -> impl IntoResponse {
    let path = format!("/ai-suggestions/{}/reject", id);
    forward_patch(&state.services.http, &state.settings.mdm_core_url, &path, &headers, serde_json::Value::Null).await
}

pub async fn trigger_address_parse(
    State(state):    State<AppState>,
    Path(entity_id): Path<Uuid>,
    headers:         HeaderMap,
    body:            Bytes,
) -> impl IntoResponse {
    let path = format!("/entities/{}/ai-suggestions/address-parse", entity_id);
    forward_post(&state, &state.settings.mdm_core_url, &path, &headers, bytes_to_value(body)).await
}

pub async fn trigger_anomaly_detection(
    State(state):    State<AppState>,
    Path(entity_id): Path<Uuid>,
    headers:         HeaderMap,
) -> impl IntoResponse {
    let path = format!("/entities/{}/ai-suggestions/anomaly", entity_id);
    forward_post(&state, &state.settings.mdm_core_url, &path, &headers, serde_json::Value::Null).await
}

pub async fn trigger_enrichment(
    State(state):    State<AppState>,
    Path(entity_id): Path<Uuid>,
    headers:         HeaderMap,
    body:            Bytes,
) -> impl IntoResponse {
    let path = format!("/entities/{}/ai-suggestions/enrichment", entity_id);
    forward_post(&state, &state.settings.mdm_core_url, &path, &headers, bytes_to_value(body)).await
}

