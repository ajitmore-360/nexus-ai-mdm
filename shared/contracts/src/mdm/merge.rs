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
    common::*,
    entity::*,
    golden_record::*,
    matching::*,
};

//
// ========================================
// MERGE STATUS
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MergeStatus {

    Draft,

    Pending,

    SubmittedForReview,

    UnderReview,

    Approved,

    Rejected,

    Scheduled,

    Executing,

    AutoMerged,

    Completed,

    Failed,

    RolledBack,

    Archived,
}

//
// ========================================
// MERGE STRATEGY
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MergeStrategy {

    SurvivorshipRules,

    AIRecommended,

    ManualReview,

    Hybrid,

    SemanticAI,

    PolicyDriven,

    GraphDriven,
}

//
// ========================================
// MERGE TYPE
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MergeType {

    Customer,

    Vendor,

    Material,

    Product,

    FinancialAccount,

    ReferenceData,

    Party,

    Location,

    Asset,

    Custom(String),
}

//
// ========================================
// CONFLICT SEVERITY
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ConflictSeverity {

    Low,

    Medium,

    High,

    Critical,
}

//
// ========================================
// MERGE EXECUTION STAGE
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MergeExecutionStage {

    CandidateSelection,

    PolicyValidation,

    ConflictAnalysis,

    StewardReview,

    SurvivorshipEvaluation,

    GoldenRecordGeneration,

    RelationshipRewiring,

    SearchReindexing,

    VectorReEmbedding,

    KafkaPublication,

    AuditPersistence,

    Completed,
}

//
// ========================================
// REVIEW DECISION
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ReviewDecision {

    Approved,

    Rejected,

    Escalated,

    NeedsMoreInformation,
}

//
// ========================================
// MERGE CANDIDATE
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MergeCandidate {

    //
    // Entity
    //
    pub entity_id: Uuid,

    //
    // Match confidence
    //
    pub confidence: Option<ConfidenceScore>,

    //
    // Source systems
    //
    pub source_systems: Vec<String>,

    //
    // Match explanations
    //
    pub match_explanations: Vec<String>,

    //
    // AI recommendation score
    //
    pub ai_recommendation_score: Option<f32>,

    //
    // Semantic similarity
    //
    pub semantic_similarity: Option<f32>,

    //
    // Graph similarity
    //
    pub graph_similarity: Option<f32>,

    //
    // Survivorship compatibility
    //
    pub survivorship_compatibility: Option<f32>,

    //
    // Recommended merge
    //
    pub recommended_for_merge: bool,

    //
    // Requires steward review
    //
    pub requires_review: bool,

    //
    // Metadata
    //
    pub metadata: MetadataMap,
}

//
// ========================================
// MERGE CONFLICT
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MergeConflict {

    //
    // Conflict ID
    //
    pub conflict_id: Uuid,

    //
    // Attribute
    //
    pub attribute: String,

    //
    // Severity
    //
    pub severity: ConflictSeverity,

    //
    // Conflicting values
    //
    pub conflicting_values:
        Vec<serde_json::Value>,

    //
    // Recommended value
    //
    pub recommended_value:
        Option<serde_json::Value>,

    //
    // AI reasoning
    //
    pub ai_reasoning:
        Option<String>,

    //
    // Resolution reason
    //
    pub resolution_reason:
        Option<String>,

    //
    // Manual review required
    //
    pub requires_manual_review:
        bool,

    //
    // Policy violations
    //
    pub policy_violations:
        Vec<String>,

    //
    // Metadata
    //
    pub metadata:
        MetadataMap,
}

//
// ========================================
// MERGE REVIEW
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MergeReview {

    //
    // Review ID
    //
    pub review_id: Uuid,

    //
    // Reviewer
    //
    pub reviewed_by: Uuid,

    //
    // Decision
    //
    pub decision: ReviewDecision,

    //
    // Notes
    //
    pub notes: Option<String>,

    //
    // Reviewed at
    //
    pub reviewed_at: DateTime<Utc>,
}

