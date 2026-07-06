use std::sync::Arc;

use anyhow::Result;
use tracing::instrument;

use contracts::mdm::matching::{MatchRequest, MatchResponse};

use crate::matching::matcher::Matcher;
use crate::matching::policy::MatchingPolicy;

pub struct MatchingService {
    matcher: Arc<Matcher>,
}

impl MatchingService {
    pub fn new(matcher: Arc<Matcher>) -> Self {
        Self { matcher }
    }

    /// Run matching with the current global policy (no override).
    #[instrument(skip(self, request))]
    pub async fn execute_matching(
        &self,
        request: MatchRequest,
    ) -> Result<MatchResponse> {
        self.matcher.execute(request, None).await
    }

    /// Run matching with an explicit policy override (e.g. a domain policy
    /// resolved by `DomainPolicyService::resolve`).  Pass `None` to fall back
    /// to the global live policy, which is identical to calling
    /// `execute_matching`.
    #[instrument(skip(self, request, policy_override))]
    pub async fn execute_matching_with_policy(
        &self,
        request: MatchRequest,
        policy_override: Option<MatchingPolicy>,
    ) -> Result<MatchResponse> {
        self.matcher.execute(request, policy_override).await
    }
}
