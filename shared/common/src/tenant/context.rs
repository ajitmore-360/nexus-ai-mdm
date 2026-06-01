use uuid::Uuid;

#[derive(Debug, Clone)]
pub struct TenantContext {
    pub tenant_id: Uuid,
    pub correlation_id: Option<Uuid>,
    pub request_id: Option<String>,
}