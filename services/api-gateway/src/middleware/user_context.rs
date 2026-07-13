use std::net::SocketAddr;
use axum::{extract::{ConnectInfo, Request}, http::header::{HeaderName, HeaderValue}, middleware::Next, response::Response};

/// Reads `Claims` from request extensions (injected by auth_middleware) and
/// injects `x-user-id` + `x-user-role` headers so downstream services that
/// communicate via service-to-service bearer tokens can reconstruct user identity.
///
/// Also injects `x-real-ip` from the verified TCP peer address (ConnectInfo)
/// and strips `x-forwarded-for` to prevent client IP spoofing on downstream
/// services that trust that header (e.g. mdm-core login rate limiter).
///
/// No-op on Claims when AUTH_DISABLED=true (no Claims present).
pub async fn inject_user_context(mut request: Request, next: Next) -> Response {
    // Strip x-forwarded-for — it is client-controlled and must not reach
    // downstream services that would use it for rate limiting or audit.
    request.headers_mut().remove("x-forwarded-for");

    // Inject the real TCP peer IP so downstream services have a trustworthy source.
    let real_ip = request
        .extensions()
        .get::<ConnectInfo<SocketAddr>>()
        .map(|ci| ci.0.ip().to_string())
        .or_else(|| {
            request.headers()
                .get("x-real-ip")
                .and_then(|v| v.to_str().ok())
                .map(str::to_owned)
        });

    if let Some(ip) = real_ip {
        if let Ok(v) = HeaderValue::from_str(&ip) {
            request.headers_mut().insert(HeaderName::from_static("x-real-ip"), v);
        }
    }

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
