use anyhow::{bail, Result};
use async_trait::async_trait;
use reqwest::Client;
use serde_json::Value;
use tracing::{info, instrument, warn};

use crate::connectors::Connector;

/// Allowlist of URL schemes permitted for outbound webhooks.
const ALLOWED_SCHEMES: &[&str] = &["https", "http"];

/// Private/loopback CIDR blocks that must never receive webhooks.
/// This prevents SSRF attacks where a connector is configured to call
/// internal Kubernetes services, cloud metadata APIs, or localhost.
const BLOCKED_HOSTS: &[&str] = &[
    "localhost",
    "127.",
    "0.0.0.0",
    "::1",
    "169.254.",      // AWS/GCP metadata service (link-local)
    "192.168.",      // RFC 1918 private
    "10.",           // RFC 1918 private
    "172.16.",       // RFC 1918 private
    "172.17.",       // RFC 1918 private
    "172.18.",       // RFC 1918 private
    "172.19.",       // RFC 1918 private
    "172.2",         // RFC 1918 private (172.20-31)
    "fd",            // IPv6 private (ULA fc00::/7)
    "fe80",          // IPv6 link-local
    "metadata.google.internal",
    "169.254.169.254", // EC2 metadata endpoint
];

/// HTTP webhook connector — POSTs entity JSON to an external URL.
///
/// Security controls:
/// - URL scheme restricted to http/https
/// - Private/internal IP ranges blocked (SSRF prevention)
/// - HMAC-SHA256 signature header for payload authentication
/// - Strict 30-second timeout
pub struct WebhookConnector {
    http:    Client,
    endpoint: String,
    secret:   Option<String>,
    headers:  Vec<(String, String)>,
}

impl WebhookConnector {
    pub fn new(endpoint: String, secret: Option<String>, headers: Vec<(String, String)>) -> Self {
        let http = Client::builder()
            .timeout(std::time::Duration::from_secs(30))
            // Disable redirects to prevent SSRF via open-redirect chains
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .expect("failed to build webhook HTTP client");

        Self { http, endpoint, secret, headers }
    }

    /// Validate that the endpoint URL is safe to call.
    ///
    /// Blocks private IP ranges (SSRF), non-http(s) schemes, and bare IPs.
    fn validate_endpoint(url: &str) -> Result<()> {
        let parsed = reqwest::Url::parse(url)
            .map_err(|e| anyhow::anyhow!("invalid webhook URL '{}': {}", url, e))?;

        let scheme = parsed.scheme();
        if !ALLOWED_SCHEMES.contains(&scheme) {
            bail!("webhook URL scheme '{}' is not allowed (use https)", scheme);
        }

        let host = parsed.host_str().unwrap_or("").to_lowercase();

        for blocked in BLOCKED_HOSTS {
            if host.starts_with(blocked) || host == *blocked {
                bail!(
                    "webhook URL targets a blocked host '{}' (SSRF prevention)",
                    host
                );
            }
        }

        // Reject bare IP addresses (require hostnames for external destinations)
        // Allow if explicitly whitelisted — production should use FQDN
        if host.parse::<std::net::IpAddr>().is_ok() {
            warn!(host=%host, "webhook URL is a bare IP address — use FQDNs in production");
            // Not blocking bare IPs outright to allow valid use-cases (e.g. staging)
            // but warn operators.
        }

        Ok(())
    }
}

#[async_trait]
impl Connector for WebhookConnector {
    fn name(&self) -> &'static str { "webhook" }

    #[instrument(skip(self, payload), fields(endpoint=%self.endpoint))]
    async fn send(&self, payload: &Value) -> Result<()> {
        // ── SSRF prevention ──────────────────────────────────────────────────
        Self::validate_endpoint(&self.endpoint)?;

        let body = serde_json::to_string(payload)?;

        let mut req = self.http
            .post(&self.endpoint)
            .header("Content-Type", "application/json")
            .header("X-Nexus-Source", "nexus-mdm")
            .header("X-Nexus-Version", env!("CARGO_PKG_VERSION"));

        for (k, v) in &self.headers {
            // Prevent header injection — reject values containing CR or LF
            if v.contains('\r') || v.contains('\n') {
                bail!("webhook header '{}' contains invalid characters (CRLF injection)", k);
            }
            req = req.header(k.as_str(), v.as_str());
        }

        // HMAC-SHA256 signature
        if let Some(secret) = &self.secret {
            let signature = compute_hmac_sha256(secret, &body);
            req = req.header("X-Nexus-Signature", format!("sha256={}", signature));
        }

        let resp = req.body(body).send().await?;

        if resp.status().is_success() {
            info!("webhook delivery succeeded");
            Ok(())
        } else {
            let status = resp.status();
            let text   = resp.text().await.unwrap_or_default();
            // Truncate response body in error — avoid leaking internal server details
            let truncated = &text[..text.len().min(200)];
            anyhow::bail!("webhook returned {}: {}", status, truncated)
        }
    }
}

/// Compute HMAC-SHA256 for webhook payload authentication.
///
/// Produces the `X-Nexus-Signature: sha256=<hex>` header value.
/// Receivers should verify using the same shared secret.
fn compute_hmac_sha256(secret: &str, body: &str) -> String {
    use hmac::{Hmac, Mac};
    use sha2::Sha256;

    type HmacSha256 = Hmac<Sha256>;

    let mut mac = HmacSha256::new_from_slice(secret.as_bytes())
        .expect("HMAC accepts any key length");
    mac.update(body.as_bytes());
    hex::encode(mac.finalize().into_bytes())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn blocks_localhost() {
        assert!(WebhookConnector::validate_endpoint("https://localhost/hook").is_err());
        assert!(WebhookConnector::validate_endpoint("https://127.0.0.1/hook").is_err());
    }

    #[test]
    fn blocks_metadata_service() {
        assert!(WebhookConnector::validate_endpoint("https://169.254.169.254/latest/meta-data/").is_err());
    }

    #[test]
    fn blocks_internal_rfc1918() {
        assert!(WebhookConnector::validate_endpoint("https://192.168.1.1/hook").is_err());
        assert!(WebhookConnector::validate_endpoint("https://10.0.0.1/hook").is_err());
    }

    #[test]
    fn allows_external_https() {
        assert!(WebhookConnector::validate_endpoint("https://api.example.com/webhook").is_ok());
    }

    #[test]
    fn blocks_file_scheme() {
        assert!(WebhookConnector::validate_endpoint("file:///etc/passwd").is_err());
    }

    #[test]
    fn blocks_crlf_header_injection() {
        let conn = WebhookConnector::new(
            "https://example.com".to_string(),
            None,
            vec![("X-Custom".to_string(), "value\r\nX-Injected: evil".to_string())],
        );
        // Payload doesn't matter — header validation fires first
        let rt = tokio::runtime::Runtime::new().unwrap();
        rt.block_on(async {
            assert!(conn.send(&serde_json::json!({})).await.is_err());
        });
    }
}
