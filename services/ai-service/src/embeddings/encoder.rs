use std::collections::HashMap;
use std::sync::Mutex;

use anyhow::Result;
use serde_json::Value;
use tracing::instrument;

use crate::llm::OllamaClient;

/// Maximum number of embeddings to keep in the in-process cache.
/// Each entry is ~1.5 KB (384 f32s). 2000 entries ≈ 3 MB total.
const EMBED_CACHE_CAPACITY: usize = 2000;

/// Sequence-number LRU cache for embedding vectors.
///
/// On eviction the single least-recently-used entry is removed, preserving
/// the rest of the warm cache.  This prevents the thundering herd that the
/// previous full-clear strategy caused at capacity boundaries.
struct LruEmbeddingCache {
    /// key → (last_access_seq, embedding vector)
    map:      HashMap<String, (u64, Vec<f32>)>,
    /// Monotonically increasing access counter.
    counter:  u64,
    capacity: usize,
}

impl LruEmbeddingCache {
    fn new(capacity: usize) -> Self {
        Self {
            map: HashMap::with_capacity(capacity),
            counter: 0,
            capacity,
        }
    }

    fn get(&mut self, key: &str) -> Option<Vec<f32>> {
        if let Some((seq, vec)) = self.map.get_mut(key) {
            self.counter += 1;
            *seq = self.counter;
            Some(vec.clone())
        } else {
            None
        }
    }

    fn insert(&mut self, key: String, value: Vec<f32>) {
        if self.map.len() >= self.capacity && !self.map.contains_key(&key) {
            // Evict the single LRU entry — O(n) scan, acceptable for n ≤ 2000.
            let lru_key = self.map.iter()
                .min_by_key(|(_, (seq, _))| *seq)
                .map(|(k, _)| k.clone());
            if let Some(k) = lru_key {
                self.map.remove(&k);
                tracing::debug!("embedding cache LRU eviction — removed 1 entry");
            }
        }
        self.counter += 1;
        self.map.insert(key, (self.counter, value));
    }
}

/// Converts entity attributes into a single canonical text representation
/// suitable for embedding.
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
///
/// Embeddings are cached in-process by their full text using an LRU policy.
/// The same user query arriving twice returns instantly from the cache instead
/// of making a second Ollama call (~80ms saved per cache hit).
pub struct Encoder {
    client: OllamaClient,
    cache:  Mutex<LruEmbeddingCache>,
}

impl Encoder {
    pub fn new(client: OllamaClient) -> Self {
        Self {
            client,
            cache: Mutex::new(LruEmbeddingCache::new(EMBED_CACHE_CAPACITY)),
        }
    }

    /// Embed `text` and return the vector.
    #[instrument(skip(self, text))]
    pub async fn encode(&self, text: &str) -> Result<Vec<f32>> {
        if text.trim().is_empty() {
            return Ok(vec![]);
        }

        // Fast path: LRU hit — also updates the access sequence.
        {
            let mut guard = self.cache.lock().unwrap_or_else(|e| e.into_inner());
            if let Some(cached) = guard.get(text) {
                tracing::debug!(len = text.len(), "embedding cache hit");
                return Ok(cached);
            }
        }

        // Cache miss: call Ollama.
        let embedding = self.client.embed(text).await?;

        // Insert with LRU eviction on capacity (single entry evicted, no full clear).
        {
            let mut guard = self.cache.lock().unwrap_or_else(|e| e.into_inner());
            guard.insert(text.to_string(), embedding.clone());
        }

        Ok(embedding)
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
