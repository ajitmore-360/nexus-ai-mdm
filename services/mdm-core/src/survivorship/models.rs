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

use contracts::mdm::{
    common::{
        ConfidenceScore,
        MetadataMap,
    },
    survivorship::{
        SurvivorshipStrategy,
    },
};

//
// ========================================
// CANDIDATE SCORE
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CandidateScore {

    //
    // Source entity
    //
    pub entity_id: Uuid,

    //
    // Source system
    //
    pub source: String,

    //
    // Candidate value
    //
    pub value: Value,

    //
    // Survivorship score
    //
    pub score: f32,

    //
    // Confidence
    //
    pub confidence:
        Option<ConfidenceScore>,

    //
    // Explainability
    //
    pub reasons:
        Vec<String>,

    //
    // AI contribution
    //
    pub ai_score:
        Option<f32>,

    //
    // Metadata
    //
    pub metadata:
        MetadataMap,
}

//
// ========================================
// FIELD DECISION
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FieldDecision {

    //
    // Decision ID
    //
    pub decision_id:
        Uuid,

    //
    // Attribute name
    //
    pub field:
        String,

    //
    // Winning value
    //
    pub chosen_value:
        Value,

    //
    // Winning source
    //
    pub source:
        String,

    //
    // Selected entity
    //
    pub selected_entity_id:
        Uuid,

    //
    // Confidence
    //
    pub confidence:
        f32,

    //
    // Winning score
    //
    pub winning_score:
        f32,

    //
    // Applied strategy
    //
    pub strategy:
        SurvivorshipStrategy,

    //
    // All evaluated candidates
    //
    pub candidates:
        Vec<CandidateScore>,

    //
    // Explainability
    //
    pub reason:
        String,

    //
    // Policy decisions
    //
    pub policy_decisions:
        Vec<String>,

    //
    // AI recommendations
    //
    pub ai_recommendations:
        Vec<String>,

    //
    // Manual override
    //
    pub manually_overridden:
        bool,

    //
    // Override metadata
    //
    pub overridden_by:
        Option<Uuid>,

    pub overridden_at:
        Option<DateTime<Utc>>,

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
    // Candidate attributes
    //
    pub evaluated_candidates:
        usize,

    //
    // Execution duration
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

//
// ========================================
// SURVIVORSHIP EXPLANATION
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SurvivorshipExplanation {

    //
    // Attribute-level decisions
    //
    pub decisions:
        Vec<FieldDecision>,

    //
    // Overall confidence
    //
    pub overall_confidence:
        Option<f32>,

    //
    // Execution metadata
    //
    pub execution_metadata:
        SurvivorshipExecutionMetadata,

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
    // Metadata
    //
    pub metadata:
        MetadataMap,
}