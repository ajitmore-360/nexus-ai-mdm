use chrono::{
    DateTime,
    Utc,
};

use serde::{
    Deserialize,
    Serialize,
};

use uuid::Uuid;

use crate::mdm::{
    common::{
        AuditMetadata,
        ConfidenceScore,
        MetadataMap,
        VersionInfo,
    },
    entity::{
        CanonicalEntity,
    },
};

//
// ========================================
// MATCH STRATEGY
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MatchStrategy {

    //
    // Exact deterministic
    //
    Deterministic,

    //
    // Fuzzy matching
    //
    Fuzzy,

    //
    // AI/ML enhanced
    //
    AIEnhanced,

    //
    // Hybrid weighted
    //
    Hybrid,

    //
    // Semantic/vector similarity
    //
    Semantic,

    //
    // Graph/entity-network matching
    //
    Graph,

    //
    // Ensemble multi-model
    //
    Ensemble,

    //
    // User-defined strategy
    //
    Custom(String),
}

//
// ========================================
// MATCH STATUS
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MatchStatus {

    Pending,

    Matched,

    PossibleMatch,

    RequiresReview,

    Rejected,

    AutoMerged,
}

//
// ========================================
// FIELD MATCH RESULT
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FieldMatchResult {

    //
    // Field name
    //
    pub field:
        String,

    //
    // Source value
    //
    pub source_value:
        Option<serde_json::Value>,

    //
    // Candidate value
    //
    pub candidate_value:
        Option<serde_json::Value>,

    //
    // Match score
    //
    pub score:
        f32,

    //
    // Confidence
    //
    pub confidence:
        Option<ConfidenceScore>,

    //
    // Matching strategy
    //
    pub strategy:
        MatchStrategy,

    //
    // Semantic similarity
    //
    pub semantic_similarity:
        Option<f32>,

    //
    // Explanation
    //
    pub explanation:
        Vec<String>,

    //
    // Metadata
    //
    pub metadata:
        MetadataMap,
}

//
// ========================================
// BLOCKING DIAGNOSTICS
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BlockingDiagnostics {

    //
    // Applied rules
    //
    pub applied_rules:
        Vec<String>,

    //
    // Block keys generated
    //
    pub generated_keys:
        Vec<String>,

    //
    // Candidates reduced
    //
    pub reduced_candidates:
        usize,

    //
    // Metadata
    //
    pub metadata:
        MetadataMap,
}

//
// ========================================
// MATCH CANDIDATE
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatchCandidate {

    //
    // Candidate entity
    //
    pub entity_id:
        Uuid,

    //
    // Match status
    //
    pub status:
        MatchStatus,

    //
    // Overall score
    //
    pub score:
        f32,

    //
    // Confidence
    //
    pub confidence:
        f32,

    //
    // Vector similarity
    //
    pub vector_similarity:
        Option<f32>,

    //
    // Graph similarity
    //
    pub graph_similarity:
        Option<f32>,

    //
    // AI score
    //
    pub ai_score:
        Option<f32>,

    //
    // Survivorship compatibility
    //
    pub survivorship_compatibility:
        Option<f32>,

    //
    // Match explanations
    //
    pub explanations:
        Vec<String>,

    //
    // Field-level results
    //
    pub field_matches:
        Vec<FieldMatchResult>,

    //
    // Policy decisions
    //
    pub policy_decisions:
        Vec<String>,

    //
    // Merge recommendation
    //
    pub recommended_for_merge:
        bool,

    //
    // Review required
    //
    pub requires_human_review:
        bool,

    //
    // Metadata
    //
    pub metadata:
        MetadataMap,
}

//
// ========================================
// MATCH REQUEST
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatchRequest {

    //
    // Request ID
    //
    pub request_id:
        Uuid,

    //
    // Tenant
    //
    pub tenant_id:
        Uuid,

    //
    // Correlation ID
    //
    pub correlation_id:
        Option<Uuid>,

    //
    // Entity type
    //
    pub entity_type:
        String,

    //
    // Incoming entity
    //
    pub entity:
        CanonicalEntity,

    //
    // Match threshold
    //
    pub threshold:
        Option<f32>,

    //
    // Blocking rules
    //
    pub blocking_rules:
        Vec<String>,

    //
    // Match strategy
    //
    pub strategy:
        MatchStrategy,

    //
    // AI-assisted
    //
    pub ai_assisted:
        bool,

    //
    // Explainability enabled
    //
    pub explainability_enabled:
        bool,

    //
    // Include semantic matching
    //
    pub semantic_matching:
        bool,

    //
    // Include graph matching
    //
    pub graph_matching:
        bool,

    //
    // Max candidates
    //
    pub max_candidates:
        usize,

    //
    // Metadata
    //
    pub metadata:
        MetadataMap,
}

//
// ========================================
// MATCH CLUSTER
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatchCluster {

    //
    // Cluster ID
    //
    pub cluster_id:
        Uuid,

    //
    // Cluster entities
    //
    pub entity_ids:
        Vec<Uuid>,

    //
    // Cluster confidence
    //
    pub confidence:
        f32,

    //
    // Suggested golden entity
    //
    pub suggested_master:
        Option<Uuid>,

    //
    // Metadata
    //
    pub metadata:
        MetadataMap,
}

//
// ========================================
// MATCH EXECUTION METADATA
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatchExecutionMetadata {

    //
    // Execution started
    //
    pub started_at:
        DateTime<Utc>,

    //
    // Execution completed
    //
    pub completed_at:
        DateTime<Utc>,

    //
    // Duration
    //
    pub execution_time_ms:
        u64,

    //
    // Candidates evaluated
    //
    pub candidates_evaluated:
        usize,

    //
    // Blocking reduction
    //
    pub blocking_reduction:
        Option<f32>,

    //
    // AI-assisted
    //
    pub ai_assisted:
        bool,

    //
    // Semantic matching enabled
    //
    pub semantic_matching:
        bool,

    //
    // Graph matching enabled
    //
    pub graph_matching:
        bool,

    //
    // Match engine version
    //
    pub engine_version:
        String,

    //
    // Audit
    //
    pub audit:
        AuditMetadata,

    //
    // Versioning
    //
    pub version_info:
        VersionInfo,

    //
    // Metadata
    //
    pub metadata:
        MetadataMap,
}

//
// ========================================
// MATCH RESPONSE
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatchResponse {

    //
    // Request ID
    //
    pub request_id:
        Uuid,

    //
    // Match candidates
    //
    pub matches:
        Vec<MatchCandidate>,

    //
    // Suggested clusters
    //
    pub clusters:
        Vec<MatchCluster>,

    //
    // Blocking diagnostics
    //
    pub blocking:
        Option<BlockingDiagnostics>,

    //
    // Execution metadata
    //
    pub metadata:
        MatchExecutionMetadata,

    //
    // Warnings
    //
    pub warnings:
        Vec<String>,

    //
    // Errors
    //
    pub errors:
        Vec<String>,
}