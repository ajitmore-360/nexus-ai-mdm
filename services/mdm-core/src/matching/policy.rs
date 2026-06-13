use std::sync::Arc;

/// Single source of truth for every numeric threshold and weight used across
/// the matching pipeline (Matcher, ScoreCalculator, ReviewEngine).
///
/// Construct once at startup and share as `Arc<MatchingPolicy>`.
/// All defaults represent sensible production starting values.
#[derive(Debug, Clone)]
pub struct MatchingPolicy {
    // ---- decision thresholds ------------------------------------------------
    /// Score at or above which a pair is auto-merged without human review.
    pub auto_merge_threshold: f32,
    /// Score at or above which a pair is routed to the human review queue.
    pub review_threshold: f32,
    /// Maximum delta between top-two scores before flagging as ambiguous.
    pub ambiguity_delta: f32,

    // ---- field-level scoring weights ----------------------------------------
    pub exact_weight: f32,
    pub fuzzy_weight: f32,
    pub phonetic_weight: f32,
    pub semantic_weight: f32,
    pub vector_weight: f32,

    // ---- cluster master selection weights ------------------------------------
    pub master_weight_score: f32,
    pub master_weight_confidence: f32,
    pub master_weight_centrality: f32,

    // ---- pipeline limits -----------------------------------------------------
    pub max_clusters: usize,
}

impl Default for MatchingPolicy {
    fn default() -> Self {
        Self {
            auto_merge_threshold: 0.95,
            review_threshold:     0.75,
            ambiguity_delta:      0.03,

            exact_weight:    0.35,
            fuzzy_weight:    0.30,
            phonetic_weight: 0.10,
            semantic_weight: 0.15,
            vector_weight:   0.10,

            master_weight_score:      0.50,
            master_weight_confidence: 0.30,
            master_weight_centrality: 0.20,

            max_clusters: 100,
        }
    }
}

impl MatchingPolicy {
    pub fn arc_default() -> Arc<Self> {
        Arc::new(Self::default())
    }
}
