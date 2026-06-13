use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::mdm::common::MetadataMap;
use crate::mdm::entity::CanonicalEntity;

//
// ========================================
// RECORD ORIGIN (hub vs spoke)
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "snake_case")]
pub enum EntityRecordOrigin {
    /// Created or mastered inside Nexus MDM (authoritative hub).
    #[default]
    MdmAuthoritative,
    /// Ingested from an external system of record.
    Ingested,
    /// Produced by merge/survivorship.
    SurvivorshipDerived,
}

//
// ========================================
// DISTRIBUTION TARGET
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DistributionTarget {
    pub connector_id: String,
    pub target_system: String,
    pub delivery_mode: DistributionDeliveryMode,
    pub metadata: MetadataMap,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DistributionDeliveryMode {
    Push,
    Pull,
    Cdc,
    Webhook,
}

//
// ========================================
// DISTRIBUTION REQUEST
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DistributionRequest {
    pub distribution_id: Uuid,
    pub tenant_id: Uuid,
    pub entity_id: Uuid,
    pub correlation_id: Option<Uuid>,
    pub targets: Vec<DistributionTarget>,
    pub publish_golden_record: bool,
    pub metadata: MetadataMap,
}

//
// ========================================
// DISTRIBUTION JOB STATUS
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DistributionJobStatus {
    Pending,
    InProgress,
    Completed,
    Failed,
    PartiallyCompleted,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DistributionJobResult {
    pub distribution_id: Uuid,
    pub tenant_id: Uuid,
    pub entity_id: Uuid,
    pub status: DistributionJobStatus,
    pub targets_attempted: usize,
    pub targets_succeeded: usize,
    pub errors: Vec<String>,
    pub completed_at: Option<DateTime<Utc>>,
}

//
// ========================================
// CREATE IN MDM + DISTRIBUTE (API payload)
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateEntityRequest {
    pub entity: CanonicalEntity,
    #[serde(default)]
    pub record_origin: EntityRecordOrigin,
    /// When true, enqueue distribution to configured targets after persist.
    #[serde(default)]
    pub distribute: bool,
    #[serde(default)]
    pub distribution_targets: Vec<DistributionTarget>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateEntityResponse {
    pub entity_id: Uuid,
    pub distribution_id: Option<Uuid>,
    pub outbox_event_ids: Vec<Uuid>,
}
