// ============================================================
// Internal matching-engine execution models.
// Many structs here represent the full matching domain model;
// not all are instantiated in the current pipeline but are part
// of the planned architecture.
// ============================================================
#![allow(dead_code)]

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use uuid::Uuid;

pub const MATCH_ENGINE_VERSION: &str =
    "nexus-match-engine-v2";

use contracts::mdm::{
    entity::CanonicalEntity,
    matching::{
        BlockingDiagnostics,
        FieldMatchResult,
        MatchCandidate,
    },
};

//
// ============================================================
// BLOCKING RESULT
// ============================================================
//

#[derive(Debug, Clone)]
pub struct BlockingResult {
    pub candidate_ids: HashSet<Uuid>,
    pub diagnostics: BlockingDiagnostics,
}

//
// ============================================================
// CANDIDATE ENTITY
// ============================================================
//

#[derive(Debug, Clone)]
pub struct CandidateEntity {
    pub entity: CanonicalEntity,

    pub blocking_score: f32,

    pub candidate_source: CandidateSource,

    pub vector_similarity: Option<f32>,

    pub graph_similarity: Option<f32>,
}
//
// ============================================================
// ATTRIBUTE PAIR
// ============================================================
//

#[derive(Debug, Clone)]
pub struct AttributePair {
    pub field_name: String,
    pub source_value: Option<String>,
    pub target_value: Option<String>,
}

//
// ============================================================
// FEATURE VECTOR
// ============================================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeatureVector {
    pub exact_similarity: f32,
    pub fuzzy_similarity: f32,
    pub phonetic_similarity: f32,
    pub semantic_similarity: f32,
    pub vector_similarity: f32,
    pub graph_similarity: f32,
    pub completeness_similarity: f32,
    pub source_trust_similarity: f32,
}

impl Default for FeatureVector {
    fn default() -> Self {
        Self {
            exact_similarity: 0.0,
            fuzzy_similarity: 0.0,
            phonetic_similarity: 0.0,
            semantic_similarity: 0.0,
            vector_similarity: 0.0,
            graph_similarity: 0.0,
            completeness_similarity: 0.0,
            source_trust_similarity: 0.0,
        }
    }
}

//
// ============================================================
// FIELD SCORE
// ============================================================
//

#[derive(Debug, Clone)]
pub struct FieldScore {
    pub field_name: String,
    pub score: f32,
    pub weight: f32,
    pub explanation: String,
}

//
// ============================================================
// MATCH SCORE BREAKDOWN
// ============================================================
//

#[derive(Debug, Clone)]
pub struct MatchScoreBreakdown {
    pub total_score: f32,
    pub confidence: f32,

    pub exact_score: f32,
    pub weighted_score: f32,
    pub fuzzy_score: f32,
    pub phonetic_score: f32,
    pub semantic_score: f32,
    pub vector_score: f32,
    pub graph_score: f32,
    pub feature_importance: Vec<FeatureImportance>,
    pub field_scores: Vec<FieldScore>,
}

//
// ============================================================
// MATCH THRESHOLDS
// ============================================================
//

#[derive(Debug, Clone)]
pub struct MatchThresholds {
    pub auto_merge: f32,
    pub probable_match: f32,
    pub review_required: f32,
}

impl Default for MatchThresholds {
    fn default() -> Self {
        Self {
            auto_merge: 0.95,
            probable_match: 0.85,
            review_required: 0.70,
        }
    }
}

//
// ============================================================
// MATCH CONFIGURATION
// ============================================================
//

#[derive(Debug, Clone)]
pub struct MatchingConfiguration {
    pub thresholds: MatchThresholds,

    pub enable_ai: bool,
    pub enable_vectors: bool,
    pub enable_graph_matching: bool,

    pub max_candidates: usize,

    pub attribute_weights: HashMap<String, f32>,
}

impl Default for MatchingConfiguration {
    fn default() -> Self {
        Self {
            thresholds: MatchThresholds::default(),

            enable_ai: true,
            enable_vectors: true,
            enable_graph_matching: false,

            max_candidates: 1000,

            attribute_weights: HashMap::new(),
        }
    }
}

//
// ============================================================
// MATCH EXECUTION CONTEXT
// ============================================================
//

#[derive(Debug, Clone)]
pub struct MatchExecutionContext {
    pub execution_id: Uuid,
    pub tenant_id: Uuid,

    pub started_at: DateTime<Utc>,

    pub total_candidates: usize,

    pub blocking_duration_ms: u64,
    pub scoring_duration_ms: u64,

    pub warnings: Vec<String>,
}

