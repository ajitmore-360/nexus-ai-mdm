pub mod webhook;

use anyhow::Result;
use async_trait::async_trait;
use serde_json::Value;

pub use webhook::WebhookConnector;

/// Common interface every distribution connector must implement.
#[async_trait]
pub trait Connector: Send + Sync {
    #[allow(dead_code)]
    fn name(&self) -> &'static str;
    async fn send(&self, payload: &Value) -> Result<()>;
}

/// Build a connector from stored connector config.
pub fn build_connector(
    connector_type: &str,
    endpoint_url:   Option<&str>,
    config:         &Value,
) -> Option<Box<dyn Connector>> {
    match connector_type {
        "webhook" | "http" => {
            let url     = endpoint_url?.to_string();
            let secret  = config.get("secret").and_then(|v| v.as_str()).map(str::to_owned);
            let headers = config
                .get("headers")
                .and_then(|v| v.as_object())
                .map(|m| m.iter().map(|(k, v)| (k.clone(), v.as_str().unwrap_or("").to_string())).collect())
                .unwrap_or_default();
            Some(Box::new(WebhookConnector::new(url, secret, headers)))
        }
        _ => {
            tracing::warn!(connector_type=%connector_type, "unknown connector type; skipping");
            None
        }
    }
}
