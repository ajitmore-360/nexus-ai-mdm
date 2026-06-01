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
};

//
// ========================================
// GOLDEN RECORD STATUS
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum GoldenRecordStatus {

    Draft,

    Active,

    PendingApproval,

    UnderReview,

    Superseded,

    Archived,

    SoftDeleted,
}

//
// ========================================
// GOLDEN RECORD LIFECYCLE
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum GoldenRecordLifecycleStage {

    Created,

    Matched,

    SurvivorshipApplied,

    AIValidated,

    HumanReviewed,

    Approved,

    Published,

    Archived,
}

//
// ========================================
// ATTRIBUTE CONFLICT
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AttributeConflict {

    //
    // Attribute name
    //
    pub attribute:
        String,

    //
    // Conflicting values
    //
    pub conflicting_values:
        Vec<serde_json::Value>,

    //
    // Sources involved
    //
    pub sources:
        Vec<String>,

    //
    // Resolution status
    //
    pub resolved:
        bool,

    //
    // Resolution notes
    //
    pub resolution_notes:
        Option<String>,
}

//
// ========================================
// SOURCE CONTRIBUTION
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SourceContribution {

    //
    // Source system
    //
    pub source_system:
        String,

    //
    // Entity ID
    //
    pub entity_id:
        Uuid,

    //
    // Contribution score
    //
    pub contribution_score:
        f32,

    //
    // Attributes contributed
    //
    pub contributed_attributes:
        Vec<String>,
}

//
// ========================================
// GOLDEN ATTRIBUTE
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GoldenAttribute {

    //
    // Golden attribute ID
    //
    pub golden_attribute_id:
        Uuid,

    //
    // Mastered attribute
    //
    pub attribute:
        EntityAttribute,

    //
    // Selected source entity
    //
    pub selected_from_entity:
        Uuid,

    //
    // Source system
    //
    pub selected_from_source:
        Option<String>,

    //
    // Survivorship rule
    //
    pub survivorship_rule_id:
        Option<Uuid>,

    //
    // Survivorship execution
    //
    pub survivorship_execution_id:
        Option<Uuid>,

    //
    // Survivorship score
    //
    pub survivorship_score:
        Option<f32>,

    //
    // AI confidence
    //
    pub ai_confidence:
        Option<f32>,

    //
    // Human override
    //
    pub overridden_by_user:
        Option<Uuid>,

    //
    // Override timestamp
    //
    pub overridden_at:
        Option<DateTime<Utc>>,

    //
    // Override reason
    //
    pub override_reason:
        Option<String>,

    //
    // Explainability summary
    //
    pub explainability:
        Option<String>,

    //
    // Candidate source entities
    //
    pub candidate_entities:
        Vec<Uuid>,

    //
    // Policy references
    //
    pub policy_refs:
        Vec<Uuid>,

    //
    // Metadata
    //
    pub metadata:
        MetadataMap,
}

//
// ========================================
// GOLDEN RECORD QUALITY
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GoldenRecordQuality {

    //
    // Trust score
    //
    pub trust_score:
        Option<f32>,

    //
    // Completeness score
    //
    pub completeness_score:
        Option<f32>,

    //
    // Consistency score
    //
    pub consistency_score:
        Option<f32>,

    //
    // Accuracy score
    //
    pub accuracy_score:
        Option<f32>,

    //
    // Overall quality
    //
    pub overall_quality_score:
        Option<f32>,
}

//
// ========================================
// GOLDEN RECORD
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GoldenRecord {

    //
    // Golden record ID
    //
    pub golden_record_id:
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
        EntityType,

    //
    // Lifecycle stage
    //
    pub lifecycle_stage:
        GoldenRecordLifecycleStage,

    //
    // Status
    //
    pub status:
        GoldenRecordStatus,

    //
    // Source entities
    //
    pub source_entities:
        Vec<Uuid>,

    //
    // Golden attributes
    //
    pub golden_attributes:
        Vec<GoldenAttribute>,

    //
    // Quality metrics
    //
    pub quality:
        Option<GoldenRecordQuality>,

    //
    // Attribute conflicts
    //
    pub conflicts:
        Vec<AttributeConflict>,

    //
    // Source contributions
    //
    pub source_contributions:
        Vec<SourceContribution>,

    //
    // Semantic identity
    //
    pub semantic_identity:
        Option<String>,

    //
    // Vector namespace
    //
    pub vector_namespace:
        Option<String>,

    //
    // Versioning
    //
    pub version_info:
        VersionInfo,

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

    //
    // Embeddings
    //
    pub embedding_refs:
        Vec<EmbeddingReference>,

    //
    // Lineage refs
    //
    pub lineage_refs:
        Vec<Uuid>,

    //
    // Merge refs
    //
    pub merge_refs:
        Vec<Uuid>,

    //
    // Workflow refs
    //
    pub workflow_refs:
        Vec<Uuid>,

    //
    // Policy refs
    //
    pub policy_refs:
        Vec<Uuid>,

    //
    // Survivorship execution refs
    //
    pub survivorship_refs:
        Vec<Uuid>,

    //
    // Approval refs
    //
    pub approval_refs:
        Vec<Uuid>,

    //
    // Validity
    //
    pub valid_from:
        Option<DateTime<Utc>>,

    pub valid_to:
        Option<DateTime<Utc>>,
}