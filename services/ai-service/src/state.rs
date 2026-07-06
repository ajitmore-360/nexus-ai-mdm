use std::sync::Arc;
use std::time::{Duration, Instant};

use dashmap::DashMap;
use sqlx::PgPool;
use tracing::warn;
use uuid::Uuid;

use crate::embeddings::Encoder;
use crate::feedback::FeedbackProcessor;
use crate::llm::OllamaClient;
use crate::matching::SemanticMatcher;
use crate::rag::RagPipeline;

/// Per-user injection attempt tracker: user_id/IP → (count, window_start).
/// Entries older than the window are reset on the next check.
type InjectionTracker = Arc<DashMap<String, (u32, Instant)>>;

const INJECTION_WINDOW:   Duration = Duration::from_secs(60);
const INJECTION_MAX_HITS: u32      = 5;

/// Shared application state injected into every Axum handler.
#[derive(Clone)]
pub struct AppState {
    pub pool:              PgPool,
    pub llm:               Arc<OllamaClient>,
    pub encoder:           Arc<Encoder>,
    pub rag_pipeline:      Arc<RagPipeline>,
    pub semantic_matcher:  Arc<SemanticMatcher>,
    pub feedback:          Arc<FeedbackProcessor>,
    /// Tracks prompt injection attempts per user/IP for rate-limiting.
    pub injection_tracker: InjectionTracker,
}

impl AppState {
    /// Record a prompt injection attempt for the given key (user_id or IP).
    /// Returns `true` if the rate limit has been exceeded — caller should block.
    pub fn record_injection_attempt(&self, key: &str) -> bool {
        let now = Instant::now();
        let mut entry = self.injection_tracker.entry(key.to_string()).or_insert((0, now));
        if now.duration_since(entry.1) > INJECTION_WINDOW {
            *entry = (1, now);
            false
        } else {
            entry.0 += 1;
            entry.0 > INJECTION_MAX_HITS
        }
    }
}

impl AppState {
    /// Fetch the tenant's display name from core_mdm.tenants.
    ///
    /// Results are NOT cached here — callers that need high-frequency access
    /// should use the Redis EntityCache.  Falls back to the tenant UUID string
    /// on any DB error so the copilot always returns a response.
    pub async fn tenant_name(&self, tenant_id: Uuid) -> String {
        match sqlx::query_scalar::<_, String>(
            "SELECT tenant_name FROM core_mdm.tenants WHERE tenant_id = $1",
        )
        .bind(tenant_id)
        .fetch_optional(&self.pool)
        .await
        {
            Ok(Some(name)) => name,
            Ok(None) => {
                warn!(%tenant_id, "tenant not found; using UUID as name");
                tenant_id.to_string()
            }
            Err(e) => {
                warn!(error=%e, %tenant_id, "tenant name lookup failed; using UUID as name");
                tenant_id.to_string()
            }
        }
    }
}
