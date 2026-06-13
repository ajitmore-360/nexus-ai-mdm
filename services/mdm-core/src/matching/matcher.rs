use std::sync::{Arc, RwLock};
use std::time::Instant;

use anyhow::Result;
use chrono::Utc;
use tracing::{info, instrument};

use crate::matching::models::MATCH_ENGINE_VERSION;
use contracts::mdm::{
    common::{AuditMetadata, MetadataMap, VersionInfo},
    matching::{
        MatchCandidate, MatchExecutionMetadata, MatchRequest, MatchResponse,
    },
};

use crate::db::repositories::matching_repository::MatchingRepository;
use crate::matching::candidate_generation::CandidateGenerator;
use crate::matching::clustering::cluster_builder::ClusterBuilder;
use crate::matching::models::MatchResult;
use crate::matching::policy::MatchingPolicy;
use crate::matching::scoring::score_calculator::ScoreCalculator;

pub struct Matcher {
    candidate_generator: Arc<CandidateGenerator>,
    /// Shared live policy — wrapped in RwLock so PATCH /policy/weights
    /// takes effect on the next match execution without restarting the service.
    policy: Arc<RwLock<MatchingPolicy>>,
}

impl Matcher {
    pub fn new(
        repository: Arc<MatchingRepository>,
        policy:     Arc<RwLock<MatchingPolicy>>,
    ) -> Self {
        Self {
            candidate_generator: Arc::new(CandidateGenerator::new(repository)),
            policy,
        }
    }

    #[instrument(skip(self, request))]
    pub async fn execute(&self, request: MatchRequest) -> Result<MatchResponse> {
        let start      = Instant::now();
        let started_at = Utc::now();

        // Snapshot the current policy once per execution.
        // This ensures a single match run uses consistent weights even if
        // PATCH /policy/weights fires concurrently.
        let policy_snapshot = Arc::new(
            self.policy
                .read()
                .unwrap_or_else(|e| e.into_inner())
                .clone(),
        );

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

        scored_matches.sort_by(|a, b| {
            b.score.partial_cmp(&a.score).unwrap_or(std::cmp::Ordering::Equal)
        });

        if scored_matches.len() > request.max_candidates {
            scored_matches.truncate(request.max_candidates);
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
            warnings: vec![],
            errors: vec![],
        })
    }
}
