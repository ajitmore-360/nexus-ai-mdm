use std::env;

/// All runtime configuration for the enrichment service.
/// Values are read from environment variables with sane defaults for local dev.
#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct EnrichmentSettings {
    // ── HTTP ──────────────────────────────────────────────────────────────────
    /// Port the Axum HTTP server listens on.
    pub port: u16,

    // ── Database ──────────────────────────────────────────────────────────────
    pub database_url: String,

    // ── Redis ─────────────────────────────────────────────────────────────────
    pub redis_url: String,

    // ── Downstream services ───────────────────────────────────────────────────
    /// Base URL of mdm-core, e.g. "http://localhost:8080"
    pub mdm_core_url: String,

    // ── Kafka ─────────────────────────────────────────────────────────────────
    pub kafka_brokers:   String,
    pub kafka_group_id:  String,

    // ── Provider feature flags ────────────────────────────────────────────────
    pub enable_dnb:                 bool,
    pub enable_experian:            bool,
    pub enable_address_validation:  bool,

    /// When true every provider runs in mock mode (no real API calls / no cost).
    pub mock_mode: bool,

    // ── API keys (only used when mock_mode = false) ───────────────────────────
    pub dnb_api_key:      Option<String>,
    pub experian_api_key: Option<String>,
}

impl EnrichmentSettings {
    /// Build settings from environment variables.
    pub fn from_env() -> anyhow::Result<Self> {
        Ok(Self {
            port: env_u16("ENRICHMENT_PORT", 8088),

            database_url: env::var("DATABASE_URL")
                .map_err(|_| anyhow::anyhow!("DATABASE_URL is required but not set"))?,

            redis_url: env::var("REDIS_URL")
                .unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string()),

            mdm_core_url: env::var("MDM_CORE_URL")
                .unwrap_or_else(|_| "http://localhost:8080".to_string()),

            kafka_brokers: env::var("KAFKA_BROKERS")
                .unwrap_or_else(|_| "localhost:9092".to_string()),

            kafka_group_id: env::var("KAFKA_GROUP_ID")
                .unwrap_or_else(|_| "nexus-enrichment".to_string()),

            enable_dnb: env_bool("ENABLE_DNB", true),
            enable_experian: env_bool("ENABLE_EXPERIAN", true),
            enable_address_validation: env_bool("ENABLE_ADDRESS_VALIDATION", true),

            // Default false so a K8s/bare-metal deployment without docker-compose
            // does not silently return fake enrichment data.  Set
            // ENRICHMENT_MOCK_MODE=true explicitly in dev/CI environments.
            mock_mode: env_bool("ENRICHMENT_MOCK_MODE", false),

            dnb_api_key:      env::var("DNB_API_KEY").ok(),
            experian_api_key: env::var("EXPERIAN_API_KEY").ok(),
        })
    }
}

// ── helpers ───────────────────────────────────────────────────────────────────

fn env_u16(key: &str, default: u16) -> u16 {
    env::var(key)
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(default)
}

fn env_bool(key: &str, default: bool) -> bool {
    match env::var(key).ok().as_deref() {
        Some("true")  | Some("1") | Some("yes") => true,
        Some("false") | Some("0") | Some("no")  => false,
        _ => default,
    }
}
