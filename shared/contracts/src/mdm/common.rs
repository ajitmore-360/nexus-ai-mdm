use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use uuid::Uuid;

pub type MetadataMap = HashMap<String, serde_json::Value>;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditMetadata {
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,

    pub created_by: Option<Uuid>,
    pub updated_by: Option<Uuid>,

    pub correlation_id: Option<Uuid>,
    pub causation_id: Option<Uuid>,
    pub request_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VersionInfo {
    pub schema_version: String,
    pub contract_version: String,
    pub entity_version: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SourceReference {
    pub source_system: String,
    pub source_record_id: String,

    pub ingestion_batch_id: Option<String>,
    pub ingestion_job_id: Option<String>,

    pub extracted_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConfidenceScore {
    pub score: f32,

    pub explanation: Option<String>,

    pub model_version: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EmbeddingReference {
    pub embedding_id: Uuid,

    pub vector_model: String,

    pub dimensions: usize,

    pub generated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PolicyTag {
    pub tag: String,

    pub classification: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AIAnnotation {
    pub annotation_type: String,

    pub value: serde_json::Value,

    pub confidence: Option<f32>,

    pub model: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DataProvenance {
    pub source: SourceReference,

    pub transformation_pipeline: Option<String>,

    pub transformation_version: Option<String>,

    pub transformation_steps: Vec<String>,
}