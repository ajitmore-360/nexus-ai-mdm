use std::collections::HashMap;
use std::time::Instant;

use chrono::Utc;
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
        EntityType,
    },
    golden_record::{
        AttributeConflict,
        GoldenAttribute,
        GoldenRecord,
        GoldenRecordLifecycleStage,
        GoldenRecordQuality,
        GoldenRecordStatus,
        SourceContribution,
    },
    survivorship::{
        SurvivorshipEvaluation,
        SurvivorshipRule,
        SurvivorshipStrategy,
    },
};

use crate::survivorship::models::{
    CandidateScore,
    FieldDecision,
    SurvivorshipExplanation,
    SurvivorshipExecutionMetadata,
};

//
// ========================================
// APPLY SURVIVORSHIP
// ========================================
//

pub fn apply_survivorship(
    entities: Vec<CanonicalEntity>,
    rules: Vec<SurvivorshipRule>,
) -> GoldenRecord {

    let execution_started =
        Instant::now();

    //
    // ========================================
    // SAFETY VALIDATION
    // ========================================
    //

    if entities.is_empty() {

        return build_empty_golden_record();
    }

    //
    // ========================================
    // OUTPUT COLLECTIONS
    // ========================================
    //

    let mut golden_attributes:
        Vec<GoldenAttribute> = vec![];

    let mut evaluations:
        Vec<SurvivorshipEvaluation> = vec![];

    let mut decisions:
        Vec<FieldDecision> = vec![];

    let mut conflicts:
        Vec<AttributeConflict> = vec![];

    let mut total_candidates_evaluated =
        0usize;

    //
    // ========================================
    // EXECUTION ID
    // ========================================
    //

    let execution_id =
        Uuid::new_v4();

    //
    // ========================================
    // PROCESS RULES
    // ========================================
    //

    for rule in rules.iter() {

        let mut candidates:
            Vec<AttributeCandidate> = vec![];

        //
        // ========================================
        // COLLECT CANDIDATES
        // ========================================
        //

        for entity in entities.iter() {

            for attribute in entity.attributes.iter() {

                if attribute.key != rule.attribute {
                    continue;
                }

                let (
                    score,
                    reasons,
                ) = evaluate_attribute(
                    attribute,
                    rule,
                );

                if let Some(min_confidence) =
                    rule.minimum_confidence
                {
                    if score < min_confidence {
                        continue;
                    }
                }

                candidates.push(
                    AttributeCandidate {

                        entity_id:
                            entity.entity_id,

                        attribute:
                            attribute.clone(),

                        score,

                        reasons,
                    }
                );
            }
        }

        total_candidates_evaluated +=
            candidates.len();

        //
        // ========================================
        // NO CANDIDATES
        // ========================================
        //

        if candidates.is_empty() {

            evaluations.push(
                SurvivorshipEvaluation {

                    evaluation_id:
                        Uuid::new_v4(),

                    rule_id:
                        rule.rule_id,

                    attribute:
                        rule.attribute.clone(),

                    selected_value:
                        serde_json::Value::Null,

                    selected_source:
                        None,

                    confidence:
                        Some(0.0),

                    survivorship_score:
                        Some(0.0),

                    ai_score:
                        None,

                    reasoning:
                        Some(
                            "No valid candidates found"
                                .to_string()
                        ),

                    policy_decisions:
                        vec![],

                    warnings:
                        vec![
                            "No matching attributes found"
                                .to_string()
                        ],

                    manually_overridden:
                        false,

                    overridden_by:
                        None,

                    overridden_at:
                        None,

                    evaluated_at:
                        Utc::now(),

                    metadata:
                        build_metadata(vec![
                            (
                                "rule_name",
                                serde_json::json!(
                                    rule.rule_name
                                )
                            ),
                            (
                                "strategy",
                                serde_json::json!(
                                    format!(
                                        "{:?}",
                                        rule.strategy
                                    )
                                )
                            ),
                        ]),
                }
            );

            continue;
        }

        //
        // ========================================
        // SORT DESCENDING
        // ========================================
        //

        candidates.sort_by(|a, b| {

            b.score
                .partial_cmp(&a.score)
                .unwrap_or(
                    std::cmp::Ordering::Equal
                )
        });

        //
        // ========================================
        // CONFLICT DETECTION
        // ========================================
        //

        let unique_values:
            Vec<serde_json::Value> =
            candidates
                .iter()
                .map(|c| {
                    c.attribute.value.clone()
                })
                .collect();

        if unique_values.len() > 1 {

            conflicts.push(
                AttributeConflict {

                    attribute:
                        rule.attribute.clone(),

                    conflicting_values:
                        unique_values.clone(),

                    sources:
                        candidates
                            .iter()
                            .map(|c| {
                                extract_source(
                                    &c.attribute
                                )
                            })
                            .collect(),

                    resolved:
                        true,

                    resolution_notes:
                        Some(
                            format!(
                                "Resolved using {:?}",
                                rule.strategy
                            )
                        ),
                }
            );
        }

        //
        // ========================================
        // WINNER
        // ========================================
        //

        let winner =
            &candidates[0];

        //
        // ========================================
        // CONFIDENCE
        // ========================================
        //

        let confidence =
            calculate_confidence(
                &candidates
            );

        //
        // ========================================
        // FIELD DECISION
        // ========================================
        //

        decisions.push(
            FieldDecision {

                decision_id:
                    Uuid::new_v4(),

                field:
                    rule.attribute.clone(),

                // winning strategy
                selected_entity_id: winner.entity_id,

                chosen_value:
                    winner
                        .attribute
                        .value
                        .clone(),

                source:
                    extract_source(
                        &winner.attribute
                    ),
                //
                // Survivorship strategy
                //
                strategy:
                    rule.strategy.clone(),

                confidence,

                winning_score:
                    winner.score,

                candidates:
                    candidates
                        .iter()
                        .map(|candidate| {

                            CandidateScore {

                                entity_id:
                                    candidate.entity_id,

                                source:
                                    extract_source(
                                        &candidate.attribute
                                    ),

                                value:
                                    candidate
                                        .attribute
                                        .value
                                        .clone(),

                                score:
                                    candidate.score,

                                confidence:
                                    candidate
                                        .attribute
                                        .confidence
                                        .clone(),

                                reasons:
                                    candidate
                                        .reasons
                                        .clone(),

                                ai_score:
                                    Some(
                                        calculate_ai_score(
                                            candidate
                                        )
                                    ),

                                metadata:
                                    build_metadata(vec![
                                        (
                                            "attribute_key",
                                            serde_json::json!(
                                                candidate.attribute.key
                                            )
                                        ),
                                        (
                                            "strategy",
                                            serde_json::json!(
                                                format!(
                                                    "{:?}",
                                                    rule.strategy
                                                )
                                            )
                                        ),
                                    ]),
                            }

                        })
                        .collect(),

                reason:
                    winner
                        .reasons
                        .join(", "),

                manually_overridden:
                    false,

                overridden_by:
                    None,

                overridden_at:
                    None,

                policy_decisions:
                    evaluate_policy_decisions(
                        winner
                    ),

                ai_recommendations:
                    generate_ai_recommendations(
                        winner
                    ),

                metadata:
                    build_metadata(vec![
                        (
                            "rule_name",
                            serde_json::json!(
                                rule.rule_name
                            )
                        ),
                        (
                            "execution_id",
                            serde_json::json!(
                                execution_id
                            )
                        ),
                    ]),
            }
        );

        //
        // ========================================
        // SURVIVORSHIP EVALUATION
        // ========================================
        //

        evaluations.push(
            SurvivorshipEvaluation {

                evaluation_id:
                    Uuid::new_v4(),

                rule_id:
                    rule.rule_id,

                attribute:
                    rule.attribute.clone(),

                selected_value:
                    winner
                        .attribute
                        .value
                        .clone(),

                selected_source:
                    Some(
                        extract_source(
                            &winner.attribute
                        )
                    ),

                confidence:
                    Some(confidence),

                survivorship_score:
                    Some(
                        winner.score
                    ),

                ai_score:
                    Some(
                        calculate_ai_score(
                            winner
                        )
                    ),

                reasoning:
                    Some(
                        winner
                            .reasons
                            .join(", ")
                    ),

                policy_decisions:
                    evaluate_policy_decisions(
                        winner
                    ),

                warnings:
                    vec![],

                manually_overridden:
                    false,

                overridden_by:
                    None,

                overridden_at:
                    None,

                evaluated_at:
                    Utc::now(),

                metadata:
                    build_metadata(vec![
                        (
                            "candidate_count",
                            serde_json::json!(
                                candidates.len()
                            )
                        ),
                        (
                            "strategy",
                            serde_json::json!(
                                format!(
                                    "{:?}",
                                    rule.strategy
                                )
                            )
                        ),
                    ]),
            }
        );

        //
        // ========================================
        // ENRICHED ATTRIBUTE
        // ========================================
        //

        let mut enriched_attribute =
            winner
                .attribute
                .clone();

        enriched_attribute.confidence =
            Some(
                ConfidenceScore {

                    score:
                        confidence,

                    explanation:
                        Some(
                            winner
                                .reasons
                                .join(", ")
                        ),

                    model_version:
                        Some(
                            "survivorship-engine-v1"
                                .to_string()
                        ),
                }
            );

        //
        // ========================================
        // GOLDEN ATTRIBUTE
        // ========================================
        //

        let golden_attribute =
            GoldenAttribute {

                golden_attribute_id:
                    Uuid::new_v4(),

                attribute:
                    enriched_attribute,

                selected_from_entity:
                    winner.entity_id,

                selected_from_source:
                    Some(
                        extract_source(
                            &winner.attribute
                        )
                    ),

                survivorship_rule_id:
                    Some(
                        rule.rule_id
                    ),

                survivorship_execution_id:
                    Some(
                        execution_id
                    ),

                survivorship_score:
                    Some(
                        winner.score
                    ),

                ai_confidence:
                    Some(
                        calculate_ai_score(
                            winner
                        )
                    ),

                overridden_by_user:
                    None,

                overridden_at:
                    None,

                override_reason:
                    None,

                explainability:
                    Some(
                        winner
                            .reasons
                            .join(", ")
                    ),

                candidate_entities:
                    candidates
                        .iter()
                        .map(|c| {
                            c.entity_id
                        })
                        .collect(),

                policy_refs:
                    vec![],

                metadata:
                    build_metadata(vec![
                        (
                            "attribute_key",
                            serde_json::json!(
                                rule.attribute
                            )
                        ),
                        (
                            "candidate_count",
                            serde_json::json!(
                                candidates.len()
                            )
                        ),
                    ]),
            };

        golden_attributes.push(
            golden_attribute
        );
    }

    //
    // ========================================
    // QUALITY
    // ========================================
    //

    let trust_score =
        calculate_trust_score(
            &entities
        );

    let completeness_score =
        calculate_record_completeness(
            &entities
        );

    let overall_quality_score =
        calculate_quality_score(
            &entities
        );

    //
    // ========================================
    // EXPLANATION
    // ========================================
    //

    let explanation =
        SurvivorshipExplanation {

            decisions,

            overall_confidence:
                Some(
                    overall_quality_score
                ),

            execution_metadata:
                SurvivorshipExecutionMetadata {

                    execution_id,

                    evaluated_rules:
                        rules.len(),

                    evaluated_candidates:
                        total_candidates_evaluated,

                    execution_time_ms:
                        execution_started
                            .elapsed()
                            .as_millis()
                            as u64,

                    ai_assisted:
                        true,

                    explainability_enabled:
                        true,

                    engine_version:
                        "survivorship-engine-v1"
                            .to_string(),

                    metadata:
                        build_metadata(vec![
                            (
                                "entities_processed",
                                serde_json::json!(
                                    entities.len()
                                )
                            ),
                        ]),
                },

            summary:
                Some(
                    format!(
                        "Applied {} survivorship rules across {} entities",
                        rules.len(),
                        entities.len()
                    )
                ),

            warnings:
                vec![],

            metadata:
                build_metadata(vec![
                    (
                        "quality_score",
                        serde_json::json!(
                            overall_quality_score
                        )
                    ),
                ]),
        };

    //
    // ========================================
    // METADATA
    // ========================================
    //

    let metadata =
        build_metadata(vec![
            (
                "survivorship_evaluations",
                serde_json::to_value(
                    &evaluations
                )
                .unwrap_or_default()
            ),
            (
                "survivorship_explanation",
                serde_json::to_value(
                    &explanation
                )
                .unwrap_or_default()
            ),
            (
                "quality_score",
                serde_json::json!(
                    overall_quality_score
                )
            ),
            (
                "trust_score",
                serde_json::json!(
                    trust_score
                )
            ),
            (
                "completeness_score",
                serde_json::json!(
                    completeness_score
                )
            ),
            (
                "execution_id",
                serde_json::json!(
                    execution_id
                )
            ),
        ]);

    //
    // ========================================
    // BUILD GOLDEN RECORD
    // ========================================
    //

    GoldenRecord {

        golden_record_id:
            Uuid::new_v4(),

        tenant_id:
            entities[0].tenant_id,

        entity_type:
            entities[0]
                .entity_type
                .clone(),

        lifecycle_stage:
            GoldenRecordLifecycleStage::SurvivorshipApplied,

        status:
            GoldenRecordStatus::Active,

        source_entities:
            entities
                .iter()
                .map(|entity| {
                    entity.entity_id
                })
                .collect(),

        golden_attributes,

        quality:
            Some(
                GoldenRecordQuality {

                    trust_score:
                        Some(
                            trust_score
                        ),

                    completeness_score:
                        Some(
                            completeness_score
                        ),

                    consistency_score:
                        Some(
                            calculate_consistency_score(
                                &conflicts
                            )
                        ),

                    accuracy_score:
                        Some(
                            overall_quality_score
                        ),

                    overall_quality_score:
                        Some(
                            overall_quality_score
                        ),
                }
            ),

        conflicts,

        source_contributions:
            build_source_contributions(
                &entities
            ),

        semantic_identity:
            Some(
                format!( "entity_type={:?}",entities[0].entity_type)
            ),

        vector_namespace:
            Some(
                format!(
                    "tenant_{}_golden_records",
                    entities[0]
                        .tenant_id
                )
            ),

        version_info:
            VersionInfo {

                schema_version:
                    "1.0.0".to_string(),

                contract_version:
                    "1.0.0".to_string(),

                entity_version:
                    1,
            },

        audit:
            AuditMetadata {

                created_at:
                    Utc::now(),

                updated_at:
                    Utc::now(),

                created_by:
                    Some(
                        Uuid::nil()
                    ),

                updated_by:
                    Some(
                        Uuid::nil()
                    ),

                correlation_id:
                    Some(
                        execution_id
                    ),

                causation_id:
                    Some(
                        execution_id
                    ),

                request_id:
                    Some(
                        execution_id
                            .to_string()
                    ),
            },

        metadata,

        embedding_refs:
            vec![],

        lineage_refs:
            entities
                .iter()
                .map(|e| {
                    e.entity_id
                })
                .collect(),

        merge_refs:
            vec![],

        workflow_refs:
            vec![],

        policy_refs:
            vec![],

        survivorship_refs:
            vec![
                execution_id
            ],

        approval_refs:
            vec![],

        valid_from:
            Some(
                Utc::now()
            ),

        valid_to:
            None,
    }
}

