use std::sync::Arc;
use std::time::Instant;

use anyhow::Result;
use chrono::Utc;
use tracing::{
    error,
    info,
    instrument,
};

use shared_contracts::mdm::matching::{
    BlockingDiagnostics,
    MatchCandidate,
    MatchExecutionMetadata,
    MatchRequest,
    MatchResponse,
};

use crate::db::repositories::{
    event_repository::EventRepository,
    matching_repository::MatchingRepository,
};

use crate::matching::{
    candidate_generation::CandidateGenerator,
    clustering::cluster_builder::ClusterBuilder,
    matcher::Matcher,
    review::review_engine::ReviewEngine,
};

pub struct MatchingService {
    matcher: Arc<Matcher>,

    candidate_generator:
        Arc<CandidateGenerator>,

    review_engine:
        Arc<ReviewEngine>,

    matching_repository:
        Arc<MatchingRepository>,

    event_repository:
        Arc<EventRepository>,
}

impl MatchingService {
    pub fn new(
        matcher: Arc<Matcher>,
        candidate_generator:
            Arc<CandidateGenerator>,
        review_engine:
            Arc<ReviewEngine>,
        matching_repository:
            Arc<MatchingRepository>,
        event_repository:
            Arc<EventRepository>,
    ) -> Self {
        Self {
            matcher,
            candidate_generator,
            review_engine,
            matching_repository,
            event_repository,
        }
    }

    #[instrument(skip(self, request))]
    pub async fn execute_matching(
        &self,
        request: MatchRequest,
    ) -> Result<MatchResponse> {

        let started = Instant::now();

        info!(
            request_id=%request.request_id,
            "matching started"
        );

        //
        // Candidate Generation
        //

        let candidates =
            self
                .candidate_generator
                .generate(
                    &request,
                )
                .await?;

        let candidate_count =
            candidates.len();

        //
        // Match Scoring
        //

        let mut results =
            Vec::<MatchCandidate>::new();

        for candidate in candidates {

            match self
                .matcher
                .match_candidate(
                    &request.entity,
                    &candidate,
                )
                .await
            {
                Ok(result) => {

                    let decision =
                        self
                            .review_engine
                            .evaluate(
                                &result,
                            );

                    let review_case =
                        self
                            .review_engine
                            .create_review_case(
                                &result,
                            );

                    if let Some(case) =
                        review_case
                    {
                        self
                            .matching_repository
                            .create_review_case(
                                &case,
                            )
                            .await?;
                    }

                    self
                        .matching_repository
                        .save_match_result(
                            &result,
                        )
                        .await?;

                    self
                        .event_repository
                        .publish_match_event(
                            &result,
                            &decision,
                        )
                        .await?;

                    results.push(
                        result.into(),
                    );
                }

                Err(e) => {
                    error!(
                        error=?e,
                        "candidate matching failed"
                    );
                }
            }
        }

        //
        // Cluster Construction
        //

        let clusters =
            ClusterBuilder::build(
                &results
                    .iter()
                    .filter_map(|c| {
                        c.metadata
                            .get("match_result")
                            .and_then(|_| None)
                    })
                    .collect::<Vec<_>>(),
            );

        let execution_time =
            started.elapsed();

        let metadata =
            MatchExecutionMetadata {

                started_at:
                    Utc::now(),

                completed_at:
                    Utc::now(),

                execution_time_ms:
                    execution_time
                        .as_millis()
                        as u64,

                candidates_evaluated:
                    candidate_count,

                blocking_reduction:
                    None,

                ai_assisted:
                    request.ai_assisted,

                semantic_matching:
                    request.semantic_matching,

                graph_matching:
                    request.graph_matching,

                engine_version:
                    "2.0.0".to_string(),

                audit:
                    Default::default(),

                version_info:
                    Default::default(),

                metadata:
                    Default::default(),
            };

        let blocking =
            Some(
                BlockingDiagnostics {

                    applied_rules:
                        request
                            .blocking_rules
                            .clone(),

                    generated_keys:
                        vec![],

                    reduced_candidates:
                        candidate_count,

                    metadata:
                        Default::default(),
                }
            );

        let response =
            MatchResponse {

                request_id:
                    request.request_id,

                matches:
                    results,

                clusters,

                blocking,

                metadata,

                warnings:
                    vec![],

                errors:
                    vec![],
            };

        info!(
            request_id=%request.request_id,
            elapsed_ms=%response.metadata.execution_time_ms,
            matches=%response.matches.len(),
            "matching completed"
        );

        Ok(response)
    }
}