use chrono::{
    DateTime,
    Utc,
};

use serde::{
    Deserialize,
    Serialize,
};

use std::collections::HashMap;
use std::fmt;

use uuid::Uuid;

use crate::mdm::common::*;

fn _new_uuid() -> Uuid { Uuid::new_v4() }
fn _bool_true() -> bool { true }
fn _default_attr_version() -> u64 { 1 }

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

impl fmt::Display for EntityType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            EntityType::Customer      => write!(f, "Customer"),
            EntityType::Vendor        => write!(f, "Vendor"),
            EntityType::Material      => write!(f, "Material"),
            EntityType::Product       => write!(f, "Product"),
            EntityType::Account       => write!(f, "Account"),
            EntityType::Employee      => write!(f, "Employee"),
            EntityType::Location      => write!(f, "Location"),
            EntityType::Organization  => write!(f, "Organization"),
            EntityType::Asset         => write!(f, "Asset"),
            EntityType::ReferenceData => write!(f, "ReferenceData"),
            EntityType::Custom(s)     => write!(f, "{}", s),
        }
    }
}

//
// ========================================
// ENTITY STATUS
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
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

impl fmt::Display for EntityStatus {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            EntityStatus::Draft              => write!(f, "Draft"),
            EntityStatus::Active             => write!(f, "Active"),
            EntityStatus::Inactive           => write!(f, "Inactive"),
            EntityStatus::PendingReview      => write!(f, "PendingReview"),
            EntityStatus::UnderInvestigation => write!(f, "UnderInvestigation"),
            EntityStatus::Merged             => write!(f, "Merged"),
            EntityStatus::Deleted            => write!(f, "Deleted"),
            EntityStatus::Archived           => write!(f, "Archived"),
            EntityStatus::SoftDeleted        => write!(f, "SoftDeleted"),
        }
    }
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

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct EntityAttribute {

    //
    // Attribute ID
    //
    #[serde(default = "_new_uuid")]
    pub attribute_id:
        Uuid,

    //
    // Key
    //
    #[serde(default)]
    pub key:
        String,

    //
    // Value
    //
    #[serde(default)]
    pub value:
        serde_json::Value,

    //
    // Data type
    //
    #[serde(default)]
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
    #[serde(default)]
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
    #[serde(default)]
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
    #[serde(default)]
    pub ai_annotations:
        Vec<AIAnnotation>,

    //
    // Searchable
    //
    #[serde(default = "_bool_true")]
    pub searchable:
        bool,

    //
    // Indexed
    //
    #[serde(default = "_bool_true")]
    pub indexed:
        bool,

    //
    // Encrypted
    //
    #[serde(default)]
    pub encrypted:
        bool,

    //
    // Survivorship eligible
    //
    #[serde(default = "_bool_true")]
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
    #[serde(default = "_default_attr_version")]
    pub attribute_version:
        u64,

    //
    // Metadata
    //
    #[serde(default)]
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
    #[serde(default)]
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
    #[serde(default)]
    pub attributes:
        Vec<EntityAttribute>,

    //
    // Relationships
    //
    #[serde(default)]
    pub relationships:
        Vec<EntityRelationship>,

    //
    // Source snapshots
    //
    #[serde(default)]
    pub source_snapshots:
        Vec<EntitySourceSnapshot>,

    //
    // Versioning
    //
    #[serde(default)]
    pub version_info:
        VersionInfo,

    //
    // Audit
    //
    #[serde(default)]
    pub audit:
        AuditMetadata,

    //
    // Entity tags
    //
    #[serde(default)]
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
    #[serde(default)]
    pub metadata:
        MetadataMap,

    //
    // Embeddings
    //
    #[serde(default)]
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
    #[serde(default)]
    pub lineage_refs:
        Vec<Uuid>,

    //
    // Merge references
    //
    #[serde(default)]
    pub merge_refs:
        Vec<Uuid>,

    //
    // Survivorship references
    //
    #[serde(default)]
    pub survivorship_refs:
        Vec<Uuid>,

    //
    // Workflow references
    //
    #[serde(default)]
    pub workflow_refs:
        Vec<Uuid>,

    //
    // Policy evaluation references
    //
    #[serde(default)]
    pub policy_refs:
        Vec<Uuid>,

    //
    // Change history
    //
    #[serde(default)]
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