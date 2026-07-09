use axum::{
    extract::State,
    http::{header, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use serde_json::{json, Value};

use crate::state::AppState;

pub async fn health(State(state): State<AppState>) -> Json<Value> {
    let ws_connections = state.ws_manager.active_count();
    Json(json!({
        "status":         "ok",
        "service":        "api-gateway",
        "version":        env!("CARGO_PKG_VERSION"),
        "ws_connections": ws_connections,
    }))
}

/// GET /metrics â€” Prometheus text exposition format.
/// Scraped by Prometheus every 15s (configured in prometheus.yml).
pub async fn prometheus_metrics() -> Response {
    match azile_telemetry::metrics::render_metrics() {
        Ok(body) => (
            StatusCode::OK,
            [(header::CONTENT_TYPE, "text/plain; version=0.0.4; charset=utf-8")],
            body,
        )
            .into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
    }
}
