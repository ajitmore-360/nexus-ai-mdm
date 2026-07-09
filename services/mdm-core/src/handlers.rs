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
pub mod ai_suggestions;
pub mod bulk;
pub mod comments;
pub mod data_profiling;
pub mod hierarchy;
pub mod quality_analytics;
pub mod quality_rules;
pub mod reference_data;
pub mod submasters;
pub mod party_roles;
pub mod tasks;
pub mod temporal;
pub mod transformations;
pub mod unmerge;
pub mod users;
pub mod xref;
pub mod sso;
pub mod scim;
pub mod workflows;
pub mod connectors;
pub mod enrichment;

/// Standard API response wrapper used by all handlers.
#[derive(Debug, Serialize)]
pub struct ApiResponse<T: Serialize> {
    pub success: bool,
    pub data:    Option<T>,
    pub error:   Option<String>,
}
