use std::collections::HashSet;

use async_trait::async_trait;
use uuid::Uuid;

use contracts::mdm::entity::CanonicalEntity;

/// A pluggable blocking strategy that, given a source entity, returns candidate
/// entity IDs from the same tenant that should be scored against it.
///
/// Implementations live in sub-modules (phonetics, canopy, vector_blocking).
/// `CandidateGenerator` holds a `Vec<Arc<dyn BlockingStrategy>>` and calls
/// each in turn, merging results into a deduplicated `HashSet<Uuid>`.
#[async_trait]
pub trait BlockingStrategy: Send + Sync {
    fn name(&self) -> &'static str;

    /// `fields` — when `Some`, restricts blocking to those attribute keys only.
    /// `None` means use the strategy's built-in default field list.
    async fn find_candidates(
        &self,
        tenant_id: Uuid,
        entity: &CanonicalEntity,
        fields: Option<&[String]>,
    ) -> anyhow::Result<HashSet<Uuid>>;
}
