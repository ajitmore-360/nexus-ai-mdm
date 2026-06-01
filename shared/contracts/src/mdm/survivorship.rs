use chrono::{
    DateTime,
    Utc,
};

use serde::{
    Deserialize,
    Serialize,
};

use serde_json::Value;

use uuid::Uuid;

use crate::mdm::common::*;

//
// ========================================
// SURVIVORSHIP STRATEGY
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SurvivorshipStrategy {

    //
    // Most recent value
    //
    MostRecent,

    //
    // Highest confidence
    //
    HighestConfidence,

    //
    // Trusted source priority
    //
    TrustedSource,

    //
    // Longest usable value
    //
    LongestValue,

    //
    // Most complete value
    //
    MostComplete,

    //
    // AI/ML recommendation
    //
    AIRecommended,

    //
    // Semantic similarity
    //
    SemanticSimilarity,

    //
    // Weighted hybrid scoring
    //
    HybridWeighted,

    //
    // User-defined strategy
    //
    Custom(String),
}

//
// ========================================
// SURVIVORSHIP STATUS
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SurvivorshipStatus {

    Draft,

    Active,

    Disabled,

    Deprecated,
}

//
// ========================================
// SURVIVORSHIP RULE SCOPE
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SurvivorshipScope {

    Global,

    Tenant,

    EntityType(String),

    Attribute(String),
}

//
// ========================================
// SURVIVORSHIP RULE
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SurvivorshipRule {

    //
    // Rule identity
    //
    pub rule_id:
        Uuid,

    //
    // Rule name
    //
    pub rule_name:
        String,

    //
    // Description
    //
    pub description:
        Option<String>,

    //
    // Entity attribute
    //
    pub attribute:
        String,

    //
    // Strategy
    //
    pub strategy:
        SurvivorshipStrategy,

    //
    // Rule scope
    //
    pub scope:
        SurvivorshipScope,

    //
    // Source priority
    //
    pub source_priority:
        Vec<String>,

    //
    // Source weights
    //
    pub source_weights:
        MetadataMap,

    //
    // Minimum confidence
    //
    pub minimum_confidence:
        Option<f32>,

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
    // Manual override allowed
    //
    pub allow_manual_override:
        bool,

    //
    // Rule status
    //
    pub status:
        SurvivorshipStatus,

    //
    // Rule priority
    //
    pub priority:
        i32,

    //
    // Effective dates
    //
    pub effective_from:
        Option<DateTime<Utc>>,

    pub effective_to:
        Option<DateTime<Utc>>,

    //
    // Created by
    //
    pub created_by:
        Option<Uuid>,

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
// SURVIVORSHIP EVALUATION
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SurvivorshipEvaluation {

    //
    // Evaluation ID
    //
    pub evaluation_id:
        Uuid,

    //
    // Rule
    //
    pub rule_id:
        Uuid,

    //
    // Attribute
    //
    pub attribute:
        String,

    //
    // Selected value
    //
    pub selected_value:
        Value,

    //
    // Selected source
    //
    pub selected_source:
        Option<String>,

    //
    // Confidence
    //
    pub confidence:
        Option<f32>,

    //
    // Survivorship score
    //
    pub survivorship_score:
        Option<f32>,

    //
    // AI score
    //
    pub ai_score:
        Option<f32>,

    //
    // Explainability
    //
    pub reasoning:
        Option<String>,

    //
    // Policy decisions
    //
    pub policy_decisions:
        Vec<String>,

    //
    // Warnings
    //
    pub warnings:
        Vec<String>,

    //
    // Manual override
    //
    pub manually_overridden:
        bool,

    //
    // Override details
    //
    pub overridden_by:
        Option<Uuid>,

    pub overridden_at:
        Option<DateTime<Utc>>,

    //
    // Evaluation timestamp
    //
    pub evaluated_at:
        DateTime<Utc>,

    //
    // Metadata
    //
    pub metadata:
        MetadataMap,
}

//
// ========================================
// SURVIVORSHIP EXECUTION REQUEST
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SurvivorshipExecutionRequest {

    //
    // Execution ID
    //
    pub execution_id:
        Uuid,

    //
    // Tenant
    //
    pub tenant_id:
        Uuid,

    //
    // Entity type
    //
    pub entity_type:
        String,

    //
    // Rule IDs
    //
    pub rule_ids:
        Vec<Uuid>,

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
    // Correlation ID
    //
    pub correlation_id:
        Option<Uuid>,

    //
    // Metadata
    //
    pub metadata:
        MetadataMap,
}

//
// ========================================
// SURVIVORSHIP EXECUTION RESULT
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SurvivorshipExecutionResult {

    //
    // Execution ID
    //
    pub execution_id:
        Uuid,

    //
    // Success
    //
    pub success:
        bool,

    //
    // Evaluations
    //
    pub evaluations:
        Vec<SurvivorshipEvaluation>,

    //
    // Overall confidence
    //
    pub overall_confidence:
        Option<f32>,

    //
    // Execution time
    //
    pub execution_time_ms:
        u64,

    //
    // Explainability summary
    //
    pub summary:
        Option<String>,

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
    // Metadata
    //
    pub metadata:
        MetadataMap,
}

//
// ========================================
// SURVIVORSHIP EXECUTION METADATA
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SurvivorshipExecutionMetadata {

    //
    // Execution ID
    //
    pub execution_id:
        Uuid,

    //
    // Rules evaluated
    //
    pub evaluated_rules:
        usize,

    //
    // Candidates evaluated
    //
    pub evaluated_candidates:
        usize,

    //
    // Execution time
    //
    pub execution_time_ms:
        u64,

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
    // Engine version
    //
    pub engine_version:
        String,

    //
    // Metadata
    //
    pub metadata:
        MetadataMap,
}