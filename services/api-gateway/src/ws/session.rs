use uuid::Uuid;

#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct ClientSession {
    pub session_id: Uuid,
    pub tenant_id: Uuid,
    pub user_id: Uuid,

    pub role: String,
    pub plan: String,

    pub connected_at: i64,

    pub is_active: bool,
}