use anyhow::Result;
use uuid::Uuid;

use contracts::mdm::entity::CanonicalEntity;
use contracts::mdm::golden_record::GoldenRecord;
use contracts::mdm::survivorship::SurvivorshipRule;

use crate::db::repositories::survivorship_repository::SurvivorshipRepository;
use crate::survivorship::engine::apply_survivorship;

/// Service that applies survivorship rules to a set of entities and produces
/// a `GoldenRecord`.  Rules can be supplied inline by the caller or loaded
/// from the tenant's persisted rule definitions.
pub struct SurvivorshipService {
    survivorship_repository: std::sync::Arc<SurvivorshipRepository>,
}

impl SurvivorshipService {
    pub fn new(survivorship_repository: std::sync::Arc<SurvivorshipRepository>) -> Self {
        Self { survivorship_repository }
    }

    /// Apply the provided rules to the entity set and return the resulting
    /// golden record.
    pub async fn apply(
        &self,
        entities: Vec<CanonicalEntity>,
        rules:    Vec<SurvivorshipRule>,
    ) -> Result<GoldenRecord> {
        if entities.is_empty() {
            return Err(anyhow::anyhow!("survivorship requires at least one entity"));
        }
        Ok(apply_survivorship(entities, rules))
    }

    /// Load persisted survivorship rules for a tenant and entity type, then
    /// apply them.
    pub async fn apply_with_persisted_rules(
        &self,
        tenant_id:   Uuid,
        entity_type: &str,
        entities:    Vec<CanonicalEntity>,
    ) -> Result<GoldenRecord> {
        let rules = self
            .survivorship_repository
            .fetch_rules_for_entity_type(tenant_id, entity_type)
            .await?;

        self.apply(entities, rules).await
    }
}