//
// ========================================
// ATTRIBUTE EVALUATION
// ========================================
//

fn evaluate_attribute(
    attribute: &EntityAttribute,
    rule: &SurvivorshipRule,
) -> (f32, Vec<String>) {

    let mut score = 0.0;

    let mut reasons =
        Vec::<String>::new();

    match &rule.strategy {

        SurvivorshipStrategy::TrustedSource => {

            if let Some(index) =
                rule
                    .source_priority
                    .iter()
                    .position(|source| {

                        extract_source(
                            attribute
                        ) == *source
                    })
            {
                let priority_score =
                    (
                        rule
                            .source_priority
                            .len()
                            - index
                    ) as f32;

                score += priority_score;

                reasons.push(
                    format!(
                        "source_priority_rank={}",
                        index + 1
                    )
                );
            }
        }

        SurvivorshipStrategy::HighestConfidence => {

            if let Some(confidence) =
                &attribute.confidence
            {
                score += confidence.score;

                reasons.push(
                    format!(
                        "confidence={:.4}",
                        confidence.score
                    )
                );
            }
        }

        SurvivorshipStrategy::MostRecent => {

            if let Some(provenance) =
                &attribute.provenance
            {
                if let Some(ts) =
                    provenance
                        .source
                        .extracted_at
                {
                    score +=
                        ts.timestamp() as f32;

                    reasons.push(
                        "recency_applied"
                            .to_string()
                    );
                }
            }
        }

        SurvivorshipStrategy::LongestValue => {

            let len =
                attribute
                    .value
                    .to_string()
                    .len() as f32;

            score += len;

            reasons.push(
                format!(
                    "value_length={}",
                    len
                )
            );
        }

        SurvivorshipStrategy::MostComplete => {

            let completeness =
                calculate_completeness(
                    attribute
                );

            score += completeness;

            reasons.push(
                format!(
                    "completeness={:.4}",
                    completeness
                )
            );
        }

        SurvivorshipStrategy::AIRecommended => {

            score += 0.5;

            reasons.push(
                "ai_recommended"
                    .to_string()
            );
        }

        SurvivorshipStrategy::SemanticSimilarity => {

            score += 0.8;

            reasons.push(
                "semantic_similarity"
                    .to_string()
            );
        }

        SurvivorshipStrategy::HybridWeighted => {

            score += 1.2;

            reasons.push(
                "hybrid_weighted"
                    .to_string()
            );
        }

        SurvivorshipStrategy::Custom(name) => {

            score += 1.0;

            reasons.push(
                format!(
                    "custom_strategy={}",
                    name
                )
            );
        }
    }

    if let Some(confidence) =
        &attribute.confidence
    {
        score += confidence.score;

        reasons.push(
            format!(
                "confidence_boost={:.4}",
                confidence.score
            )
        );
    }

    (score, reasons)
}

