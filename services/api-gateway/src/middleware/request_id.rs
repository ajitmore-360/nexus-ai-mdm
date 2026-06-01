use axum::{
    http::{Request, HeaderValue},
    middleware::Next,
    response::Response,
};

use uuid::Uuid;

pub const REQUEST_ID_HEADER: &str = "x-request-id";

//
// =========================================
// REQUEST ID MIDDLEWARE
// =========================================
//

pub async fn request_id_middleware(
    mut req: Request<axum::body::Body>,
    next: Next,
) -> Response {

    // =====================================
    // EXISTING REQUEST ID
    // =====================================

    let request_id = req
        .headers()
        .get(REQUEST_ID_HEADER)
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string())
        .unwrap_or_else(|| Uuid::new_v4().to_string());

    // =====================================
    // STORE IN REQUEST
    // =====================================

    req.extensions_mut()
        .insert(request_id.clone());

    req.headers_mut().insert(
        REQUEST_ID_HEADER,
        HeaderValue::from_str(&request_id)
            .unwrap(),
    );

    // =====================================
    // CONTINUE
    // =====================================

    let mut response = next.run(req).await;

    // =====================================
    // RETURN HEADER
    // =====================================

    response.headers_mut().insert(
        REQUEST_ID_HEADER,
        HeaderValue::from_str(&request_id)
            .unwrap(),
    );

    response
}