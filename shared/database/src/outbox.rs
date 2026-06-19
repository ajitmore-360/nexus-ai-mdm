use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use uuid::Uuid;

///
/// Shared Outbox Event Model
///
/// Used by:
///
/// mdm-core
/// policy-service
/// ai-service
/// ingest-service
///
#[derive(
    Debug,
    Clone,
    Serialize,
    Deserialize,
)]
pub struct OutboxEvent {

    pub event_id: Uuid,

    pub tenant_id: Uuid,

    pub aggregate_type: String,

    pub aggregate_id: Uuid,

    pub event_type: String,

    pub event_version: i32,

    pub payload: Value,

    pub metadata: Value,

    pub headers: Value,

    pub correlation_id: Option<Uuid>,

    pub causation_id: Option<Uuid>,

    pub trace_id: Option<String>,

    pub partition_key: Option<String>,

    pub topic_name: String,

    pub created_at: DateTime<Utc>,
}

impl OutboxEvent {

    pub fn builder() -> OutboxEventBuilder {
        OutboxEventBuilder::default()
    }
}

#[derive(Default)]
pub struct OutboxEventBuilder {

    tenant_id: Option<Uuid>,

    aggregate_type: Option<String>,

    aggregate_id: Option<Uuid>,

    event_type: Option<String>,

    payload: Option<Value>,

    metadata: Option<Value>,

    headers: Option<Value>,

    correlation_id: Option<Uuid>,

    causation_id: Option<Uuid>,

    trace_id: Option<String>,

    partition_key: Option<String>,

    topic_name: Option<String>,
}

impl OutboxEventBuilder {

    pub fn tenant_id(
        mut self,
        value: Uuid,
    ) -> Self {
        self.tenant_id = Some(value);
        self
    }

    pub fn aggregate_type(
        mut self,
        value: impl Into<String>,
    ) -> Self {
        self.aggregate_type = Some(value.into());
        self
    }

    pub fn aggregate_id(
        mut self,
        value: Uuid,
    ) -> Self {
        self.aggregate_id = Some(value);
        self
    }

    pub fn event_type(
        mut self,
        value: impl Into<String>,
    ) -> Self {
        self.event_type = Some(value.into());
        self
    }

    pub fn payload(
        mut self,
        value: Value,
    ) -> Self {
        self.payload = Some(value);
        self
    }

    pub fn metadata(
        mut self,
        value: Value,
    ) -> Self {
        self.metadata = Some(value);
        self
    }

    pub fn headers(
        mut self,
        value: Value,
    ) -> Self {
        self.headers = Some(value);
        self
    }

    pub fn correlation_id(
        mut self,
        value: Uuid,
    ) -> Self {
        self.correlation_id = Some(value);
        self
    }

    pub fn causation_id(
        mut self,
        value: Uuid,
    ) -> Self {
        self.causation_id = Some(value);
        self
    }

    pub fn trace_id(
        mut self,
        value: impl Into<String>,
    ) -> Self {
        self.trace_id = Some(value.into());
        self
    }

    pub fn partition_key(
        mut self,
        value: impl Into<String>,
    ) -> Self {
        self.partition_key = Some(value.into());
        self
    }

    pub fn topic_name(
        mut self,
        value: impl Into<String>,
    ) -> Self {
        self.topic_name = Some(value.into());
        self
    }

    pub fn build(self) -> anyhow::Result<OutboxEvent> {
        Ok(OutboxEvent {
            event_id:       Uuid::new_v4(),
            tenant_id:      self.tenant_id.ok_or_else(|| anyhow::anyhow!("OutboxEvent: tenant_id is required"))?,
            aggregate_type: self.aggregate_type.ok_or_else(|| anyhow::anyhow!("OutboxEvent: aggregate_type is required"))?,
            aggregate_id:   self.aggregate_id.ok_or_else(|| anyhow::anyhow!("OutboxEvent: aggregate_id is required"))?,
            event_type:     self.event_type.ok_or_else(|| anyhow::anyhow!("OutboxEvent: event_type is required"))?,
            topic_name:     self.topic_name.ok_or_else(|| anyhow::anyhow!("OutboxEvent: topic_name is required"))?,
            payload:        self.payload.unwrap_or(json!({})),
            metadata:       self.metadata.unwrap_or(json!({})),
            headers:        self.headers.unwrap_or(json!({})),
            correlation_id: self.correlation_id,
            causation_id:   self.causation_id,
            trace_id:       self.trace_id,
            partition_key:  self.partition_key,
            event_version:  1,
            created_at:     Utc::now(),
        })
    }
}

#[derive(
    Debug,
    Clone,
    Serialize,
    Deserialize,
)]
pub enum OutboxStatus {

    Pending,

    Published,

    Failed,

    DeadLetter,
}