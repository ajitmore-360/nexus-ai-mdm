use axum::{extract::Request, http::header::{HeaderName, HeaderValue}, middleware::Next, response::Response};

/// Reads `Claims` from request extensions (injected by auth_middleware) and
/// injects `x-user-id` + `x-user-role` headers so downstream services that
/// communicate via service-to-service bearer tokens can reconstruct user identity.
///
/// No-op when AUTH_DISABLED=true (no Claims present).
pub async fn inject_user_context(mut request: Request, next: Next) -> Response {
    if let Some(claims) = request.extensions().get::<azile_auth::Claims>().cloned() {
        let headers = request.headers_mut();

        if let Ok(v) = HeaderValue::from_str(&claims.sub) {
            headers.insert(HeaderName::from_static("x-user-id"), v);
        }

        let role_str = claims.nxs_role.to_string();
        if let Ok(v) = HeaderValue::from_str(&role_str) {
            headers.insert(HeaderName::from_static("x-user-role"), v);
        }
    }

    next.run(request).await
}
