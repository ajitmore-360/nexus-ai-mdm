pub mod address;
pub mod dnb;
pub mod experian;

use std::collections::HashMap;

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// A flattened view of an entity sufficient for all enrichment providers.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnrichmentRequest {
    /// The MDM entity_id being enriched.
    pub entity_id: Uuid,

    /// Tenant that owns the entity.
    pub tenant_id: Uuid,

    /// Entity type string, e.g. "Customer", "Vendor", "Location".
    pub entity_type: String,

    /// Key/value attribute bag extracted from the canonical entity.
    /// Values are raw JSON (strings, numbers, objects).
    pub attributes: serde_json::Value,
}

/// Enrichment result produced by a single provider.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnrichmentData {
    /// Name of the provider that produced this data, e.g. "DunBradstreet".
    pub provider: String,

    /// New or updated attribute key/value pairs to be merged into the entity.
    pub fields: HashMap<String, serde_json::Value>,

    /// Provider-assigned confidence in the match/enrichment (0.0 – 1.0).
    pub confidence: f32,

    /// When the enrichment was performed.
    pub enriched_at: DateTime<Utc>,
}

/// Trait every enrichment provider must implement.
#[async_trait]
pub trait EnrichmentProvider: Send + Sync {
    /// Human-readable provider name.
    fn name(&self) -> &str;

    /// Return true when this provider should run for the given request.
    fn applies_to(&self, req: &EnrichmentRequest) -> bool;

    /// Perform the enrichment and return populated fields.
    async fn enrich(&self, req: &EnrichmentRequest) -> anyhow::Result<EnrichmentData>;
}

// ── shared utility ────────────────────────────────────────────────────────────

/// Extract a string attribute from the request attribute bag.
pub fn attr_str<'a>(attrs: &'a serde_json::Value, key: &str) -> Option<&'a str> {
    attrs.get(key).and_then(|v| v.as_str())
}

/// Simple djb2-style hash over a string — deterministic, no external deps.
/// Used by mock providers to derive realistic-looking values from entity name.
pub fn name_hash(s: &str) -> u64 {
    let mut h: u64 = 5381;
    for b in s.bytes() {
        h = h.wrapping_mul(33).wrapping_add(b as u64);
    }
    h
}
