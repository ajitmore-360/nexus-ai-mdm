use serde::{Deserialize, Serialize};
use serde_json::Value;
use tracing::{instrument, warn};
use uuid::Uuid;

/// Decision returned by the ai-service semantic matcher.
#[derive(Debug, Clone, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum SemanticDecision {
    Match,
    NoMatch,
}

/// Parsed result from ai-service POST /semantic-match.
#[derive(Debug, Clone, Deserialize)]
pub struct SemanticMatchResult {
    pub decision:   SemanticDecision,
    pub confidence: f32,
    pub reasoning:  String,
    pub algo_score: f32,
}

#[derive(Serialize)]
struct SemanticMatchRequest<'a> {
    tenant_id:       Uuid,
    source_attrs:    &'a Value,
    candidate_attrs: &'a Value,
    algo_score:      f32,
    entity_type:     &'a str,
}

/// Thin HTTP client wrapping the ai-service `/semantic-match` endpoint.
/// Only invoked for grey-zone candidates (review band) when `semantic_matching`
/// is enabled on the MatchRequest — keeps LLM calls rare and cost-controlled.
#[derive(Clone)]
pub struct SemanticClient {
    http:        reqwest::Client,
    resolve_url: String,
}

impl SemanticClient {
    pub fn new(http: reqwest::Client, ai_service_url: &str) -> Self {
        Self {
            http,
            resolve_url: format!(
                "{}/semantic-match",
                ai_service_url.trim_end_matches('/')
            ),
        }
    }

    /// Call the ai-service to resolve a grey-zone pair.
    /// Returns `None` on any network/parse error so the caller can fall back
    /// to human review rather than hard-failing the match run.
    #[instrument(skip(self, source_attrs, candidate_attrs), fields(score=algo_score))]
    pub async fn resolve(
        &self,
        tenant_id:       Uuid,
        source_attrs:    &Value,
        candidate_attrs: &Value,
        algo_score:      f32,
        entity_type:     &str,
    ) -> Option<SemanticMatchResult> {
        let body = SemanticMatchRequest {
            tenant_id,
            source_attrs,
            candidate_attrs,
            algo_score,
            entity_type,
        };

        let resp = self
            .http
            .post(&self.resolve_url)
            .json(&body)
            .timeout(std::time::Duration::from_secs(30))
            .send()
            .await;

        match resp {
            Err(e) => {
                warn!(error=%e, "semantic-match request failed; routing to human review");
                None
            }
            Ok(r) if !r.status().is_success() => {
                warn!(status=%r.status(), "semantic-match returned non-2xx; routing to human review");
                None
            }
            Ok(r) => {
                #[derive(Deserialize)]
                struct Wrapper {
                    result: SemanticMatchResult,
                }
                match r.json::<Wrapper>().await {
                    Ok(w) => Some(w.result),
                    Err(e) => {
                        warn!(error=%e, "semantic-match response parse error; routing to human review");
                        None
                    }
                }
            }
        }
    }
}
