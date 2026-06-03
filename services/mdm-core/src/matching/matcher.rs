use std::sync::Arc;
use std::time::Instant;

use anyhow::Result;
use chrono::Utc;
use tracing::{
    info,
    instrument,
};
use uuid::Uuid;

use shared_contracts::mdm::{
    common::{
        AuditMetadata,
        MetadataMap,
        VersionInfo,
    },
    matching::{
        BlockingDiagnostics,
        MatchCandidate,
        MatchCluster,
        MatchExecutionMetadata,
        MatchRequest,
        MatchResponse,
    },
};

use crate::{
    db::repositories::matching_repository::MatchingRepository,
    matching::{
        candidate_generation::CandidateGenerator,
        models::{
            CandidateEntity,
            MatchThresholds,
        },
        scoring::score_calculator::ScoreCalculator,
    },
};

//
// ============================================================
// MATCHER CONFIG
// ============================================================
//

#[derive(Debug, Clone)]
pub struct MatcherConfig {
    pub auto_merge_threshold: f32,
    pub review_threshold: f32,
    pub max_clusters: usize,
}

impl Default for MatcherConfig {
    fn default() -> Self {
        Self {
            auto_merge_threshold: 0.95,
            review_threshold: 0.75,
            max_clusters: 100,
        }
    }
}

//
// ============================================================
// MATCHER
// ============================================================
//

pub struct Matcher<R>
where
    R: MatchingRepository,
{
    repository: Arc<R>,

    candidate_generator:
        Arc<CandidateGenerator<R>>,

    scorer:
        Arc<ScoreCalculator>,

    config:
        MatcherConfig,
}

impl<R> Matcher<R>
where
    R: MatchingRepository,
{
    pub fn new(
        repository: Arc<R>,
        candidate_generator:
            Arc<CandidateGenerator<R>>,
        scorer:
            Arc<ScoreCalculator>,
        config: MatcherConfig,
    ) -> Self {
        Self {
            repository,
            candidate_generator,
            scorer,
            config,
        }
    }

    //
    // ========================================================
    // EXECUTE MATCH
    // ========================================================
    //

    #[instrument(skip(self, request))]
    pub async fn execute(
        &self,
        request: MatchRequest,
    ) -> Result<MatchResponse> {

        let start =
            Instant::now();

        let started_at =
            Utc::now();

        //
        // ====================================================
        // CANDIDATE GENERATION
        // ====================================================
        //

        let blocking_result =
            self
                .candidate_generator
                .generate_candidates(
                    &request,
                )
                .await?;

        //
        // ====================================================
        // LOAD ENTITIES
        // ====================================================
        //

        let candidates =
            self
                .candidate_generator
                .load_entities(
                    request.tenant_id,
                    &blocking_result
                        .candidate_ids,
                )
                .await?;

        //
        // ====================================================
        // SCORE
        // ====================================================
        //

        let mut scored_matches =
            Vec::<MatchCandidate>::new();

        for candidate in candidates {

            let match_result =
                self.score_candidate(
                    &request,
                    candidate,
                )?;

            scored_matches.push(
                match_result,
            );
        }

        //
        // ====================================================
        // SORT
        // ====================================================
        //

        scored_matches.sort_by(
            |a, b| {
                b.score
                    .partial_cmp(
                        &a.score,
                    )
                    .unwrap()
            },
        );

        //
        // ====================================================
        // LIMIT
        // ====================================================
        //

        if scored_matches.len()
            > request.max_candidates
        {
            scored_matches.truncate(
                request.max_candidates,
            );
        }

        //
        // ====================================================
        // CLUSTER
        // ====================================================
        //

        let clusters =
            self.build_clusters(
                &scored_matches,
            );

        //
        // ====================================================
        // EXECUTION METADATA
        // ====================================================
        //

        let execution_time_ms =
            start
                .elapsed()
                .as_millis()
                as u64;

        let completed_at =
            Utc::now();

        info!(
            tenant_id=%request.tenant_id,
            matches=scored_matches.len(),
            duration_ms=execution_time_ms,
            "matching execution completed"
        );

        Ok(
            MatchResponse {

                request_id:
                    request.request_id,

                matches:
                    scored_matches,

                clusters,

                blocking:
                    Some(
                        blocking_result
                            .diagnostics,
                    ),

                metadata:
                    MatchExecutionMetadata {

                        started_at,

                        completed_at,

                        execution_time_ms,

                        candidates_evaluated:
                            blocking_result
                                .candidate_ids
                                .len(),

                        blocking_reduction:
                            None,

                        ai_assisted:
                            request
                                .ai_assisted,

                        semantic_matching:
                            request
                                .semantic_matching,

                        graph_matching:
                            request
                                .graph_matching,

                        engine_version:
                            "matching-engine-v2"
                                .to_string(),

                        audit:
                            AuditMetadata {

                                created_by:
                                    None,

                                created_at:
                                    started_at,

                                updated_by:
                                    None,

                                updated_at:
                                    None,
                            },

                        version_info:
                            VersionInfo {

                                version:
                                    1,

                                schema_version:
                                    Some(
                                        "v2"
                                            .to_string(),
                                    ),

                                previous_version:
                                    None,
                            },

                        metadata:
                            MetadataMap::new(),
                    },

                warnings:
                    vec![],

                errors:
                    vec![],
            },
        )
    }

    //
    // ========================================================
    // SCORE CANDIDATE
    // ========================================================
    //

    fn score_candidate(
        &self,
        request:
            &MatchRequest,
        candidate:
            CandidateEntity,
    ) -> Result<MatchCandidate> {

        self.scorer.score_candidate(
            &request.entity,
            &candidate.entity,
            None,
        )
    }

    //
    // ========================================================
    // CLUSTERING
    // ========================================================
    //

    fn build_clusters(
        &self,
        matches:
            &[MatchCandidate],
    ) -> Vec<MatchCluster> {

        let mut clusters =
            Vec::new();

        for m in matches {

            if !m.recommended_for_merge {
                continue;
            }

            clusters.push(
                MatchCluster {

                    cluster_id:
                        Uuid::new_v4(),

                    entity_ids:
                        vec![
                            m.entity_id,
                        ],

                    confidence:
                        m.score,

                    suggested_master:
                        Some(
                            m.entity_id,
                        ),

                    metadata:
                        MetadataMap::new(),
                },
            );
        }

        clusters
    }
}