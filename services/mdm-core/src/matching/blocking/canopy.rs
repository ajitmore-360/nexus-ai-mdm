use std::collections::HashSet;
use std::sync::Arc;

use async_trait::async_trait;
use uuid::Uuid;

use contracts::mdm::entity::CanonicalEntity;

use crate::db::repositories::matching_repository::MatchingRepository;
use crate::matching::blocking::strategy::BlockingStrategy;

/// Canopy-cluster blocking: generates token-based blocking keys from name and
/// address fields and looks up candidates that share significant tokens.
///
/// This is a lightweight substitute for true canopy clustering until the
/// background canopy-center maintenance job is implemented (Phase 2 AI track).
pub struct CanopyBlocker {
    repository: Arc<MatchingRepository>,
}

impl CanopyBlocker {
    pub fn new(repository: Arc<MatchingRepository>) -> Self {
        Self { repository }
    }

    fn token_keys(entity: &CanonicalEntity) -> Vec<String> {
        let mut keys = Vec::new();

        for attr in &entity.attributes {
            let field = attr.key.to_lowercase();
            if !matches!(
                field.as_str(),
                "name" | "company_name" | "legal_name" | "first_name" | "last_name"
            ) {
                continue;
            }

            let value = attr.value.as_str().unwrap_or("").trim().to_lowercase();
            if value.is_empty() {
                continue;
            }

            // Each significant token (≥3 chars) becomes an independent key so
            // partial-name overlaps still produce candidates.
            for token in value.split_whitespace() {
                let t = token.trim_matches(|c: char| !c.is_alphanumeric());
                if t.len() >= 3 {
                    keys.push(format!("PHONETIC:{t}"));
                }
            }
        }

        keys
    }
}

#[async_trait]
impl BlockingStrategy for CanopyBlocker {
    fn name(&self) -> &'static str {
        "canopy"
    }

    async fn find_candidates(
        &self,
        tenant_id: Uuid,
        entity: &CanonicalEntity,
    ) -> anyhow::Result<HashSet<Uuid>> {
        let keys = Self::token_keys(entity);

        if keys.is_empty() {
            return Ok(HashSet::new());
        }

        let candidates = self
            .repository
            .find_by_blocking_keys(tenant_id, &keys, 500)
            .await?;

        Ok(candidates)
    }
}
