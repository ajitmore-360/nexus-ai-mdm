use std::time::Instant;

use chrono::Utc;

use serde_json::Value;

use uuid::Uuid;

use contracts::mdm::{
    common::{
        AuditMetadata,
        ConfidenceScore,
        MetadataMap,
        VersionInfo,
    },
    entity::{
        CanonicalEntity,
        EntityAttribute,
    },
    matching::{
        BlockingDiagnostics,
        FieldMatchResult,
        MatchCandidate,
        MatchCluster,
        MatchExecutionMetadata,
        MatchRequest,
        MatchResponse,
        MatchStatus,
        MatchStrategy,
    },
};

//
// ========================================
// MATCH ENTITY
// ========================================
//

pub async fn match_entity(
    request: MatchRequest,
    candidate_entities: Vec<CanonicalEntity>,
) -> MatchResponse {

    let started = Instant::now();

    //
    // ========================================
    // BLOCKING
    // ========================================
    //

    let blocked_candidates =
        apply_blocking(
            &request,
            candidate_entities,
        );

    //
    // ========================================
    // MATCH CANDIDATES
    // ========================================
    //

    let mut matches:
        Vec<MatchCandidate> = vec![];

    for candidate in blocked_candidates.iter()
    {
        let result =
            evaluate_candidate(
                &request.entity,
                candidate,
                &request.strategy,
                request.threshold
                    .unwrap_or(0.75),
            );

        if result.score
            >= request
                .threshold
                .unwrap_or(0.75)
        {
            matches.push(result);
        }
    }

    //
    // ========================================
    // SORT BY SCORE
    // ========================================
    //

    matches.sort_by(|a, b| {
        b.score
            .partial_cmp(&a.score)
            .unwrap()
    });

    //
    // ========================================
    // CLUSTERING
    // ========================================
    //

    let clusters =
        build_clusters(&matches);

    //
    // ========================================
    // EXECUTION METADATA
    // ========================================
    //

    let execution_time_ms =
        started.elapsed().as_millis()
            as u64;

    MatchResponse {

        request_id:
            request.request_id,

        matches,

        clusters,

        blocking: Some(
            BlockingDiagnostics {

                applied_rules:
                    request
                        .blocking_rules
                        .clone(),

                generated_keys:
                    vec![],

                reduced_candidates:
                    blocked_candidates
                        .len(),

                metadata:
                    MetadataMap::new(),
            }
        ),

        metadata:
            MatchExecutionMetadata {

                started_at:
                    Utc::now(),

                completed_at:
                    Utc::now(),

                execution_time_ms,

                candidates_evaluated:
                    blocked_candidates
                        .len(),

                blocking_reduction:
                    None,

                ai_assisted:
                    request.ai_assisted,

                semantic_matching:
                    request
                        .semantic_matching,

                graph_matching:
                    request
                        .graph_matching,

                engine_version:
                    "2.0.0"
                        .to_string(),

                audit:
                    AuditMetadata {

                        created_at:
                            Utc::now(),

                        updated_at:
                            Utc::now(),

                        created_by: None,

                        updated_by: None,

                        correlation_id:
                            request
                                .correlation_id,

                        causation_id:
                            None,

                        request_id:
                            Some(
                                request
                                    .request_id
                                    .to_string()
                            ),
                    },

                version_info:
                    VersionInfo {

                        schema_version:
                            "2.0.0"
                                .to_string(),

                        contract_version:
                            "2.0.0"
                                .to_string(),

                        entity_version:
                            1,
                    },

                metadata:
                    MetadataMap::new(),
            },

        warnings: vec![],

        errors: vec![],
    }
}

//
// ========================================
// APPLY BLOCKING
// ========================================
//

fn apply_blocking(
    request: &MatchRequest,
    candidates: Vec<CanonicalEntity>,
) -> Vec<CanonicalEntity> {

    //
    // Future:
    // deterministic blocking
    // phonetic blocking
    // semantic blocking
    // vector blocking
    //

    candidates
}

//
// ========================================
// EVALUATE CANDIDATE
// ========================================
//

