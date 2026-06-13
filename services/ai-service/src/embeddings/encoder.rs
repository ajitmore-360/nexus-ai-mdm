use anyhow::Result;
use serde_json::Value;
use tracing::instrument;

use crate::llm::OllamaClient;

/// Converts entity attributes into a single canonical text representation
/// suitable for embedding.
#[allow(dead_code)]
pub fn entity_to_text(attributes: &Value) -> String {
    match attributes.as_object() {
        None => String::new(),
        Some(map) => {
            map.iter()
                .filter_map(|(k, v)| {
                    let val = match v {
                        Value::String(s) => s.trim().to_string(),
                        Value::Number(n) => n.to_string(),
                        Value::Bool(b)   => b.to_string(),
                        _                => return None,
                    };
                    if val.is_empty() { None } else { Some(format!("{}: {}", k, val)) }
                })
                .collect::<Vec<_>>()
                .join(". ")
        }
    }
}

/// Embeds a free-form text string using the configured embedding model.
pub struct Encoder {
    client: OllamaClient,
}

impl Encoder {
    pub fn new(client: OllamaClient) -> Self {
        Self { client }
    }

    /// Embed `text` and return the vector.
    #[instrument(skip(self, text))]
    pub async fn encode(&self, text: &str) -> Result<Vec<f32>> {
        if text.trim().is_empty() {
            return Ok(vec![]);
        }
        self.client.embed(text).await
    }

    /// Embed a batch of texts, returning vectors in the same order.
    /// Errors on individual items are returned as empty vectors.
    #[allow(dead_code)]
    pub async fn encode_batch(&self, texts: &[String]) -> Vec<Vec<f32>> {
        let mut results = Vec::with_capacity(texts.len());
        for text in texts {
            let vec = self.encode(text).await.unwrap_or_default();
            results.push(vec);
        }
        results
    }

    /// Build entity text from attributes JSON and embed it.
    #[allow(dead_code)]
    pub async fn embed_entity(&self, attributes: &Value) -> Result<Vec<f32>> {
        let text = entity_to_text(attributes);
        self.encode(&text).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn entity_to_text_basic() {
        let attrs = json!({"name": "Acme Corp", "email": "info@acme.com"});
        let text  = entity_to_text(&attrs);
        assert!(text.contains("Acme Corp"));
        assert!(text.contains("info@acme.com"));
    }

    #[test]
    fn entity_to_text_skips_objects() {
        let attrs = json!({"name": "Acme", "nested": {"key": "val"}});
        let text  = entity_to_text(&attrs);
        assert!(text.contains("Acme"));
        assert!(!text.contains("nested"));
    }

    #[test]
    fn entity_to_text_empty_values_skipped() {
        let attrs = json!({"name": "Acme", "phone": ""});
        let text  = entity_to_text(&attrs);
        assert!(!text.contains("phone"));
    }
}