//
// ========================================
// SOURCE EXTRACTION
// ========================================
//

fn extract_source(
    attribute: &EntityAttribute,
) -> String {

    attribute
        .provenance
        .as_ref()
        .map(|p| {

            p.source
                .source_system
                .clone()

        })
        .unwrap_or_else(|| {

            "unknown".to_string()

        })
}

//
// ========================================
// CONFIDENCE
// ========================================
//

fn calculate_confidence(
    candidates: &[AttributeCandidate],
) -> f32 {

    if candidates.len() <= 1 {
        return 1.0;
    }

    let winner =
        &candidates[0];

    let second =
        &candidates[1];

    let diff =
        winner.score
        - second.score;

    (
        diff
        / winner.score.max(1.0)
    )
    .min(1.0)
    .max(0.0)
}

//
// ========================================
// COMPLETENESS
// ========================================
//

fn calculate_completeness(
    attribute: &EntityAttribute,
) -> f32 {

    if attribute.value.is_null() {
        return 0.0;
    }

    match &attribute.value {

        serde_json::Value::String(v) => {

            if v.trim().is_empty() {
                0.0
            } else {
                1.0
            }
        }

        serde_json::Value::Array(v) => {

            if v.is_empty() {
                0.0
            } else {
                1.0
            }
        }

        serde_json::Value::Object(v) => {

            if v.is_empty() {
                0.0
            } else {
                1.0
            }
        }

        _ => 1.0,
    }
}