fn evaluate_candidate(
    incoming: &CanonicalEntity,
    candidate: &CanonicalEntity,
    strategy: &MatchStrategy,
    threshold: f32,
) -> MatchCandidate {

    let mut total_score = 0.0;

    let mut explanations =
        vec![];

    let mut field_matches =
        vec![];

    //
    // ========================================
    // FIELD COMPARISON
    // ========================================
    //

    for incoming_attr
    in incoming.attributes.iter()
    {
        if let Some(candidate_attr) =
            find_matching_attribute(
                &incoming_attr.key,
                candidate,
            )
        {
            let field_result =
                compare_attributes(
                    incoming_attr,
                    candidate_attr,
                    strategy,
                );

            total_score +=
                field_result.score;

            explanations.extend(
                field_result
                    .explanation
                    .clone(),
            );

            field_matches
                .push(field_result);
        }
    }

    //
    // ========================================
    // NORMALIZATION
    // ========================================
    //

    let normalized_score =
        normalize_score(
            total_score,
            field_matches.len(),
        );

    //
    // ========================================
    // MATCH STATUS
    // ========================================
    //

    let status =
        if normalized_score >= threshold {

            MatchStatus::Matched

        } else if normalized_score >= 0.5 {

            MatchStatus::PossibleMatch

        } else {

            MatchStatus::Rejected
        };

    MatchCandidate {

        entity_id:
            candidate.entity_id,

        status:
            status.clone(),

        score:
            normalized_score,

        confidence:
            normalized_score,

        vector_similarity:
            None,

        graph_similarity:
            None,

        ai_score:
            None,

        survivorship_compatibility:
            None,

        explanations,

        field_matches,

        policy_decisions:
            vec![],

        recommended_for_merge:
            matches!(
                status,
                MatchStatus::Matched
            ),

        requires_human_review:
            matches!(
                status,
                MatchStatus::PossibleMatch
            ),

        metadata:
            MetadataMap::new(),
    }
}

//
// ========================================
// FIND ATTRIBUTE
// ========================================
//

fn find_matching_attribute<'a>(
    key: &str,
    entity: &'a CanonicalEntity,
) -> Option<&'a EntityAttribute> {

    entity
        .attributes
        .iter()
        .find(|a| a.key == key)
}

//
// ========================================
// ATTRIBUTE COMPARISON
// ========================================
//

fn compare_attributes(
    incoming: &EntityAttribute,
    candidate: &EntityAttribute,
    strategy: &MatchStrategy,
) -> FieldMatchResult {

    let mut score = 0.0;

    let mut explanations =
        vec![];

    //
    // ========================================
    // EXACT MATCH
    // ========================================
    //

    if incoming.value == candidate.value {

        score += 1.0;

        explanations.push(
            "exact_match".to_string()
        );
    }

    //
    // ========================================
    // STRING SIMILARITY
    // ========================================
    //

    if let (
        Some(source),
        Some(target),
    ) = (
        incoming.value.as_str(),
        candidate.value.as_str(),
    ) {

        let similarity =
            string_similarity(
                source,
                target,
            );

        score += similarity;

        explanations.push(format!(
            "string_similarity={:.4}",
            similarity
        ));
    }

    //
    // ========================================
    // STRATEGY BOOSTS
    // ========================================
    //

    match strategy {

        MatchStrategy::AIEnhanced => {

            score += 0.1;

            explanations.push(
                "ai_boost_applied"
                    .to_string()
            );
        }

        MatchStrategy::Semantic => {

            score += 0.1;

            explanations.push(
                "semantic_boost_applied"
                    .to_string()
            );
        }

        MatchStrategy::Hybrid => {

            score += 0.2;

            explanations.push(
                "hybrid_boost_applied"
                    .to_string()
            );
        }

        _ => {}
    }

    FieldMatchResult {

        field:
            incoming.key.clone(),

        source_value:
            Some(
                incoming.value.clone()
            ),

        candidate_value:
            Some(
                candidate.value.clone()
            ),

        score,

        confidence:
            Some(
                ConfidenceScore {

                    score,

                    explanation:
                        Some(
                            explanations
                                .join(", ")
                        ),

                    model_version:
                        None,
                }
            ),

        strategy:
            strategy.clone(),

        semantic_similarity:
            None,

        explanation:
            explanations,

        metadata:
            MetadataMap::new(),
    }
}

//
// ========================================
// NORMALIZE SCORE
// ========================================
//

fn normalize_score(
    total: f32,
    fields: usize,
) -> f32 {

    if fields == 0 {
        return 0.0;
    }

    (total / fields as f32)
        .min(1.0)
}

//
// ========================================
// SIMPLE STRING SIMILARITY
// ========================================
//

fn string_similarity(
    left: &str,
    right: &str,
) -> f32 {

    if left.eq_ignore_ascii_case(right) {
        return 1.0;
    }

    let left =
        left.to_lowercase();

    let right =
        right.to_lowercase();

    let common =
        left
            .chars()
            .filter(|c| {
                right.contains(*c)
            })
            .count();

    common as f32
        / left.len().max(1)
            as f32
}

//
// ========================================
// BUILD CLUSTERS
// ========================================
//

fn build_clusters(
    matches: &[MatchCandidate],
) -> Vec<MatchCluster> {

    if matches.is_empty() {
        return vec![];
    }

    vec![
        MatchCluster {

            cluster_id:
                Uuid::new_v4(),

            entity_ids:
                matches
                    .iter()
                    .map(|m| m.entity_id)
                    .collect(),

            confidence:
                matches[0].score,

            suggested_master:
                Some(
                    matches[0]
                        .entity_id
                ),

            metadata:
                MetadataMap::new(),
        }
    ]
}