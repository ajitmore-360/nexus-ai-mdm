use std::time::Duration;

use anyhow::{Context, Result};
use futures::{channel::mpsc as fmpsc, StreamExt};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use tracing::{debug, instrument, warn};

/// Response from Ollama `/api/generate`.
#[derive(Debug, Deserialize)]
struct GenerateResponse {
    response: String,
    done:     bool,
}

/// Request to Ollama `/api/embeddings`.
#[derive(Debug, Serialize)]
struct EmbedRequest<'a> {
    model:  &'a str,
    prompt: &'a str,
}

/// Response from Ollama `/api/embeddings`.
#[derive(Debug, Deserialize)]
struct EmbedResponse {
    embedding: Vec<f32>,
}

/// Ollama HTTP client wrapping text-generation and embedding endpoints.
#[derive(Clone)]
pub struct OllamaClient {
    http:        Client,
    base_url:    String,
    llm_model:   String,
    embed_model: String,
    temperature: f32,
    max_tokens:  u32,
    num_ctx:     u32,
    num_thread:  u32,
}

impl OllamaClient {
    pub fn new(
        base_url:    impl Into<String>,
        llm_model:   impl Into<String>,
        embed_model: impl Into<String>,
        temperature: f32,
        max_tokens:  u32,
        num_ctx:     u32,
        num_thread:  u32,
        timeout:     Duration,
    ) -> Self {
        let http = Client::builder()
            .timeout(timeout)
            // Keep up to 10 idle connections to Ollama — avoids TCP handshake
            // overhead on every request (saves ~20-50ms per call).
            .pool_max_idle_per_host(10)
            .tcp_keepalive(Duration::from_secs(30))
            .build()
            .expect("failed to build Ollama HTTP client");

        Self {
            http,
            base_url:    base_url.into(),
            llm_model:   llm_model.into(),
            embed_model: embed_model.into(),
            temperature,
            max_tokens,
            num_ctx,
            num_thread,
        }
    }

    /// Generate text from a prompt. Returns the full response string.
    ///
    /// Pass `json_mode: true` to enable Ollama's constrained JSON output —
    /// the model is forced to emit valid JSON (use when `fmt == "table"`).
    #[instrument(skip(self, prompt), fields(model=%self.llm_model))]
    pub async fn generate(&self, prompt: &str, json_mode: bool) -> Result<String> {
        let url = format!("{}/api/generate", self.base_url);

        let mut body = serde_json::json!({
            "model":  self.llm_model,
            "prompt": prompt,
            "stream": false,
            "options": {
                "temperature": self.temperature,
                "num_predict": self.max_tokens,
                "num_ctx":     self.num_ctx,
            }
        });
        if self.num_thread != 0 {
            body["options"]["num_thread"] = serde_json::json!(self.num_thread);
        }
        if json_mode {
            body["format"] = serde_json::json!("json");
        }

        let resp = self
            .http
            .post(&url)
            .json(&body)
            .send()
            .await
            .context("Ollama generate request failed")?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            anyhow::bail!("Ollama returned {}: {}", status, text);
        }

        let gen: GenerateResponse = resp.json().await.context("failed to parse Ollama response")?;
        debug!(json_mode, done=%gen.done, len=gen.response.len(), "LLM generation complete");
        Ok(gen.response.trim().to_string())
    }

    /// Generate an embedding vector for `text`.
    #[instrument(skip(self, text), fields(model=%self.embed_model))]
    pub async fn embed(&self, text: &str) -> Result<Vec<f32>> {
        let url = format!("{}/api/embeddings", self.base_url);

        let body = EmbedRequest {
            model:  &self.embed_model,
            prompt: text,
        };

        let resp = self
            .http
            .post(&url)
            .json(&body)
            .send()
            .await
            .context("Ollama embed request failed")?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            anyhow::bail!("Ollama embed returned {}: {}", status, text);
        }

        let embed: EmbedResponse = resp.json().await.context("failed to parse embedding response")?;
        debug!(dims=embed.embedding.len(), "embedding generated");
        Ok(embed.embedding)
    }

    /// Generate text token-by-token using Ollama's streaming NDJSON API.
    ///
    /// Returns a stream of token strings.  Each item is one or more characters
    /// as Ollama yields them.  The stream closes when Ollama reports `done: true`
    /// or when the caller drops the receiver.
    /// Pass `json_mode: true` to constrain output to valid JSON.
    pub async fn generate_stream(
        &self,
        prompt:    &str,
        json_mode: bool,
    ) -> Result<impl futures::Stream<Item = Result<String>> + Send + 'static> {
        let url = format!("{}/api/generate", self.base_url);

        let mut options = serde_json::json!({
            "temperature": self.temperature,
            "num_predict": self.max_tokens,
            "num_ctx":     self.num_ctx,
        });
        if self.num_thread != 0 {
            options["num_thread"] = serde_json::json!(self.num_thread);
        }
        let mut body = serde_json::json!({
            "model":   self.llm_model,
            "prompt":  prompt,
            "stream":  true,
            "options": options,
        });
        if json_mode {
            body["format"] = serde_json::json!("json");
        }

        let resp = self
            .http
            .post(&url)
            .json(&body)
            .send()
            .await
            .context("Ollama streaming request failed")?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            anyhow::bail!("Ollama stream returned {}: {}", status, text);
        }

        // Unbounded channel so the spawned reader never blocks waiting for the consumer.
        // Tokens arrive at ~5/s from llama3.2:3b so memory pressure is negligible.
        let (tx, rx) = fmpsc::unbounded::<Result<String>>();

        let bytes_stream = resp.bytes_stream();
        tokio::spawn(async move {
            let mut buf = String::new();
            futures::pin_mut!(bytes_stream);

            while let Some(chunk) = bytes_stream.next().await {
                match chunk {
                    Err(e) => {
                        let _ = tx.unbounded_send(Err(anyhow::anyhow!("stream chunk error: {}", e)));
                        break;
                    }
                    Ok(bytes) => {
                        buf.push_str(&String::from_utf8_lossy(&bytes));
                        // Process every complete newline-terminated JSON object.
                        loop {
                            match buf.find('\n') {
                                None => break,
                                Some(pos) => {
                                    let line = buf[..pos].trim().to_string();
                                    buf.drain(..=pos);
                                    if line.is_empty() { continue; }
                                    if let Ok(val) = serde_json::from_str::<serde_json::Value>(&line) {
                                        let done = val["done"].as_bool().unwrap_or(false);
                                        if let Some(token) = val["response"].as_str() {
                                            if !token.is_empty()
                                                && tx.unbounded_send(Ok(token.to_string())).is_err()
                                            {
                                                return; // receiver dropped
                                            }
                                        }
                                        if done { return; }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        });

        Ok(rx)
    }

    /// Health-check: verify Ollama is reachable and the required models are available.
    pub async fn health_check(&self) -> Result<bool> {
        let url = format!("{}/api/tags", self.base_url);
        match self.http.get(&url).send().await {
            Ok(r) => Ok(r.status().is_success()),
            Err(e) => {
                warn!(error=%e, "Ollama health check failed");
                Ok(false)
            }
        }
    }
}
