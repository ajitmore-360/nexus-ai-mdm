use std::time::Duration;

use reqwest::Client;
use tracing::{debug, instrument, warn};

use crate::models::{OpaInput, OpaResponse, PolicyContext, PolicyDecision};

/// Thin HTTP client around the OPA REST API.
///
/// Fail-open: if OPA is unreachable or returns an unexpected response, a
/// permissive decision is returned with a warning — availability > security
/// for the MDM data plane.  Security-critical denials should be handled by
/// an OPA sidecar with a liveness check.
pub struct OpaClient {
    http:     Client,
    base_url: String,
}

impl OpaClient {
    pub fn new(base_url: impl Into<String>, timeout_secs: u64) -> Self {
        let http = Client::builder()
            .timeout(Duration::from_secs(timeout_secs))
            .build()
            .expect("failed to build OPA HTTP client");

        Self {
            http,
            base_url: base_url.into(),
        }
    }

    /// Evaluate the policy at `policy_path` (e.g. `mdm/entity_access`) for
    /// the given context.  Returns `PolicyDecision::permissive` on transport
    /// or parse errors.
    #[instrument(skip(self, ctx), fields(policy_path=%policy_path))]
    pub async fn evaluate(
        &self,
        policy_path: &str,
        ctx:         &PolicyContext,
    ) -> PolicyDecision {
        let url = format!(
            "{}/v1/data/{}",
            self.base_url.trim_end_matches('/'),
            policy_path
        );

        let body = OpaInput { input: ctx.clone() };

        match self.http.post(&url).json(&body).send().await {
            Err(e) => {
                warn!(error=%e, "OPA unreachable; failing open");
                PolicyDecision::permissive("OPA unavailable — failing open")
            }
            Ok(resp) if !resp.status().is_success() => {
                warn!(status=%resp.status(), "OPA returned non-success; failing open");
                PolicyDecision::permissive("OPA returned error — failing open")
            }
            Ok(resp) => {
                match resp.json::<OpaResponse>().await {
                    Err(e) => {
                        warn!(error=%e, "failed to parse OPA response; failing open");
                        PolicyDecision::permissive("OPA response unparseable — failing open")
                    }
                    Ok(opa_resp) => {
                        match opa_resp.result {
                            None => {
                                // OPA returned undefined — fail open
                                debug!("OPA returned undefined result; allowing");
                                PolicyDecision::permissive("no policy defined — allowing")
                            }
                            Some(result) => PolicyDecision {
                                allowed:         result.allowed,
                                reason:          result.reason,
                                masked_fields:   result.masked_fields,
                                required_fields: result.required_fields,
                                warnings:        result.warnings,
                                applied_rules:   vec![policy_path.to_string()],
                            },
                        }
                    }
                }
            }
        }
    }

    pub async fn health_check(&self) -> bool {
        let url = format!("{}/health", self.base_url.trim_end_matches('/'));
        self.http.get(&url).send().await
            .map(|r| r.status().is_success())
            .unwrap_or(false)
    }
}