//
// ========================================
// RECORD COMPLETENESS
// ========================================
//

fn calculate_record_completeness(
    entities: &[CanonicalEntity],
) -> f32 {

    let total: usize =
        entities
            .iter()
            .map(|e| {
                e.attributes.len()
            })
            .sum();

    if total == 0 {
        return 0.0;
    }

    let populated: usize =
        entities
            .iter()
            .flat_map(|e| {
                &e.attributes
            })
            .filter(|a| {
                !a.value.is_null()
            })
            .count();

    populated as f32
        / total as f32
}

//
// ========================================
// TRUST SCORE
// ========================================
//

fn calculate_trust_score(
    entities: &[CanonicalEntity],
) -> f32 {

    let mut total = 0.0;

    let mut count = 0;

    for entity in entities {

        if let Some(value) =
            entity
                .metadata
                .get("trust_score")
        {
            if let Some(score) =
                value.as_f64()
            {
                total += score as f32;

                count += 1;
            }
        }
    }

    if count == 0 {
        return 0.5;
    }

    total / count as f32
}

//
// ========================================
// QUALITY SCORE
// ========================================
//

fn calculate_quality_score(
    entities: &[CanonicalEntity],
) -> f32 {

    let completeness =
        calculate_record_completeness(
            entities
        );

    let trust =
        calculate_trust_score(
            entities
        );

    (
        completeness + trust
    ) / 2.0
}

