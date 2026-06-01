use serde::{
    Deserialize,
    Serialize,
};

use uuid::Uuid;

//
// ========================================
// CLIENT → GATEWAY
// ========================================
//

#[derive(Debug, Serialize, Deserialize)]
pub struct WsClientMessage {

    pub tenant_id: Uuid,

    pub user_id: Uuid,

    pub prompt: String,

    pub correlation_id: Option<Uuid>,
}

//
// ========================================
// GATEWAY → CLIENT
// ========================================
//

#[derive(Debug, Serialize, Deserialize)]
pub struct WsServerMessage {

    pub event: String,

    pub correlation_id: Option<Uuid>,

    pub data: serde_json::Value,
}