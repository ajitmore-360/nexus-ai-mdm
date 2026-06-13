use std::collections::HashSet;

use async_trait::async_trait;
use tracing::debug;
use uuid::Uuid;

use contracts::mdm::entity::CanonicalEntity;

use crate::matching::blocking::strategy::BlockingStrategy;

/// pgvector-based semantic blocking.
///
/// When an entity arrives with a pre-computed embedding (stored in the
/// `ai.entity_embeddings` table), this blocker performs an approximate nearest-
/// neighbour search to surface semantically similar candidates that exact or
/// phonetic blocking would miss.
///
/// The embedding lookup and ANN query are left as TODO markers until the
/// embedding pipeline (ai-service → `ai.entity_embeddings`) is wired up.
/// Until then this blocker logs a debug note and returns an empty set, which
/// is non-critical: phonetic + canopy blocking still run.
pub struct VectorBlocker;

#[async_trait]
impl BlockingStrategy for VectorBlocker {
    fn name(&self) -> &'static str {
        "vector"
    }

    async fn find_candidates(
        &self,
        _tenant_id: Uuid,
        entity: &CanonicalEntity,
    ) -> anyhow::Result<HashSet<Uuid>> {
        // TODO: query ai.entity_embeddings for entity.entity_id, then run
        //   SELECT entity_id FROM ai.entity_embeddings
        //   ORDER BY embedding <=> $1 LIMIT 200
        // Replace this stub once the embedding pipeline is live.
        debug!(
            entity_id=%entity.entity_id,
            "vector blocking skipped: embedding pipeline not yet wired"
        );
        Ok(HashSet::new())
    }
}
