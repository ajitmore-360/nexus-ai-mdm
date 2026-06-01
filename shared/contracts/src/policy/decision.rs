use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PolicyDecision {

    pub allowed: bool,

    pub reason: Option<String>,
}