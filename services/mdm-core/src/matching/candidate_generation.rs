use std::collections::{HashMap, HashSet};
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
            Arc::new(VectorBlocker::new(repository.pool.clone())),
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

        // Parse blocking_rules into strategy → fields map.
        // None means "run all strategies with their built-in default fields".
        let rules_map: Option<HashMap<String, Vec<String>>> = if request.blocking_rules.is_empty() {
            None
        } else {
            Some(parse_blocking_rules(&request.blocking_rules))
        };

        // ---- exact-key blocking (email, phone, tax_id, customer_id, vendor_id) ----
        let run_exact = rules_map.as_ref().map_or(true, |m| m.contains_key("exact"));
        if run_exact {
            let exact_fields = rules_map.as_ref()
                .and_then(|m| m.get("exact"))
                .filter(|v| !v.is_empty())
                .map(|v| v.as_slice());
            let exact_keys = generate_exact_keys(&request.entity, exact_fields);
            if !exact_keys.is_empty() {
                generated_keys.extend(exact_keys.clone());
                applied_rules.push("deterministic".to_string());
                let exact_matches = self
                    .repository
                    .find_by_blocking_keys(request.tenant_id, &exact_keys, request.max_candidates)
                    .await?;
                candidate_ids.extend(exact_matches);
            }
        }

        // ---- pluggable strategies ----
        for strategy in &self.strategies {
            // Vector blocking is only invoked when the request opts in.
            if strategy.name() == "vector" && !request.semantic_matching {
                continue;
            }

            // When rules are configured, skip strategies not listed.
            let fields_opt: Option<&[String]> = if let Some(ref rules) = rules_map {
                match rules.get(strategy.name()) {
                    None => continue,
                    Some(f) if f.is_empty() => None,  // listed but no field filter → defaults
                    Some(f) => Some(f.as_slice()),
                }
            } else {
                None
            };

            match strategy.find_candidates(request.tenant_id, &request.entity, fields_opt).await {
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

/// Parse "strategy:field" or bare "strategy" tokens into a map of strategy → fields.
/// An empty Vec for a key means "run this strategy with its default field list".
fn parse_blocking_rules(rules: &[String]) -> HashMap<String, Vec<String>> {
    let mut map: HashMap<String, Vec<String>> = HashMap::new();
    for rule in rules {
        let rule = rule.trim().to_lowercase();
        if let Some((strat, field)) = rule.split_once(':') {
            map.entry(strat.to_string()).or_default().push(field.to_string());
        } else {
            map.entry(rule).or_default();
        }
    }
    map
}

/// Generates exact-match blocking keys for high-precision deterministic fields.
/// `fields` — when `Some`, only emit keys for those attribute names; `None` uses
/// the built-in defaults (email, phone, tax_id, customer_id, vendor_id).
fn generate_exact_keys(entity: &CanonicalEntity, fields: Option<&[String]>) -> Vec<String> {
    let allowed: Option<HashSet<&str>> = fields.map(|f| f.iter().map(|s| s.as_str()).collect());
    let mut keys = Vec::new();

    for attr in &entity.attributes {
        let field = attr.key.to_lowercase();
        if let Some(ref a) = allowed {
            if !a.contains(field.as_str()) {
                continue;
            }
        }

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
