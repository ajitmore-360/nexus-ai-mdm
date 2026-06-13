use std::collections::HashSet;
use std::sync::Arc;

use async_trait::async_trait;
use uuid::Uuid;

use contracts::mdm::entity::CanonicalEntity;

use crate::db::repositories::matching_repository::MatchingRepository;
use crate::matching::blocking::strategy::BlockingStrategy;

pub struct PhoneticBlocker {
    repository: Arc<MatchingRepository>,
}

impl PhoneticBlocker {
    pub fn new(repository: Arc<MatchingRepository>) -> Self {
        Self { repository }
    }

    pub fn generate_keys(entity: &CanonicalEntity) -> Vec<String> {
        let mut keys = Vec::new();

        for attr in &entity.attributes {
            let field = attr.key.to_lowercase();
            if !matches!(field.as_str(), "name" | "company_name" | "legal_name") {
                continue;
            }

            let value = attr.value.as_str().unwrap_or("").trim().to_lowercase();
            if value.is_empty() {
                continue;
            }

            keys.push(format!("PHONETIC:{value}"));
        }

        keys
    }
}

#[async_trait]
impl BlockingStrategy for PhoneticBlocker {
    fn name(&self) -> &'static str {
        "phonetic"
    }

    async fn find_candidates(
        &self,
        tenant_id: Uuid,
        entity: &CanonicalEntity,
    ) -> anyhow::Result<HashSet<Uuid>> {
        let keys = Self::generate_keys(entity);

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
