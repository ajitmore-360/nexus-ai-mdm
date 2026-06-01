use axum::{
    http::Request,
    middleware::Next,
    response::Response,
};

use uuid::Uuid;

//
// ========================================
// REQUEST LOGGING
// ========================================
//

pub async fn logging_middleware(
    mut request: Request<axum::body::Body>,
    next: Next,
) -> Response {

    let correlation_id = Uuid::new_v4().to_string();

    request.headers_mut().insert(
        "x-correlation-id",
        correlation_id.parse().unwrap(),
    );

    println!(
        "Incoming request: {} {}",
        request.method(),
        request.uri(),
    );

    next.run(request).await
}