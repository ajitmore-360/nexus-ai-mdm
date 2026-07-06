use std::time::Duration;

#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct Settings {
    pub port:             u16,
    pub database_url:     String,
    pub redis_url:        String,
    pub redis_key_prefix: String,

    // Ollama / LLM
    pub ollama_url:       String,
    pub llm_model:        String,
    pub embed_model:      String,
    pub llm_timeout_secs: u64,
    pub llm_temperature:  f32,
    pub llm_max_tokens:   u32,
    /// Context window size passed to Ollama. Smaller = faster prompt eval.
    /// 4096 covers all MDM copilot queries; use 8192 only if long doc RAG is needed.
    pub llm_num_ctx:      u32,
    /// CPU threads for Ollama inference. 0 = let Ollama auto-detect (numcpu/2).
    /// Set to host physical core count for maximum throughput on CPU-only deployments.
    pub llm_num_threads:  u32,

    // RAG
    pub rag_top_k:             usize,
    pub rag_min_score:         f32,
    /// Maximum characters per retrieved document's content before truncation.
    pub rag_max_doc_chars:     usize,
    /// Maximum total characters for the full assembled RAG context string.
    pub rag_max_context_chars: usize,

    // Semantic matching
    pub semantic_match_timeout_secs: u64,
}

impl Settings {
    pub fn from_env() -> anyhow::Result<Self> {
        Ok(Self {
            port: env_u16("AI_SERVICE_PORT", 8082),
            database_url: std::env::var("DATABASE_URL")
                .map_err(|_| anyhow::anyhow!("DATABASE_URL is required but not set"))?,
            redis_url: std::env::var("REDIS_URL")
                .unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string()),
            redis_key_prefix: std::env::var("REDIS_KEY_PREFIX")
                .unwrap_or_else(|_| "nexus".to_string()),

            ollama_url: std::env::var("OLLAMA_URL")
                .unwrap_or_else(|_| "http://localhost:11434".to_string()),
            // llama3.2 only ships in 1b and 3b; there is no 8b variant.
            llm_model: std::env::var("LLM_MODEL")
                .unwrap_or_else(|_| "llama3.2:3b".to_string()),
            embed_model: std::env::var("EMBED_MODEL")
                .unwrap_or_else(|_| "nomic-embed-text".to_string()),
            // 120s — CPU-only generation takes 25-35s; 60s timed out under load.
            llm_timeout_secs: env_u64("LLM_TIMEOUT_SECS", 120),
            llm_temperature:  env_f32("LLM_TEMPERATURE", 0.2),
            // 512 tokens is generous for MDM copilot answers (~350 words).
            // 2048 allowed 4x the needed length and multiplied wall-clock time.
            llm_max_tokens:   env_u32("LLM_MAX_TOKENS", 512),
            llm_num_ctx:      env_u32("LLM_NUM_CTX", 4096),
            llm_num_threads:  env_u32("LLM_NUM_THREADS", 0),

            rag_top_k:             env_usize("RAG_TOP_K", 5),
            rag_min_score:         env_f32("RAG_MIN_SCORE", 0.70),
            rag_max_doc_chars:     env_usize("RAG_MAX_DOC_CHARS", 2_000),
            rag_max_context_chars: env_usize("RAG_MAX_CONTEXT_CHARS", 8_000),

            semantic_match_timeout_secs: env_u64("SEMANTIC_MATCH_TIMEOUT_SECS", 30),
        })
    }

    pub fn llm_timeout(&self) -> Duration {
        Duration::from_secs(self.llm_timeout_secs)
    }
}

fn env_u16(key: &str, default: u16) -> u16 {
    std::env::var(key).ok().and_then(|v| v.parse().ok()).unwrap_or(default)
}

fn env_u32(key: &str, default: u32) -> u32 {
    std::env::var(key).ok().and_then(|v| v.parse().ok()).unwrap_or(default)
}

fn env_u64(key: &str, default: u64) -> u64 {
    std::env::var(key).ok().and_then(|v| v.parse().ok()).unwrap_or(default)
}

fn env_f32(key: &str, default: f32) -> f32 {
    std::env::var(key).ok().and_then(|v| v.parse().ok()).unwrap_or(default)
}

fn env_usize(key: &str, default: usize) -> usize {
    std::env::var(key).ok().and_then(|v| v.parse().ok()).unwrap_or(default)
}
