use axum::{
    http::Request,
    middleware::Next,
    response::Response,
};
use uuid::Uuid;

pub async fn logging_middleware(
    mut request: Request<axum::body::Body>,
    next: Next,
) -> Response {
    let correlation_id = Uuid::new_v4().to_string();

    if let Ok(val) = correlation_id.parse() {
        request.headers_mut().insert("x-correlation-id", val);
    }

    tracing::info!(
        method = %request.method(),
        uri    = %request.uri(),
        "incoming request"
    );

    next.run(request).await
}
