use chrono::{
    DateTime,
    Utc,
};

use serde::{
    Deserialize,
    Serialize,
};

use std::collections::HashMap;

use uuid::Uuid;

use crate::mdm::common::*;

//
// ========================================
// ENTITY TYPE
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum EntityType {

    Customer,

    Vendor,

    Material,

    Product,

    Account,

    Employee,

    Location,

    Organization,

    Asset,

    ReferenceData,

    Custom(String),
}

//
// ========================================
// ENTITY STATUS
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum EntityStatus {

    Draft,

    Active,

    Inactive,

    PendingReview,

    UnderInvestigation,

    Merged,

    Deleted,

    Archived,

    SoftDeleted,
}

//
// ========================================
// ENTITY SOURCE SNAPSHOT
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EntitySourceSnapshot {

    //
    // Source system
    //
    pub source_system:
        String,

    //
    // Source entity ID
    //
    pub source_entity_id:
        String,

    //
    // Raw payload reference
    //
    pub payload_reference:
        Option<String>,

    //
    // Extracted at
    //
    pub extracted_at:
        Option<DateTime<Utc>>,

    //
    // Metadata
    //
    pub metadata:
        MetadataMap,
}

//
// ========================================
// ATTRIBUTE CHANGE
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AttributeChange {

    //
    // Attribute
    //
    pub attribute:
        String,

    //
    // Old value
    //
    pub old_value:
        Option<serde_json::Value>,

    //
    // New value
    //
    pub new_value:
        Option<serde_json::Value>,

    //
    // Changed by
    //
    pub changed_by:
        Option<Uuid>,

    //
    // Changed at
    //
    pub changed_at:
        DateTime<Utc>,

    //
    // Reason
    //
    pub reason:
        Option<String>,
}

//
// ========================================
// ENTITY ATTRIBUTE
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EntityAttribute {

    //
    // Attribute ID
    //
    pub attribute_id:
        Uuid,

    //
    // Key
    //
    pub key:
        String,

    //
    // Value
    //
    pub value:
        serde_json::Value,

    //
    // Data type
    //
    pub data_type:
        String,

    //
    // Confidence
    //
    pub confidence:
        Option<ConfidenceScore>,

    //
    // Provenance
    //
    pub provenance:
        Option<DataProvenance>,

    //
    // Policy tags
    //
    pub policy_tags:
        Vec<PolicyTag>,

    //
    // Semantic type
    //
    pub semantic_type:
        Option<String>,

    //
    // Search aliases
    //
    pub aliases:
        Vec<String>,

    //
    // Embedding reference
    //
    pub embedding_ref:
        Option<EmbeddingReference>,

    //
    // AI annotations
    //
    pub ai_annotations:
        Vec<AIAnnotation>,

    //
    // Searchable
    //
    pub searchable:
        bool,

    //
    // Indexed
    //
    pub indexed:
        bool,

    //
    // Encrypted
    //
    pub encrypted:
        bool,

    //
    // Survivorship eligible
    //
    pub survivorship_eligible:
        bool,

    //
    // Last updated
    //
    pub updated_at:
        Option<DateTime<Utc>>,

    //
    // Attribute version
    //
    pub attribute_version:
        u64,

    //
    // Metadata
    //
    pub metadata:
        MetadataMap,
}

//
// ========================================
// ENTITY RELATIONSHIP
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EntityRelationship {

    //
    // Relationship ID
    //
    pub relationship_id:
        Uuid,

    //
    // Relationship type
    //
    pub relationship_type:
        String,

    //
    // Target entity
    //
    pub target_entity_id:
        Uuid,

    //
    // Target entity type
    //
    pub target_entity_type:
        EntityType,

    //
    // Confidence
    //
    pub confidence:
        Option<ConfidenceScore>,

    //
    // Bidirectional
    //
    pub bidirectional:
        bool,

    //
    // Relationship strength
    //
    pub strength:
        Option<f32>,

    //
    // Temporal validity
    //
    pub valid_from:
        Option<DateTime<Utc>>,

    pub valid_to:
        Option<DateTime<Utc>>,

    //
    // Metadata
    //
    pub metadata:
        MetadataMap,
}

//
// ========================================
// DATA QUALITY METRICS
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DataQualityMetrics {

    //
    // Completeness
    //
    pub completeness:
        Option<f32>,

    //
    // Accuracy
    //
    pub accuracy:
        Option<f32>,

    //
    // Consistency
    //
    pub consistency:
        Option<f32>,

    //
    // Uniqueness
    //
    pub uniqueness:
        Option<f32>,

    //
    // Timeliness
    //
    pub timeliness:
        Option<f32>,

    //
    // Validity
    //
    pub validity:
        Option<f32>,
}

//
// ========================================
// CANONICAL ENTITY
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CanonicalEntity {

    //
    // Entity identity
    //
    pub entity_id:
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
    // External IDs
    //
    pub external_ids:
        HashMap<String, String>,

    //
    // Status
    //
    pub status:
        EntityStatus,

    //
    // Attributes
    //
    pub attributes:
        Vec<EntityAttribute>,

    //
    // Relationships
    //
    pub relationships:
        Vec<EntityRelationship>,

    //
    // Source snapshots
    //
    pub source_snapshots:
        Vec<EntitySourceSnapshot>,

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
    // Entity tags
    //
    pub tags:
        Vec<String>,

    //
    // Data quality
    //
    pub data_quality:
        Option<DataQualityMetrics>,

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
    // Trust score
    //
    pub trust_score:
        Option<f32>,

    //
    // Golden/master record
    //
    pub master_record:
        Option<Uuid>,

    //
    // Lineage references
    //
    pub lineage_refs:
        Vec<Uuid>,

    //
    // Merge references
    //
    pub merge_refs:
        Vec<Uuid>,

    //
    // Survivorship references
    //
    pub survivorship_refs:
        Vec<Uuid>,

    //
    // Workflow references
    //
    pub workflow_refs:
        Vec<Uuid>,

    //
    // Policy evaluation references
    //
    pub policy_refs:
        Vec<Uuid>,

    //
    // Change history
    //
    pub changes:
        Vec<AttributeChange>,

    //
    // Semantic identity
    //
    pub semantic_identity:
        Option<String>,

    //
    // Vector search namespace
    //
    pub vector_namespace:
        Option<String>,

    //
    // Temporal validity
    //
    pub valid_from:
        Option<DateTime<Utc>>,

    pub valid_to:
        Option<DateTime<Utc>>,
}