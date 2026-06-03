use std::collections::HashMap;

use anyhow::Result;
use strsim::{
    jaro_winkler,
    normalized_levenshtein,
};
use tracing::instrument;

use shared_contracts::mdm::{
    common::MetadataMap,
    entity::{
        CanonicalEntity,
        EntityAttribute,
    },
    matching::{
        FieldMatchResult,
        MatchCandidate,
        MatchStatus,
        MatchStrategy,
    },
};

//
// ============================================================
// CONFIG
// ============================================================
//

#[derive(Debug, Clone)]
pub struct ScoreConfiguration {
    pub auto_merge_threshold: f32,
    pub review_threshold: f32,

    pub exact_weight: f32,
    pub fuzzy_weight: f32,
    pub phonetic_weight: f32,
    pub semantic_weight: f32,
    pub vector_weight: f32,
}

impl Default for ScoreConfiguration {
    fn default() -> Self {
        Self {
            auto_merge_threshold: 0.95,
            review_threshold: 0.75,

            exact_weight: 0.35,
            fuzzy_weight: 0.30,
            phonetic_weight: 0.10,
            semantic_weight: 0.15,
            vector_weight: 0.10,
        }
    }
}

//
// ============================================================
// SCORE CALCULATOR
// ============================================================
//

pub struct ScoreCalculator {
    config: ScoreConfiguration,
}

impl ScoreCalculator {
    pub fn new(
        config: ScoreConfiguration,
    ) -> Self {
        Self { config }
    }

    //
    // ========================================================
    // SCORE CANDIDATE
    // ========================================================
    //

    #[instrument(skip(self, source, candidate))]
    pub fn score_candidate(
        &self,
        source: &CanonicalEntity,
        candidate: &CanonicalEntity,
        vector_similarity: Option<f32>,
    ) -> Result<MatchCandidate> {

        let mut field_matches =
            Vec::<FieldMatchResult>::new();

        let mut total_weight = 0.0f32;
        let mut weighted_score = 0.0f32;

        let source_map =
            self.attribute_map(source);

        let candidate_map =
            self.attribute_map(candidate);

        for (field, source_attr)
            in &source_map
        {
            if let Some(
                candidate_attr,
            ) = candidate_map.get(field)
            {
                let result =
                    self.score_field(
                        source_attr,
                        candidate_attr,
                    );

                weighted_score +=
                    result.score;

                total_weight += 1.0;

                field_matches.push(
                    result,
                );
            }
        }

        let field_score =
            if total_weight > 0.0 {
                weighted_score
                    / total_weight
            } else {
                0.0
            };

        let vector_score =
            vector_similarity
                .unwrap_or(0.0);

        let final_score =
            (field_score * 0.90)
                + (vector_score * 0.10);

        let confidence =
            self.calculate_confidence(
                final_score,
                field_matches.len(),
            );

        let status =
            self.determine_status(
                final_score,
            );

        let requires_review =
            matches!(
                status,
                MatchStatus::RequiresReview
            );

        let explanations =
            self.build_explanations(
                &field_matches,
            );

        Ok(
            MatchCandidate {
                entity_id:
                    candidate.entity_id,

                status,

                score:
                    final_score,

                confidence,

                vector_similarity,

                graph_similarity:
                    None,

                ai_score:
                    None,

                survivorship_compatibility:
                    Some(
                        self
                            .survivorship_compatibility(
                                source,
                                candidate,
                            )
                    ),

                explanations,

                field_matches,

                policy_decisions:
                    vec![],

                recommended_for_merge:
                    final_score
                        >= self
                            .config
                            .auto_merge_threshold,

                requires_human_review:
                    requires_review,

                metadata:
                    MetadataMap::new(),
            }
        )
    }

    //
    // ========================================================
    // FIELD SCORING
    // ========================================================
    //

    fn score_field(
        &self,
        source: &EntityAttribute,
        candidate: &EntityAttribute,
    ) -> FieldMatchResult {

        let source_value =
            self.extract_string(
                source,
            );

        let candidate_value =
            self.extract_string(
                candidate,
            );

        let exact =
            self.exact_similarity(
                &source_value,
                &candidate_value,
            );

        let fuzzy =
            self.fuzzy_similarity(
                &source_value,
                &candidate_value,
            );

        let phonetic =
            self.phonetic_similarity(
                &source_value,
                &candidate_value,
            );

        let score =
            exact
                * self.config.exact_weight
            + fuzzy
                * self.config.fuzzy_weight
            + phonetic
                * self.config.phonetic_weight;

        FieldMatchResult {
            field:
                source.key.clone(),

            source_value:
                Some(
                    source.value.clone(),
                ),

            candidate_value:
                Some(
                    candidate.value.clone(),
                ),

            score,

            confidence: None,

            strategy:
                MatchStrategy::Hybrid,

            semantic_similarity:
                Some(fuzzy),

            explanation:
                vec![
                    format!(
                        "Exact={:.2}",
                        exact
                    ),
                    format!(
                        "Fuzzy={:.2}",
                        fuzzy
                    ),
                    format!(
                        "Phonetic={:.2}",
                        phonetic
                    ),
                ],

            metadata:
                MetadataMap::new(),
        }
    }

