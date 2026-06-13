use std::sync::Arc;

use sqlx::PgPool;
use tracing::warn;
use uuid::Uuid;

use crate::embeddings::Encoder;
use crate::feedback::FeedbackProcessor;
use crate::llm::OllamaClient;
use crate::matching::SemanticMatcher;
use crate::rag::RagPipeline;

/// Shared application state injected into every Axum handler.
#[derive(Clone)]
pub struct AppState {
    pub pool:             PgPool,
    pub llm:              Arc<OllamaClient>,
    pub encoder:          Arc<Encoder>,
    pub rag_pipeline:     Arc<RagPipeline>,
    pub semantic_matcher: Arc<SemanticMatcher>,
    pub feedback:         Arc<FeedbackProcessor>,
}

impl AppState {
    /// Fetch the tenant's display name from core_mdm.tenants.
    ///
    /// Results are NOT cached here — callers that need high-frequency access
    /// should use the Redis EntityCache.  Falls back to the tenant UUID string
    /// on any DB error so the copilot always returns a response.
    pub async fn tenant_name(&self, tenant_id: Uuid) -> String {
        match sqlx::query_scalar::<_, String>(
            "SELECT display_name FROM core_mdm.tenants WHERE tenant_id = $1",
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