//
// ========================================
// MERGE EXECUTION TRACE
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MergeExecutionTrace {

    //
    // Stage
    //
    pub stage: MergeExecutionStage,

    //
    // Started
    //
    pub started_at: DateTime<Utc>,

    //
    // Completed
    //
    pub completed_at: Option<DateTime<Utc>>,

    //
    // Success
    //
    pub success: bool,

    //
    // Warnings
    //
    pub warnings: Vec<String>,

    //
    // Errors
    //
    pub errors: Vec<String>,

    //
    // Explainability
    //
    pub explanation: Option<String>,
}

//
// ========================================
// ENTITY SNAPSHOT
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EntitySnapshot {

    //
    // Snapshot ID
    //
    pub snapshot_id: Uuid,

    //
    // Captured entity
    //
    pub entity: CanonicalEntity,

    //
    // Captured at
    //
    pub captured_at: DateTime<Utc>,
}

//
// ========================================
// MERGE REQUEST
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MergeRequest {

    //
    // Merge request ID
    //
    pub merge_request_id: Uuid,

    //
    // Workflow ID
    //
    pub workflow_id: Option<Uuid>,

    //
    // Tenant
    //
    pub tenant_id: Uuid,

    //
    // Correlation
    //
    pub correlation_id:
        Option<Uuid>,

    //
    // Merge type
    //
    pub merge_type:
        MergeType,

    //
    // Initiator
    //
    pub initiated_by:
        Option<Uuid>,

    //
    // Strategy
    //
    pub strategy:
        MergeStrategy,

    //
    // Status
    //
    pub status:
        MergeStatus,

    //
    // Primary entity
    //
    pub primary_entity_id:
        Uuid,

    //
    // Candidate entities
    //
    pub candidate_entities:
        Vec<MergeCandidate>,

    //
    // Match results
    //
    pub match_results:
        Vec<MatchCandidate>,

    //
    // Proposed golden record
    //
    pub proposed_golden_record:
        Option<GoldenRecord>,

    //
    // Conflicts
    //
    pub conflicts:
        Vec<MergeConflict>,

    //
    // Reviews
    //
    pub reviews:
        Vec<MergeReview>,

    //
    // Execution trace
    //
    pub execution_trace:
        Vec<MergeExecutionTrace>,

    //
    // Pre-merge snapshots
    //
    pub snapshots:
        Vec<EntitySnapshot>,

    //
    // AI merge summary
    //
    pub ai_merge_summary:
        Option<String>,

    //
    // Policy decisions
    //
    pub policy_decisions:
        Vec<String>,

    //
    // Approval workflow
    //
    pub approved_by:
        Option<Uuid>,

    pub approved_at:
        Option<DateTime<Utc>>,

    //
    // Rejection workflow
    //
    pub rejected_by:
        Option<Uuid>,

    pub rejected_at:
        Option<DateTime<Utc>>,

    pub rejection_reason:
        Option<String>,

    //
    // Rollback
    //
    pub rollback_of_merge_id:
        Option<Uuid>,

    //
    // Async execution
    //
    pub async_execution:
        bool,

    //
    // Audit
    //
    pub audit:
        AuditMetadata,

    //
    // Metadata
    //
    pub metadata:
        MetadataMap,
}

//
// ========================================
// MERGE EXECUTION RESULT
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MergeExecutionResult {

    //
    // Merge request
    //
    pub merge_request_id:
        Uuid,

    //
    // Surviving entity
    //
    pub surviving_entity:
        CanonicalEntity,

    //
    // Merged entities
    //
    pub merged_entity_ids:
        Vec<Uuid>,

    //
    // Generated golden record
    //
    pub generated_golden_record:
        Option<GoldenRecord>,

    //
    // Execution timing
    //
    pub execution_started_at:
        DateTime<Utc>,

    pub execution_completed_at:
        DateTime<Utc>,

    //
    // Status
    //
    pub success:
        bool,

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

    //
    // Explainability
    //
    pub execution_summary:
        Option<String>,

    //
    // Execution stages
    //
    pub execution_trace:
        Vec<MergeExecutionTrace>,

    //
    // Lineage references
    //
    pub lineage_event_ids:
        Vec<Uuid>,

    //
    // Kafka events published
    //
    pub published_event_ids:
        Vec<Uuid>,

    //
    // Search reindex status
    //
    pub search_reindexed:
        bool,

    //
    // Embeddings regenerated
    //
    pub embeddings_regenerated:
        bool,

    //
    // Metadata
    //
    pub metadata:
        MetadataMap,
}