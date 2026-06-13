use std::sync::Arc;

use crate::{
    config::settings::PolicySettings,
    engine::{GdprEngine, PolicyEvaluator},
    rules::PolicyRepository,
};

#[derive(Clone)]
pub struct AppState {
    #[allow(dead_code)]
    pub settings:  Arc<PolicySettings>,
    pub evaluator: Arc<PolicyEvaluator>,
    pub gdpr:      Arc<GdprEngine>,
    pub rule_repo: Arc<PolicyRepository>,
}