//
// ========================================
// CONSISTENCY SCORE
// ========================================
//

fn calculate_consistency_score(
    conflicts: &[AttributeConflict],
) -> f32 {

    if conflicts.is_empty() {
        return 1.0;
    }

    let resolved =
        conflicts
            .iter()
            .filter(|c| {
                c.resolved
            })
            .count();

    resolved as f32
        / conflicts.len() as f32
}

//
// ========================================
// SOURCE CONTRIBUTIONS
// ========================================
//

fn build_source_contributions(
    entities: &[CanonicalEntity],
) -> Vec<SourceContribution> {

    entities
        .iter()
        .map(|entity| {

            let contributed_attributes =
                entity
                    .attributes
                    .iter()
                    .map(|a| {
                        a.key.clone()
                    })
                    .collect();

            SourceContribution {

                source_system:
                    entity
                        .metadata
                        .get("source_system")
                        .and_then(|v| {
                            v.as_str()
                        })
                        .unwrap_or("unknown")
                        .to_string(),

                entity_id:
                    entity.entity_id,

                contribution_score:
                    calculate_entity_contribution(
                        entity
                    ),

                contributed_attributes,
            }

        })
        .collect()
}

//
// ========================================
// ENTITY CONTRIBUTION
// ========================================
//

fn calculate_entity_contribution(
    entity: &CanonicalEntity,
) -> f32 {

    let total_attributes =
        entity.attributes.len();

    if total_attributes == 0 {
        return 0.0;
    }

    let populated =
        entity
            .attributes
            .iter()
            .filter(|a| {
                !a.value.is_null()
            })
            .count();

    populated as f32
        / total_attributes as f32
}

