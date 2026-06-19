use serde::Serialize;

pub mod dashboard;
pub mod entities;
pub mod lineage;
pub mod matching;
pub mod merge;
pub mod policy;
pub mod review;
pub mod users;

/// Standard API response wrapper used by all handlers.
#[derive(Debug, Serialize)]
pub struct ApiResponse<T: Serialize> {
    pub success: bool,
    pub data:    Option<T>,
    pub error:   Option<String>,
}
