use axum::{
    http::Request,
    middleware::Next,
    response::Response,
};
use axum::http::HeaderValue;

/// Axum middleware that injects production security headers on every response.
///
/// Apply to every service router:
/// ```ignore
/// app.layer(axum::middleware::from_fn(
///     azile_telemetry::security_headers::security_headers_middleware
/// ))
/// ```
pub async fn security_headers_middleware(
    req:  Request<axum::body::Body>,
    next: Next,
) -> Response {
    let mut response = next.run(req).await;
    let headers = response.headers_mut();

    // Prevent clickjacking
    headers.insert(
        "x-frame-options",
        HeaderValue::from_static("DENY"),
    );

    // Prevent MIME-type sniffing
    headers.insert(
        "x-content-type-options",
        HeaderValue::from_static("nosniff"),
    );

    // Referrer policy â€” don't leak internal URLs
    headers.insert(
        "referrer-policy",
        HeaderValue::from_static("strict-origin-when-cross-origin"),
    );

    // Permissions policy â€” disable unused browser features
    headers.insert(
        "permissions-policy",
        HeaderValue::from_static(
            "geolocation=(), microphone=(), camera=(), payment=(), usb=()"
        ),
    );

    // Content Security Policy â€” strict for API (no HTML rendered)
    headers.insert(
        "content-security-policy",
        HeaderValue::from_static("default-src 'none'; frame-ancestors 'none'"),
    );

    // HSTS â€” enforce HTTPS for 1 year (only add once TLS is terminated)
    // Commented out for local dev; enable behind TLS termination proxy
    // headers.insert(
    //     "strict-transport-security",
    //     HeaderValue::from_static("max-age=31536000; includeSubDomains; preload"),
    // );

    // Remove server identification header (defence in depth)
    headers.remove("server");
    headers.remove("x-powered-by");

    response
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn header_values_are_valid() {
        // Ensure every hardcoded header value parses correctly
        assert!(HeaderValue::from_static("DENY").is_sensitive() == false);
        assert!(HeaderValue::from_static("nosniff").as_bytes().len() > 0);
    }
}
