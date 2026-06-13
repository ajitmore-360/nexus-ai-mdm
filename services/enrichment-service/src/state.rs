use std::sync::Arc;
use crate::enricher::EnrichmentOrchestrator;

#[derive(Clone)]
pub struct AppState {
    pub orchestrator: Arc<EnrichmentOrchestrator>,
}
