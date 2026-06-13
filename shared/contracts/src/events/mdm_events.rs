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
    distribution::*,
    entity::*,
    golden_record::*,
    matching::*,
    merge::*,
};

//
// ========================================
// EVENT SOURCE
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum EventSource {

    API,

    AIService,

    MDMCore,

    PolicyEngine,

    Kafka,

    MCP,

    WorkflowEngine,

    SearchIndexer,

    VectorEngine,

    GraphEngine,

    CDCConnector,

    StewardshipUI,

    System,
}

//
// ========================================
// EVENT PRIORITY
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum EventPriority {

    Low,

    Normal,

    High,

    Critical,
}

//
// ========================================
// EVENT CATEGORY
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum EventCategory {

    Entity,

    Matching,

    Merge,

    Survivorship,

    GoldenRecord,

    Workflow,

    AI,

    Policy,

    Search,

    Vector,

    Graph,

    Audit,

    Cache,

    Streaming,

    CDC,

    System,
}

//
// ========================================
// EVENT STATUS
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum EventStatus {

    Pending,

    Published,

    Consumed,

    Retried,

    Failed,

    DeadLettered,

    Archived,
}

//
// ========================================
// EVENT METADATA
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventMetadata {

    //
    // Event identity
    //
    pub event_id: Uuid,

    //
    // Event type
    //
    pub event_type: String,

    //
    // Category
    //
    pub category:
        EventCategory,

    //
    // Status
    //
    pub status:
        EventStatus,

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
    // Causation
    //
    pub causation_id:
        Option<Uuid>,

    //
    // Parent event
    //
    pub parent_event_id:
        Option<Uuid>,

    //
    // Workflow
    //
    pub workflow_id:
        Option<Uuid>,

    //
    // Replay protection
    //
    pub idempotency_key:
        Option<String>,

    //
    // Replay support
    //
    pub replayable:
        bool,

    //
    // Replay sequence
    //
    pub replay_sequence:
        Option<u64>,

    //
    // Retry count
    //
    pub retry_count:
        u32,

    //
    // Dead-letter flag
    //
    pub dead_lettered:
        bool,

    //
    // Event source
    //
    pub source:
        EventSource,

    //
    // Priority
    //
    pub priority:
        EventPriority,

    //
    // Kafka topic
    //
    pub kafka_topic:
        Option<String>,

    //
    // Kafka partition key
    //
    pub partition_key:
        Option<String>,

    //
    // Event version
    //
    pub schema_version:
        String,

    //
    // Contract version
    //
    pub contract_version:
        String,

    //
    // Trace metadata
    //
    pub trace_id:
        Option<String>,

    pub span_id:
        Option<String>,

    //
    // Streaming
    //
    pub stream_id:
        Option<String>,

    //
    // Emitted timestamp
    //
    pub emitted_at:
        DateTime<Utc>,

    //
    // Published timestamp
    //
    pub published_at:
        Option<DateTime<Utc>>,

    //
    // Consumed timestamp
    //
    pub consumed_at:
        Option<DateTime<Utc>>,

    //
    // Emitted by
    //
    pub emitted_by:
        Option<Uuid>,

    //
    // Metadata
    //
    pub metadata:
        MetadataMap,
}

//
// ========================================
// ENTITY MERGED PAYLOAD
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EntityMergedPayload {

    pub surviving_entity:
        CanonicalEntity,

    pub merged_entities:
        Vec<Uuid>,

    pub generated_golden_record:
        Option<GoldenRecord>,

    pub merge_request_id:
        Option<Uuid>,

    pub lineage_event_ids:
        Vec<Uuid>,

    pub replay_reference:
        Option<String>,
}

//
// ========================================
// SURVIVORSHIP EXECUTED PAYLOAD
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SurvivorshipExecutedPayload {

    pub golden_record:
        GoldenRecord,

    pub applied_rule_ids:
        Vec<Uuid>,

    pub confidence:
        Option<f32>,

    pub explanation:
        Vec<String>,

    pub ai_assisted:
        bool,
}

//
// ========================================
// AI RECOMMENDATION PAYLOAD
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AIRecommendationPayload {

    pub recommendation_type:
        String,

    pub recommendation:
        serde_json::Value,

    pub confidence:
        f32,

    pub model_name:
        String,

    pub model_version:
        String,

    pub embeddings_used:
        bool,

    pub rag_enabled:
        bool,

    pub explanation:
        Vec<String>,
}

