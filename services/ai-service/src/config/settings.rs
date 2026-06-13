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

    // RAG
    pub rag_top_k:        usize,
    pub rag_min_score:    f32,

    // Semantic matching
    pub semantic_match_timeout_secs: u64,
}

impl Settings {
    pub fn from_env() -> Self {
        Self {
            port: env_u16("AI_SERVICE_PORT", 8082),
            database_url: std::env::var("DATABASE_URL")
                .expect("DATABASE_URL must be set"),
            redis_url: std::env::var("REDIS_URL")
                .unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string()),
            redis_key_prefix: std::env::var("REDIS_KEY_PREFIX")
                .unwrap_or_else(|_| "nexus".to_string()),

            ollama_url: std::env::var("OLLAMA_URL")
                .unwrap_or_else(|_| "http://localhost:11434".to_string()),
            llm_model: std::env::var("LLM_MODEL")
                .unwrap_or_else(|_| "llama3.2:8b".to_string()),
            embed_model: std::env::var("EMBED_MODEL")
                .unwrap_or_else(|_| "nomic-embed-text".to_string()),
            llm_timeout_secs: env_u64("LLM_TIMEOUT_SECS", 60),
            llm_temperature:  env_f32("LLM_TEMPERATURE", 0.2),
            llm_max_tokens:   env_u32("LLM_MAX_TOKENS", 2048),

            rag_top_k:     env_usize("RAG_TOP_K", 5),
            rag_min_score: env_f32("RAG_MIN_SCORE", 0.70),

            semantic_match_timeout_secs: env_u64("SEMANTIC_MATCH_TIMEOUT_SECS", 30),
        }
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