//
// ============================================================
// MATCH EVALUATION RESULT
// ============================================================
//

#[derive(Debug, Clone)]
pub struct MatchEvaluationResult {
    pub candidate: MatchCandidate,

    pub breakdown: MatchScoreBreakdown,

    pub field_results: Vec<FieldMatchResult>,

    pub metrics: CandidateEvaluationMetrics,
}

//
// ============================================================
// VECTOR SEARCH RESULT
// ============================================================
//

#[derive(Debug, Clone)]
pub struct VectorSearchResult {
    pub entity_id: Uuid,
    pub similarity: f32,
}

//
// ============================================================
// GRAPH SEARCH RESULT
// ============================================================
//

#[derive(Debug, Clone)]
pub struct GraphSearchResult {
    pub entity_id: Uuid,
    pub relationship_score: f32,
}

//
// ============================================================
// HUMAN REVIEW TASK
// ============================================================
//

#[derive(Debug, Clone)]
pub struct HumanReviewTask {
    pub review_id: Uuid,

    pub source_entity_id: Uuid,

    pub candidate_entity_id: Uuid,

    pub score: f32,

    pub reason: String,
}

//
// ============================================================
// CLUSTER NODE
// ============================================================
//

#[derive(Debug, Clone)]
pub struct ClusterNode {
    pub entity_id: Uuid,
    pub confidence: f32,
}

//
// ============================================================
// MATCH CLUSTER GRAPH
// ============================================================
//

#[derive(Debug, Clone)]
pub struct MatchClusterGraph {
    pub nodes: Vec<ClusterNode>,
    pub edges: Vec<(Uuid, Uuid, f32)>,
    pub confidence: ClusterConfidence,
}

//
// ============================================================
// BLOCKING STATISTICS
// ============================================================
//

#[derive(Debug, Clone)]
pub struct BlockingStatistics {
    pub total_records: usize,
    pub candidate_records: usize,
    pub reduction_percentage: f32,
    pub rule_metrics: Vec<BlockingRuleMetrics>,
}

//
// ============================================================
// ENGINE METRICS
// ============================================================
//

#[derive(Debug, Clone)]
pub struct MatchingEngineMetrics {
    pub execution_id: Uuid,
    pub started_at: DateTime<Utc>,
    pub completed_at: Option<DateTime<Utc>>,
    pub blocking_time_ms: u64,
    pub scoring_time_ms: u64,
    pub clustering_time_ms: u64,
    pub candidates_generated: usize,
    pub candidates_scored: usize,
    pub matches_found: usize,
    pub review_cases_created: usize,
    pub clusters_created: usize,
    pub average_score: f32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MatchDecision {
    AutoMerge,
    HumanReview,
    NoMatch,
}

#[derive(Debug, Clone)]
pub enum ReviewPriority {
    Low,
    Medium,
    High,
    Critical,
}

#[derive(Debug, Clone)]
pub struct ReviewCase {
    pub review_id: Uuid,
    pub source_entity_id: Uuid,
    pub candidate_entity_id: Uuid,
    pub score: f64,
    pub priority: ReviewPriority,
    pub reason: String,
    pub review_reason: ReviewReason,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone)]
pub enum CandidateSource {
    Blocking,
    VectorSearch,
    GraphSearch,
    ExternalReference,
    HumanSuggested,
}

#[derive(Debug, Clone)]
pub struct FeatureImportance {
    pub feature_name: String,
    pub contribution: f32,
}

#[derive(Debug, Clone)]
pub struct CandidateEvaluationMetrics {

    pub fields_compared: usize,

    pub fields_matched: usize,

    pub fields_missing: usize,

    pub exact_matches: usize,

    pub fuzzy_matches: usize,
}

#[derive(Debug, Clone)]
pub enum ReviewReason {
    ScoreInGreyZone,
    ConflictingAttributes,
    MultipleHighConfidenceMatches,
    PolicyViolation,
    AIRecommendation,
}

#[derive(Debug, Clone)]
pub struct ClusterConfidence {

    pub average_score: f32,

    pub minimum_score: f32,

    pub maximum_score: f32,
}

#[derive(Debug, Clone)]
pub struct BlockingRuleMetrics {
   pub rule_name: String,
    pub candidates_generated: usize,
    pub reduction_percentage: f32,
}

//
// ============================================================
// MATCH RESULT (pairwise edge for clustering)
// ============================================================
//

#[derive(Debug, Clone)]
pub struct MatchResult {
    pub source_entity_id: Uuid,
    pub candidate_entity_id: Uuid,
    pub score: f64,
    pub confidence: f64,
}



