use std::collections::HashSet;
use std::sync::Arc;

use anyhow::Result;
use tracing::{info, instrument, warn};
use uuid::Uuid;

use contracts::mdm::{
    common::MetadataMap,
    entity::CanonicalEntity,
    matching::{BlockingDiagnostics, MatchRequest},
};

use crate::db::repositories::matching_repository::MatchingRepository;
use crate::matching::blocking::{
    BlockingStrategy,
    canopy::CanopyBlocker,
    phonetics::PhoneticBlocker,
    vector_blocking::VectorBlocker,
};
use crate::matching::models::{BlockingResult, CandidateEntity, CandidateSource};

pub struct CandidateGenerator {
    repository: Arc<MatchingRepository>,
    strategies: Vec<Arc<dyn BlockingStrategy>>,
}

impl CandidateGenerator {
    pub fn new(repository: Arc<MatchingRepository>) -> Self {
        // Default strategy stack: exact-key lookup + phonetic + canopy + vector.
        // Exact-key blocking is handled inline (email, phone, tax_id etc.) before
        // the strategy loop because it uses the same repository method.
        let strategies: Vec<Arc<dyn BlockingStrategy>> = vec![
            Arc::new(PhoneticBlocker::new(Arc::clone(&repository))),
            Arc::new(CanopyBlocker::new(Arc::clone(&repository))),
            Arc::new(VectorBlocker),
        ];

        Self {
            repository,
            strategies,
        }
    }

    /// Build from a custom strategy list (useful for tests and future config-driven setup).
    #[allow(dead_code)]
    pub fn with_strategies(
        repository: Arc<MatchingRepository>,
        strategies: Vec<Arc<dyn BlockingStrategy>>,
    ) -> Self {
        Self { repository, strategies }
    }

    #[instrument(skip(self, request))]
    pub async fn generate_candidates(
        &self,
        request: &MatchRequest,
    ) -> Result<BlockingResult> {
        let mut candidate_ids  = HashSet::<Uuid>::new();
        let mut generated_keys = Vec::<String>::new();
        let mut applied_rules  = Vec::<String>::new();

        // ---- exact-key blocking (email, phone, tax_id, customer_id, vendor_id) ----
        let exact_keys = generate_exact_keys(&request.entity);
        if !exact_keys.is_empty() {
            generated_keys.extend(exact_keys.clone());
            applied_rules.push("deterministic".to_string());

            let exact_matches = self
                .repository
                .find_by_blocking_keys(request.tenant_id, &exact_keys, request.max_candidates)
                .await?;
            candidate_ids.extend(exact_matches);
        }

        // ---- pluggable strategies ----
        for strategy in &self.strategies {
            // Vector blocking is only invoked when the request opts in.
            if strategy.name() == "vector" && !request.semantic_matching {
                continue;
            }

            match strategy.find_candidates(request.tenant_id, &request.entity).await {
                Ok(ids) => {
                    applied_rules.push(strategy.name().to_string());
                    candidate_ids.extend(ids);
                }
                Err(e) => {
                    warn!(
                        strategy = strategy.name(),
                        error = %e,
                        "blocking strategy failed; continuing with other strategies"
                    );
                }
            }
        }

        // Remove the source entity itself from candidates.
        candidate_ids.remove(&request.entity.entity_id);

        if candidate_ids.len() > request.max_candidates {
            candidate_ids = candidate_ids
                .into_iter()
                .take(request.max_candidates)
                .collect();
        }

        info!(
            tenant_id = %request.tenant_id,
            generated_candidates = %candidate_ids.len(),
            strategies = ?applied_rules,
            "candidate generation completed"
        );

        Ok(BlockingResult {
            candidate_ids: candidate_ids.clone(),
            diagnostics: BlockingDiagnostics {
                applied_rules,
                generated_keys,
                reduced_candidates: candidate_ids.len(),
                metadata: MetadataMap::new(),
            },
        })
    }

    #[instrument(skip(self))]
    pub async fn load_entities(
        &self,
        tenant_id: Uuid,
        candidate_ids: &HashSet<Uuid>,
    ) -> Result<Vec<CandidateEntity>> {
        let entities = self
            .repository
            .load_entities(tenant_id, candidate_ids)
            .await?;

        Ok(entities
            .into_iter()
            .map(|entity| CandidateEntity {
                entity,
                blocking_score: 1.0,
                candidate_source: CandidateSource::Blocking,
                vector_similarity: None,
                graph_similarity: None,
            })
            .collect())
    }
}

/// Generates exact-match blocking keys for high-precision deterministic fields.
/// Extracted as a free function so it can be reused without an instance.
fn generate_exact_keys(entity: &CanonicalEntity) -> Vec<String> {
    let mut keys = Vec::new();

    for attr in &entity.attributes {
        let field = attr.key.to_lowercase();
        let value = attr.value.as_str().unwrap_or("").trim().to_lowercase();

        if value.is_empty() {
            continue;
        }

        match field.as_str() {
            "email"       => keys.push(format!("EMAIL:{value}")),
            "phone"       => keys.push(format!("PHONE:{}", value.replace('-', ""))),
            "tax_id"      => keys.push(format!("TAX:{value}")),
            "customer_id" => keys.push(format!("CID:{value}")),
            "vendor_id"   => keys.push(format!("VID:{value}")),
            _             => {}
        }
    }

    keys
}