    //
    // ========================================================
    // EXACT
    // ========================================================
    //

    fn exact_similarity(
        &self,
        a: &str,
        b: &str,
    ) -> f32 {

        if a.trim()
            .eq_ignore_ascii_case(
                b.trim(),
            )
        {
            1.0
        } else {
            0.0
        }
    }

    //
    // ========================================================
    // FUZZY
    // ========================================================
    //

    fn fuzzy_similarity(
        &self,
        a: &str,
        b: &str,
    ) -> f32 {

        let jw =
            jaro_winkler(a, b)
                as f32;

        let lev =
            normalized_levenshtein(
                a, b,
            ) as f32;

        (jw + lev) / 2.0
    }

    //
    // ========================================================
    // PHONETIC
    // ========================================================
    //

    fn phonetic_similarity(
        &self,
        a: &str,
        b: &str,
    ) -> f32 {

        let sa =
            self.soundex(a);

        let sb =
            self.soundex(b);

        if sa == sb {
            1.0
        } else {
            0.0
        }
    }

    //
    // ========================================================
    // SOUNDEX
    // ========================================================
    //

    fn soundex(
        &self,
        input: &str,
    ) -> String {

        let input =
            input.to_uppercase();

        let mut chars =
            input.chars();

        let first =
            chars.next()
                .unwrap_or('X');

        let mut result =
            String::new();

        result.push(first);

        for c in chars {

            let digit =
                match c {

                    'B' | 'F'
                    | 'P'
                    | 'V' => '1',

                    'C' | 'G'
                    | 'J'
                    | 'K'
                    | 'Q'
                    | 'S'
                    | 'X'
                    | 'Z' => '2',

                    'D' | 'T' => '3',

                    'L' => '4',

                    'M' | 'N' => '5',

                    'R' => '6',

                    _ => '0',
                };

            if digit != '0' {
                result.push(digit);
            }
        }

        result
            .chars()
            .take(4)
            .collect()
    }

    //
    // ========================================================
    // CONFIDENCE
    // ========================================================
    //

    fn calculate_confidence(
        &self,
        score: f32,
        matched_fields: usize,
    ) -> f32 {

        let coverage =
            (matched_fields
                as f32
                / 10.0)
                .min(1.0);

        ((score * 0.80)
            + (coverage * 0.20))
            .min(1.0)
    }

    //
    // ========================================================
    // STATUS
    // ========================================================
    //

    fn determine_status(
        &self,
        score: f32,
    ) -> MatchStatus {

        if score
            >= self
                .config
                .auto_merge_threshold
        {
            MatchStatus::Matched
        } else if score
            >= self
                .config
                .review_threshold
        {
            MatchStatus::RequiresReview
        } else {
            MatchStatus::Rejected
        }
    }

    //
    // ========================================================
    // SURVIVORSHIP COMPATIBILITY
    // ========================================================
    //

    fn survivorship_compatibility(
        &self,
        source: &CanonicalEntity,
        candidate: &CanonicalEntity,
    ) -> f32 {

        let source_attrs =
            source.attributes.len();

        let target_attrs =
            candidate.attributes.len();

        let max =
            source_attrs.max(
                target_attrs,
            ) as f32;

        if max == 0.0 {
            return 0.0;
        }

        (source_attrs.min(
            target_attrs,
        ) as f32)
            / max
    }

    //
    // ========================================================
    // ATTRIBUTE MAP
    // ========================================================
    //

    fn attribute_map(
        &self,
        entity: &CanonicalEntity,
    ) -> HashMap<
        String,
        EntityAttribute,
    > {

        entity
            .attributes
            .iter()
            .cloned()
            .map(
                |a| (
                    a.key
                        .to_lowercase(),
                    a,
                )
            )
            .collect()
    }

    //
    // ========================================================
    // EXPLANATIONS
    // ========================================================
    //

    fn build_explanations(
        &self,
        fields:
            &[FieldMatchResult],
    ) -> Vec<String> {

        fields
            .iter()
            .map(|f| {
                format!(
                    "{} score {:.2}",
                    f.field,
                    f.score
                )
            })
            .collect()
    }

    //
    // ========================================================
    // STRING EXTRACTION
    // ========================================================
    //

    fn extract_string(
        &self,
        attr: &EntityAttribute,
    ) -> String {

        attr.value
            .as_str()
            .unwrap_or("")
            .trim()
            .to_lowercase()
    }
}