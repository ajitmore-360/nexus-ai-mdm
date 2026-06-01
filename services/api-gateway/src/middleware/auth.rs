use axum::{
    http::Request,
    middleware::Next,
    response::Response,
};

//
// ========================================
// AUTH MIDDLEWARE
// ========================================
//

pub async fn auth_middleware(
    request: Request<axum::body::Body>,
    next: Next,
) -> Response {

    // TODO:
    // - JWT validation
    // - API key validation
    // - OAuth2
    // - RBAC
    // - policy enforcement

    next.run(request).await
}