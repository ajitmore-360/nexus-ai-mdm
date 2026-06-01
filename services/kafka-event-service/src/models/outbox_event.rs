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

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OutboxEvent {

    pub event_id:
        Uuid,

    pub tenant_id:
        Uuid,

    pub aggregate_type:
        String,

    pub aggregate_id:
        Uuid,

    pub event_type:
        String,

    pub event_payload:
        Value,

    pub topic_name:
        String,

    pub published:
        bool,

    pub retry_count:
        i32,

    pub created_at:
        DateTime<Utc>,
}