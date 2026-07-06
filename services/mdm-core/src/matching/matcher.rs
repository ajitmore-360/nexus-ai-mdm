use std::sync::{Arc, RwLock};
use std::time::Instant;

use anyhow::Result;
use chrono::Utc;
use tracing::{info, instrument, warn};

use crate::matching::models::MATCH_ENGINE_VERSION;
use contracts::mdm::{
    common::{AuditMetadata, MetadataMap, VersionInfo},
    matching::{
        MatchCandidate, MatchExecutionMetadata, MatchRequest, MatchResponse, MatchStatus,
    },
};

use crate::db::repositories::matching_repository::MatchingRepository;
use crate::matching::candidate_generation::CandidateGenerator;
use crate::matching::clustering::cluster_builder::ClusterBuilder;
use crate::matching::models::MatchResult;
use crate::matching::policy::MatchingPolicy;
use crate::matching::review::review_engine::ReviewEngine;
use crate::matching::scoring::score_calculator::ScoreCalculator;
use crate::matching::semantic_client::{SemanticClient, SemanticDecision};

pub struct Matcher {
    candidate_generator: Arc<CandidateGenerator>,
    repository:          Arc<MatchingRepository>,
    review_engine:       Arc<ReviewEngine>,
    /// Shared live policy — wrapped in RwLock so PATCH /policy/weights
    /// takes effect on the next match execution without restarting the service.
    policy: Arc<RwLock<MatchingPolicy>>,
    /// Optional ai-service client for LLM-based grey-zone resolution.
    semantic_client: Option<Arc<SemanticClient>>,
}

impl Matcher {
    pub fn new(
        repository: Arc<MatchingRepository>,
        policy:     Arc<RwLock<MatchingPolicy>>,
    ) -> Self {
        let candidate_generator = Arc::new(CandidateGenerator::new(Arc::clone(&repository)));
        let policy_snapshot = Arc::new(
            policy.read().unwrap_or_else(|e| e.into_inner()).clone(),
        );
        let review_engine = Arc::new(ReviewEngine::new(policy_snapshot));
        Self {
            candidate_generator,
            repository,
            review_engine,
            policy,
            semantic_client: None,
        }
    }

    /// Attach a SemanticClient so LLM resolution is called for grey-zone pairs.
    pub fn with_semantic_client(mut self, client: SemanticClient) -> Self {
        self.semantic_client = Some(Arc::new(client));
        self
    }


