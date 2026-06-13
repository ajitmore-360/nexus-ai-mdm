use std::sync::Arc;

use anyhow::Result;
use tracing::instrument;

use contracts::mdm::matching::{MatchRequest, MatchResponse};

use crate::matching::matcher::Matcher;

pub struct MatchingService {
    matcher: Arc<Matcher>,
}

impl MatchingService {
    pub fn new(matcher: Arc<Matcher>) -> Self {
        Self { matcher }
    }

    #[instrument(skip(self, request))]
    pub async fn execute_matching(
        &self,
        request: MatchRequest,
    ) -> Result<MatchResponse> {
        self.matcher.execute(request).await
    }
}
