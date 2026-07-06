use serde::Serialize;

pub mod admin;
pub mod audit;
pub mod branding;
pub mod data_governance;
pub mod distribution;
pub mod notifications;
pub mod license;
pub mod dashboard;
pub mod domain_policies;
pub mod entities;
pub mod entity_types;
pub mod golden_records;
pub mod lineage;
pub mod matching;
pub mod merge;
pub mod policy;
pub mod relationships;
pub mod review;
pub mod users;

/// Standard API response wrapper used by all handlers.
#[derive(Debug, Serialize)]
pub struct ApiResponse<T: Serialize> {
    pub success: bool,
    pub data:    Option<T>,
    pub error:   Option<String>,
}
