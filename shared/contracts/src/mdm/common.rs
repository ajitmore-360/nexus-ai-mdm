use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use uuid::Uuid;

pub type MetadataMap = HashMap<String, serde_json::Value>;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditMetadata {
    #[serde(default = "chrono::Utc::now")]
    pub created_at: DateTime<Utc>,
    #[serde(default = "chrono::Utc::now")]
    pub updated_at: DateTime<Utc>,

    pub created_by: Option<Uuid>,
    pub updated_by: Option<Uuid>,

    pub correlation_id: Option<Uuid>,
    pub causation_id: Option<Uuid>,
    pub request_id: Option<String>,
}

impl Default for AuditMetadata {
    fn default() -> Self {
        let now = chrono::Utc::now();
        Self {
            created_at: now,
            updated_at: now,
            created_by: None,
            updated_by: None,
            correlation_id: None,
            causation_id: None,
            request_id: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VersionInfo {
    #[serde(default = "VersionInfo::default_schema_version")]
    pub schema_version: String,
    #[serde(default = "VersionInfo::default_contract_version")]
    pub contract_version: String,
    #[serde(default)]
    pub entity_version: i64,
}

impl VersionInfo {
    fn default_schema_version() -> String { "1.0".to_string() }
    fn default_contract_version() -> String { "1.0".to_string() }
}

impl Default for VersionInfo {
    fn default() -> Self {
        Self {
            schema_version: "1.0".to_string(),
            contract_version: "1.0".to_string(),
            entity_version: 1,
        }
    }
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