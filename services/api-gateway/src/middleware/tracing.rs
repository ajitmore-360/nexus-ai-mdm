use axum::{
    http::Request,
    middleware::Next,
    response::Response,
};

use tracing::{
    info,
    error,
};

use std::time::Instant;

//
// =========================================
// REQUEST TRACING
// =========================================
//

#[allow(dead_code)]
pub async fn tracing_middleware(
    req: Request<axum::body::Body>,
    next: Next,
) -> Response {

    let method = req.method().clone();
    let path = req.uri().path().to_string();

    let request_id = req
        .headers()
        .get("x-request-id")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("unknown")
        .to_string();

    let started = Instant::now();

    info!(
        request_id = %request_id,
        method = %method,
        path = %path,
        "incoming request"
    );

    let response = next.run(req).await;

    let elapsed = started.elapsed().as_millis();

    let status = response.status();

    if status.is_server_error() {

        error!(
            request_id = %request_id,
            method = %method,
            path = %path,
            status = %status,
            elapsed_ms = elapsed,
            "request failed"
        );

    } else {

        info!(
            request_id = %request_id,
            method = %method,
            path = %path,
            status = %status,
            elapsed_ms = elapsed,
            "request completed"
        );
    }

    response
}