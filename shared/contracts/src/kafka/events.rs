use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KafkaEvent {

    pub event_type: String,

    pub tenant_id: String,

    pub payload: serde_json::Value,

    pub correlation_id: String,
}