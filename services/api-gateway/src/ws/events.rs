use serde::{Deserialize, Serialize};
use serde_json::Value;
use uuid::Uuid;

#[allow(dead_code)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WsEvent {
    pub event_id: Uuid,
    pub correlation_id: Option<Uuid>,
    pub tenant_id: Option<Uuid>,
    pub user_id: Option<Uuid>,

    pub event_type: String,

    pub content: Option<String>,

    pub payload: Option<Value>,

    pub timestamp: i64,
}

impl WsEvent {
    #[allow(dead_code)]
    pub fn new(event_type: &str) -> Self {
        Self {
            event_id: Uuid::new_v4(),
            correlation_id: None,
            tenant_id: None,
            user_id: None,
            event_type: event_type.to_string(),
            content: None,
            payload: None,
            timestamp: chrono::Utc::now().timestamp(),
        }
    }
}