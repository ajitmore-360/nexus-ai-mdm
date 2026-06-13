use anyhow::Result;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use tracing::{info, instrument, warn};

use crate::llm::{OllamaClient, Prompts};

/// Decision returned by the semantic matcher.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum MatchDecision {
    Match,
    NoMatch,
}

/// Result of semantic match resolution.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SemanticMatchResult {
    pub decision:   MatchDecision,
    pub confidence: f32,
    pub reasoning:  String,
    /// Original algorithm score (before LLM intervention).
    pub algo_score: f32,
}

/// Uses Llama to resolve ambiguous entity pairs (grey-zone 0.75–0.95 score).
///
/// The matcher is only called when the deterministic scoring engine puts a
/// pair in the review band but hasn't made a confident auto-merge decision.
/// This keeps LLM calls rare and cost-controlled.
pub struct SemanticMatcher {
    llm:     OllamaClient,
}

impl SemanticMatcher {
    pub fn new(llm: OllamaClient) -> Self {
        Self { llm }
    }

    #[instrument(skip(self, source_attrs, candidate_attrs), fields(score=algo_score))]
    pub async fn resolve(
        &self,
        source_attrs:    &Value,
        candidate_attrs: &Value,
        algo_score:      f32,
        entity_type:     &str,
    ) -> Result<SemanticMatchResult> {
        let prompt = Prompts::resolve_ambiguous_match(
            source_attrs,
            candidate_attrs,
            algo_score,
            entity_type,
        );

        let raw = self.llm.generate(&prompt).await?;

        // The prompt instructs the model to respond with JSON only.
        // Find the JSON object in the response (model may add whitespace).
        let parsed = parse_decision_json(&raw);

        match parsed {
            Some(result) => {
                info!(
                    decision=?result.decision,
                    confidence=result.confidence,
                    "semantic matcher decided"
                );
                Ok(result)
            }
            None => {
                warn!(raw=%raw, "failed to parse LLM decision; defaulting to review");
                // Fail-safe: if LLM response is malformed, keep for human review.
                Ok(SemanticMatchResult {
                    decision:   MatchDecision::NoMatch,
                    confidence: 0.5,
                    reasoning:  "LLM response could not be parsed; routed to human review".to_string(),
                    algo_score,
                })
            }
        }
    }

    /// Explain a match decision in plain English.
    pub async fn explain(
        &self,
        source_attrs:    &Value,
        candidate_attrs: &Value,
        score:           f32,
        field_results:   &Value,
    ) -> Result<String> {
        let prompt = Prompts::explain_match(source_attrs, candidate_attrs, score, field_results);
        self.llm.generate(&prompt).await
    }
}

// Exposed for unit tests.
#[cfg(test)]
pub fn parse_decision_json_pub(raw: &str) -> Option<SemanticMatchResult> {
    parse_decision_json(raw)
}

fn parse_decision_json(raw: &str) -> Option<SemanticMatchResult> {
    // Extract first JSON object from the response.
    let start = raw.find('{')?;
    let end   = raw.rfind('}').map(|i| i + 1)?;
    let json  = &raw[start..end];

    #[derive(Deserialize)]
    struct LlmDecision {
        decision:   String,
        confidence: f32,
        reasoning:  String,
    }

    let d: LlmDecision = serde_json::from_str(json).ok()?;

    let decision = match d.decision.to_lowercase().as_str() {
        "match"    => MatchDecision::Match,
        "no_match" => MatchDecision::NoMatch,
        _          => return None,
    };

    Some(SemanticMatchResult {
        decision,
        confidence: d.confidence.clamp(0.0, 1.0),
        reasoning:  d.reasoning,
        algo_score: 0.0, // filled in by caller
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_clean_json() {
        let raw = r#"{"decision":"match","confidence":0.92,"reasoning":"Same tax ID."}"#;
        let result = parse_decision_json(raw).unwrap();
        assert_eq!(result.decision, MatchDecision::Match);
        assert!((result.confidence - 0.92).abs() < 0.001);
    }

    #[test]
    fn parse_json_with_preamble() {
        let raw = r#"Here is my analysis: {"decision":"no_match","confidence":0.88,"reasoning":"Different addresses."}"#;
        let result = parse_decision_json(raw).unwrap();
        assert_eq!(result.decision, MatchDecision::NoMatch);
    }

    #[test]
    fn parse_invalid_returns_none() {
        assert!(parse_decision_json("not json at all").is_none());
    }
}