    #[instrument(skip(self, request, policy_override))]
    pub async fn execute(
        &self,
        request: MatchRequest,
        policy_override: Option<MatchingPolicy>,
    ) -> Result<MatchResponse> {
        let start      = Instant::now();
        let started_at = Utc::now();

        // If a per-request policy override is supplied (e.g. from a domain
        // policy looked up by DomainPolicyService), use it directly.
        // Otherwise snapshot the shared live policy as usual so that a single
        // match run uses consistent weights even if PATCH /policy/weights fires
        // concurrently.
        let policy_snapshot: Arc<MatchingPolicy> = match policy_override {
            Some(p) => Arc::new(p),
            None => Arc::new(
                self.policy
                    .read()
                    .unwrap_or_else(|e| e.into_inner())
                    .clone(),
            ),
        };

        let scorer = ScoreCalculator::new(Arc::clone(&policy_snapshot));

        let blocking_result = self
            .candidate_generator
            .generate_candidates(&request)
            .await?;

        let candidates = self
            .candidate_generator
            .load_entities(request.tenant_id, &blocking_result.candidate_ids)
            .await?;

        let source_id = request.entity.entity_id;
        let mut scored_matches = Vec::<MatchCandidate>::new();
        let mut match_graph    = Vec::<MatchResult>::new();

        // ── Initial field + vector scoring ────────────────────────────────────
        for candidate in candidates {
            let match_candidate = scorer.score_candidate(
                &request.entity,
                &candidate.entity,
                candidate.vector_similarity,
            )?;
            let score      = match_candidate.score as f64;
            let confidence = match_candidate.confidence as f64;

            if score >= policy_snapshot.review_threshold as f64 {
                match_graph.push(MatchResult {
                    source_entity_id:    source_id,
                    candidate_entity_id: match_candidate.entity_id,
                    score,
                    confidence,
                });
            }

            scored_matches.push(match_candidate);
        }

        // ── Semantic resolution for grey-zone candidates ───────────────────────
        // Only runs when: (a) the request enables it, and (b) a SemanticClient
        // is configured. Upgrades RequiresReview to Matched/Rejected based on
        // LLM decision, and stores the ai_score for audit.
        if request.semantic_matching {
            if let Some(ref sem_client) = self.semantic_client {
                let source_attrs = serde_json::to_value(&request.entity.attributes)
                    .unwrap_or(serde_json::Value::Null);
                let entity_type  = request.entity.entity_type.to_string();

                for candidate in &mut scored_matches {
                    if candidate.status != MatchStatus::RequiresReview {
                        continue;
                    }

                    let candidate_attrs = serde_json::json!({ "entity_id": candidate.entity_id });

                    match sem_client
                        .resolve(
                            request.tenant_id,
                            &source_attrs,
                            &candidate_attrs,
                            candidate.score,
                            &entity_type,
                        )
                        .await
                    {
                        Some(result) => {
                            candidate.ai_score = Some(result.confidence);
                            match result.decision {
                                SemanticDecision::Match => {
                                    candidate.status = MatchStatus::Matched;
                                    candidate.recommended_for_merge = true;
                                    candidate.requires_human_review  = false;
                                    candidate.explanations.push(format!(
                                        "AI resolved → match (confidence={:.2}): {}",
                                        result.confidence, result.reasoning
                                    ));
                                }
                                SemanticDecision::NoMatch => {
                                    candidate.status = MatchStatus::Rejected;
                                    candidate.recommended_for_merge = false;
                                    candidate.requires_human_review  = false;
                                    candidate.explanations.push(format!(
                                        "AI resolved → no match (confidence={:.2}): {}",
                                        result.confidence, result.reasoning
                                    ));
                                }
                            }
                        }
                        None => {
                            warn!(
                                entity_id = %candidate.entity_id,
                                "semantic resolution unavailable; candidate stays in RequiresReview"
                            );
                        }
                    }
                }
            }
        }

        scored_matches.sort_by(|a, b| {
            b.score.partial_cmp(&a.score).unwrap_or(std::cmp::Ordering::Equal)
        });

        // Detect ambiguous top candidates before truncation.
        let mut warnings: Vec<String> = vec![];
        if scored_matches.len() >= 2 {
            let top    = scored_matches[0].score;
            let second = scored_matches[1].score;
            if self.review_engine.detect_ambiguous_candidates(top, second) {
                let msg = format!(
                    "Top two candidates are ambiguous (scores {:.3} vs {:.3}); human review recommended.",
                    top, second
                );
                warn!(%msg);
                warnings.push(msg);
            }
        }

        if scored_matches.len() > request.max_candidates {
            scored_matches.truncate(request.max_candidates);
        }

        // ── Persist match candidates to DB ────────────────────────────────────
        // Persisted after truncation so only the top-N returned to the caller
        // are stored. Errors are non-fatal — the match response is still returned.
        for candidate in &scored_matches {
            if let Err(e) = self.repository
                .create_match_candidate(
                    request.tenant_id,
                    request.request_id,
                    source_id,
                    candidate,
                )
                .await
            {
                warn!(
                    entity_id = %candidate.entity_id,
                    error = %e,
                    "failed to persist match candidate — result still returned to caller"
                );
            }
        }

        let clusters = ClusterBuilder::build(&match_graph, &policy_snapshot);
        let execution_time_ms = start.elapsed().as_millis() as u64;

        info!(
            tenant_id=%request.tenant_id,
            matches=scored_matches.len(),
            duration_ms=execution_time_ms,
            auto_merge_threshold=policy_snapshot.auto_merge_threshold,
            "matching execution completed"
        );

        Ok(MatchResponse {
            request_id: request.request_id,
            matches: scored_matches,
            clusters,
            blocking: Some(blocking_result.diagnostics),
            metadata: MatchExecutionMetadata {
                started_at,
                completed_at: Utc::now(),
                execution_time_ms,
                candidates_evaluated: blocking_result.candidate_ids.len(),
                blocking_reduction: None,
                ai_assisted: request.ai_assisted,
                semantic_matching: request.semantic_matching,
                graph_matching: request.graph_matching,
                engine_version: MATCH_ENGINE_VERSION.to_string(),
                audit: AuditMetadata {
                    created_at:     started_at,
                    updated_at:     Utc::now(),
                    created_by:     None,
                    updated_by:     None,
                    correlation_id: request.correlation_id,
                    causation_id:   None,
                    request_id:     Some(request.request_id.to_string()),
                },
                version_info: VersionInfo {
                    schema_version:   "v2".to_string(),
                    contract_version: "1.0".to_string(),
                    entity_version:   1,
                },
                metadata: MetadataMap::new(),
            },
            warnings,
            errors: vec![],
        })
    }
}
