use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use uuid::Uuid;

// ============================================================
// FIELD TRANSFORM
// ============================================================

/// Transformation applied to a single field value during normalization.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum FieldTransform {
    Lowercase,
    Uppercase,
    TitleCase,
    StripWhitespace,
    PhoneE164,
    EmailNormalize,
    DateIso8601,
}

// ============================================================
// SCHEMA MAPPING
// ============================================================

/// Maps a single source field name to a canonical field name and
/// optionally applies a transformation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SchemaMapping {
    /// Field name as it appears in the source data.
    pub source_field: String,

    /// Field name used in the canonical entity model.
    pub canonical_field: String,

    /// Optional transformation to apply to the field value.
    pub transform: Option<FieldTransform>,
}

// ============================================================
// INGEST RECORD
// ============================================================

/// A single entity record as received from a source system.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IngestRecord {
    /// The source system name (e.g. "salesforce", "sap", "csv_upload").
    pub source_system: String,

    /// The entity identifier in the source system.
    pub source_entity_id: String,

    /// Logical entity type (e.g. "Customer", "Vendor").
    pub entity_type: String,

    /// Raw key-value fields from the source.
    pub raw_fields: HashMap<String, serde_json::Value>,

    /// Timestamp when this record was received by the ingest service.
    pub received_at: DateTime<Utc>,
}

impl IngestRecord {
    /// Construct a new record with `received_at` set to now.
    pub fn new(
        source_system: impl Into<String>,
        source_entity_id: impl Into<String>,
        entity_type: impl Into<String>,
        raw_fields: HashMap<String, serde_json::Value>,
    ) -> Self {
        Self {
            source_system: source_system.into(),
            source_entity_id: source_entity_id.into(),
            entity_type: entity_type.into(),
            raw_fields,
            received_at: Utc::now(),
        }
    }
}

// ============================================================
// INGEST BATCH
// ============================================================

/// A collection of ingest records submitted as a single unit.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IngestBatch {
    /// Unique identifier for this batch.
    pub batch_id: Uuid,

    /// Tenant that owns these records.
    pub tenant_id: Uuid,

    /// Source system name for the entire batch.
    pub source_system: String,

    /// Records in this batch.
    pub records: Vec<IngestRecord>,

    /// Optional originating file name (for file-based ingestion).
    pub file_name: Option<String>,
}

impl IngestBatch {
    pub fn new(
        tenant_id: Uuid,
        source_system: impl Into<String>,
        records: Vec<IngestRecord>,
    ) -> Self {
        Self {
            batch_id: Uuid::new_v4(),
            tenant_id,
            source_system: source_system.into(),
            records,
            file_name: None,
        }
    }

    #[allow(dead_code)]
    pub fn with_file_name(mut self, file_name: impl Into<String>) -> Self {
        self.file_name = Some(file_name.into());
        self
    }
}

// ============================================================
// INGEST STATUS
// ============================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum IngestStatus {
    Pending,
    Processing,
    Completed,
    Failed,
    PartialSuccess,
}

// ============================================================
// INGEST RESULT
// ============================================================

/// Aggregated outcome of processing an `IngestBatch`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IngestResult {
    /// Batch that was processed.
    pub batch_id: Uuid,

    /// Number of records successfully processed.
    pub processed: usize,

    /// Number of records that failed.
    pub failed: usize,

    /// Number of records that were intentionally skipped (e.g. duplicates).
    pub skipped: usize,

    /// Canonical entity IDs created or updated.
    pub entity_ids: Vec<Uuid>,

    /// Per-record error messages.
    pub errors: Vec<String>,

    /// Total wall-clock time for the batch in milliseconds.
    pub duration_ms: u64,

    /// Overall status of this batch.
    pub status: IngestStatus,
}

impl IngestResult {
    pub fn new(batch_id: Uuid) -> Self {
        Self {
            batch_id,
            processed: 0,
            failed: 0,
            skipped: 0,
            entity_ids: Vec::new(),
            errors: Vec::new(),
            duration_ms: 0,
            status: IngestStatus::Pending,
        }
    }

    /// Derive the overall status from the counters.
    pub fn finalize(&mut self, duration_ms: u64) {
        self.duration_ms = duration_ms;
        self.status = if self.failed == 0 && self.processed > 0 {
            IngestStatus::Completed
        } else if self.processed == 0 && self.failed > 0 {
            IngestStatus::Failed
        } else if self.processed > 0 && self.failed > 0 {
            IngestStatus::PartialSuccess
        } else {
            IngestStatus::Completed
        };
    }
}

// ============================================================
// TESTS
// ============================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ingest_result_finalize_all_success() {
        let mut result = IngestResult::new(Uuid::new_v4());
        result.processed = 10;
        result.finalize(500);
        assert_eq!(result.status, IngestStatus::Completed);
    }

    #[test]
    fn ingest_result_finalize_all_failed() {
        let mut result = IngestResult::new(Uuid::new_v4());
        result.failed = 5;
        result.finalize(100);
        assert_eq!(result.status, IngestStatus::Failed);
    }

    #[test]
    fn ingest_result_finalize_partial() {
        let mut result = IngestResult::new(Uuid::new_v4());
        result.processed = 8;
        result.failed = 2;
        result.finalize(200);
        assert_eq!(result.status, IngestStatus::PartialSuccess);
    }

    #[test]
    fn ingest_batch_builder() {
        let tenant_id = Uuid::new_v4();
        let batch = IngestBatch::new(tenant_id, "test-system", vec![])
            .with_file_name("data.csv");
        assert_eq!(batch.tenant_id, tenant_id);
        assert_eq!(batch.file_name.as_deref(), Some("data.csv"));
    }
}