//
// ========================================
// AI SCORE
// ========================================
//

fn calculate_ai_score(
    candidate: &AttributeCandidate,
) -> f32 {

    let confidence =
        candidate
            .attribute
            .confidence
            .as_ref()
            .map(|c| c.score)
            .unwrap_or(0.5);

    (
        candidate.score + confidence
    ) / 2.0
}

//
// ========================================
// POLICY DECISIONS
// ========================================
//

fn evaluate_policy_decisions(
    candidate: &AttributeCandidate,
) -> Vec<String> {

    let mut decisions =
        Vec::<String>::new();

    if candidate.score < 0.5 {

        decisions.push(
            "low_confidence_review_required"
                .to_string()
        );
    }

    decisions
}

//
// ========================================
// AI RECOMMENDATIONS
// ========================================
//

fn generate_ai_recommendations(
    candidate: &AttributeCandidate,
) -> Vec<String> {

    let mut recommendations =
        Vec::<String>::new();

    if candidate.score < 0.7 {

        recommendations.push(
            "consider_manual_review"
                .to_string()
        );
    }

    recommendations
}

//
// ========================================
// METADATA BUILDER
// ========================================
//

fn build_metadata(
    entries: Vec<(
        &str,
        serde_json::Value,
    )>,
) -> MetadataMap {

    let mut metadata =
        HashMap::new();

    for (key, value) in entries {

        metadata.insert(
            key.to_string(),
            value,
        );
    }

    metadata
}

//
// ========================================
// INTERNAL MODEL
// ========================================
//

#[derive(Debug, Clone)]
struct AttributeCandidate {

    pub entity_id:
        Uuid,

    pub attribute:
        EntityAttribute,

    pub score:
        f32,

    pub reasons:
        Vec<String>,
}

//
// ========================================
// EMPTY GOLDEN RECORD
// ========================================
//

fn build_empty_golden_record()
-> GoldenRecord {

    GoldenRecord {

        golden_record_id:
            Uuid::new_v4(),

        tenant_id:
            Uuid::nil(),

        entity_type:
            EntityType::Custom(
                "unknown".to_string()
            ),

        lifecycle_stage:
            GoldenRecordLifecycleStage::Created,

        status:
            GoldenRecordStatus::Draft,

        source_entities:
            vec![],

        golden_attributes:
            vec![],

        quality:
            Some(
                GoldenRecordQuality {

                    trust_score:
                        Some(0.0),

                    completeness_score:
                        Some(0.0),

                    consistency_score:
                        Some(1.0),

                    accuracy_score:
                        Some(0.0),

                    overall_quality_score:
                        Some(0.0),
                }
            ),

        conflicts:
            vec![],

        source_contributions:
            vec![],

        semantic_identity:
            Some(
                "empty-record"
                    .to_string()
            ),

        vector_namespace:
            Some(
                "default"
                    .to_string()
            ),

        version_info:
            VersionInfo {

                schema_version:
                    "1.0.0".to_string(),

                contract_version:
                    "1.0.0".to_string(),

                entity_version:
                    1,
            },

        audit:
            AuditMetadata {

                created_at:
                    Utc::now(),

                updated_at:
                    Utc::now(),

                created_by:
                    Some(
                        Uuid::nil()
                    ),

                updated_by:
                    Some(
                        Uuid::nil()
                    ),

                correlation_id:
                    None,

                causation_id:
                    None,

                request_id:
                    Some(
                        "empty-record"
                            .to_string()
                    ),
            },

        metadata:
            MetadataMap::new(),

        embedding_refs:
            vec![],

        lineage_refs:
            vec![],

        merge_refs:
            vec![],

        workflow_refs:
            vec![],

        policy_refs:
            vec![],

        survivorship_refs:
            vec![],

        approval_refs:
            vec![],

        valid_from:
            Some(
                Utc::now()
            ),

        valid_to:
            None,
    }
}