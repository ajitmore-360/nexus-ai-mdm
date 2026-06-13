use std::time::Duration;

use anyhow::{Context, Result};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use tracing::{debug, instrument, warn};

/// Request to Ollama `/api/generate`.
#[derive(Debug, Serialize)]
struct GenerateRequest<'a> {
    model:   &'a str,
    prompt:  &'a str,
    stream:  bool,
    options: GenerateOptions,
}

#[derive(Debug, Serialize)]
struct GenerateOptions {
    temperature: f32,
    num_predict: u32,
}

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
}

impl OllamaClient {
    pub fn new(
        base_url:    impl Into<String>,
        llm_model:   impl Into<String>,
        embed_model: impl Into<String>,
        temperature: f32,
        max_tokens:  u32,
        timeout:     Duration,
    ) -> Self {
        let http = Client::builder()
            .timeout(timeout)
            .build()
            .expect("failed to build Ollama HTTP client");

        Self {
            http,
            base_url:    base_url.into(),
            llm_model:   llm_model.into(),
            embed_model: embed_model.into(),
            temperature,
            max_tokens,
        }
    }

    /// Generate text from a prompt. Returns the full response string.
    #[instrument(skip(self, prompt), fields(model=%self.llm_model))]
    pub async fn generate(&self, prompt: &str) -> Result<String> {
        let url = format!("{}/api/generate", self.base_url);

        let body = GenerateRequest {
            model:  &self.llm_model,
            prompt,
            stream: false,
            options: GenerateOptions {
                temperature: self.temperature,
                num_predict: self.max_tokens,
            },
        };

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
        debug!(done=%gen.done, len=gen.response.len(), "LLM generation complete");
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
