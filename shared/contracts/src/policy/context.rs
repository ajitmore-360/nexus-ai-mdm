use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PolicyContext {

    pub tenant_id: String,

    pub user_id: String,

    pub role: String,

    pub plan: String,

    pub is_active: bool,
}