//
// ========================================
// POLICY VIOLATION PAYLOAD
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PolicyViolationPayload {

    pub policy_name:
        String,

    pub violation_reason:
        String,

    pub severity:
        String,

    pub affected_entity_ids:
        Vec<Uuid>,

    pub remediation:
        Option<String>,
}

//
// ========================================
// WORKFLOW EVENT PAYLOAD
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkflowEventPayload {

    pub workflow_id:
        Uuid,

    pub workflow_name:
        String,

    pub workflow_step:
        String,

    pub status:
        String,

    pub message:
        Option<String>,
}

//
// ========================================
// VECTOR EVENT PAYLOAD
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VectorEventPayload {

    pub entity_id:
        Uuid,

    pub embedding_model:
        String,

    pub vector_dimension:
        usize,

    pub regenerated:
        bool,
}

//
// ========================================
// SEARCH INDEX EVENT PAYLOAD
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchIndexEventPayload {

    pub entity_id:
        Uuid,

    pub index_name:
        String,

    pub operation:
        String,

    pub successful:
        bool,
}

//
// ========================================
// CACHE INVALIDATION PAYLOAD
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheInvalidationPayload {

    pub cache_keys:
        Vec<String>,

    pub reason:
        String,
}

//
// ========================================
// STREAMING EVENT PAYLOAD
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StreamingEventPayload {

    pub stream_id:
        String,

    pub channel:
        String,

    pub message:
        serde_json::Value,
}

//
// ========================================
// MDM EVENT PAYLOAD
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MDMEventPayload {

    //
    // ENTITY EVENTS
    //

    EntityCreated(
        CanonicalEntity
    ),

    EntityUpdated(
        CanonicalEntity
    ),

    EntityDeleted {
        entity_id: Uuid,
    },

    //
    // HUB: MDM-authored entity published to downstream systems
    //

    EntityDistributionRequested(
        DistributionRequest,
    ),

    EntityDistributed(
        DistributionJobResult,
    ),

    //
    // MATCHING EVENTS
    //

    MatchDetected(
        MatchCandidate
    ),

    MatchRejected {
        entity_id: Uuid,

        reason: String,
    },

    //
    // MERGE EVENTS
    //

    MergeRequested(
        MergeRequest
    ),

    MergeApproved {
        merge_request_id:
            Uuid,
    },

    MergeRejected {
        merge_request_id:
            Uuid,

        reason: String,
    },

    MergeExecutionStarted {
        merge_request_id:
            Uuid,
    },

    MergeExecutionCompleted(
        MergeExecutionResult
    ),

    EntityMerged(
        EntityMergedPayload
    ),

    //
    // GOLDEN RECORD EVENTS
    //

    GoldenRecordCreated(
        GoldenRecord
    ),

    GoldenRecordUpdated(
        GoldenRecord
    ),

    GoldenRecordDeleted {
        golden_record_id:
            Uuid,
    },

    //
    // SURVIVORSHIP EVENTS
    //

    SurvivorshipExecuted(
        SurvivorshipExecutedPayload
    ),

    //
    // AI EVENTS
    //

    AIRecommendationGenerated(
        AIRecommendationPayload
    ),

    //
    // POLICY EVENTS
    //

    PolicyViolationDetected(
        PolicyViolationPayload
    ),

    //
    // VECTOR EVENTS
    //

    EmbeddingGenerated(
        VectorEventPayload
    ),

    //
    // SEARCH EVENTS
    //

    SearchIndexUpdated(
        SearchIndexEventPayload
    ),

    //
    // CACHE EVENTS
    //

    CacheInvalidated(
        CacheInvalidationPayload
    ),

    //
    // STREAMING EVENTS
    //

    StreamMessage(
        StreamingEventPayload
    ),

    //
    // WORKFLOW EVENTS
    //

    WorkflowTriggered(
        WorkflowEventPayload
    ),

    WorkflowCompleted(
        WorkflowEventPayload
    ),

    WorkflowFailed(
        WorkflowEventPayload
    ),
}

//
// ========================================
// ROOT EVENT
// ========================================
//

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MDMEvent {

    //
    // Metadata
    //
    pub metadata:
        EventMetadata,

    //
    // Payload
    //
    pub payload:
        MDMEventPayload,
}