use anyhow::{Context, Result};

/// All runtime configuration for the ingest service.
///
/// Values are loaded from environment variables with sane defaults so the
/// service can run locally without any `.env` file.
#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct IngestSettings {
    /// TCP port the HTTP server listens on.
    pub port: u16,

    /// PostgreSQL connection string.
    pub database_url: String,

    /// Base URL of the MDM-Core service (e.g. `http://localhost:8081`).
    pub mdm_core_url: String,

    /// Redis connection URL (e.g. `redis://127.0.0.1:6379`).
    pub redis_url: String,

    /// Comma-separated list of Kafka broker addresses.
    pub kafka_brokers: String,

    /// Kafka consumer group id.
    pub kafka_group_id: String,

    /// Kafka topics to consume from.
    pub kafka_topics: Vec<String>,

    /// Maximum records per ingest batch.
    pub max_batch_size: usize,

    /// Per-request timeout (seconds) when calling MDM-Core.
    pub ingest_timeout_secs: u64,

    /// Base URL of the AI enrichment service.
    pub ai_service_url: String,
}

impl IngestSettings {
    /// Load settings from environment variables.
    pub fn from_env() -> Result<Self> {
        let kafka_topics_raw = std::env::var("KAFKA_TOPICS")
            .unwrap_or_else(|_| "ingest.raw".to_string());

        let kafka_topics = kafka_topics_raw
            .split(',')
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect::<Vec<_>>();

        Ok(Self {
            port: std::env::var("INGEST_PORT")
                .unwrap_or_else(|_| "8082".to_string())
                .parse::<u16>()
                .context("INGEST_PORT must be a valid port number")?,

            database_url: std::env::var("DATABASE_URL")
                .context("DATABASE_URL is required")?,

            mdm_core_url: std::env::var("MDM_CORE_URL")
                .unwrap_or_else(|_| "http://localhost:8081".to_string()),

            redis_url: std::env::var("REDIS_URL")
                .unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string()),

            kafka_brokers: std::env::var("KAFKA_BROKERS")
                .unwrap_or_else(|_| "localhost:9092".to_string()),

            kafka_group_id: std::env::var("KAFKA_GROUP_ID")
                .unwrap_or_else(|_| "ingest-service".to_string()),

            kafka_topics,

            max_batch_size: std::env::var("MAX_BATCH_SIZE")
                .unwrap_or_else(|_| "10000".to_string())
                .parse::<usize>()
                .context("MAX_BATCH_SIZE must be a positive integer")?,

            ingest_timeout_secs: std::env::var("INGEST_TIMEOUT_SECS")
                .unwrap_or_else(|_| "30".to_string())
                .parse::<u64>()
                .context("INGEST_TIMEOUT_SECS must be a positive integer")?,

            ai_service_url: std::env::var("AI_SERVICE_URL")
                .unwrap_or_else(|_| "http://localhost:8083".to_string()),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_are_valid() {
        // DATABASE_URL is required — provide a placeholder so the rest of the defaults are tested.
        std::env::set_var("DATABASE_URL", "postgres://test:test@localhost:5432/test");
        let settings = IngestSettings::from_env().expect("defaults should be valid");
        assert_eq!(settings.port, 8082);
        assert!(!settings.mdm_core_url.is_empty());
        assert!(!settings.kafka_topics.is_empty());
        assert!(settings.max_batch_size > 0);
        std::env::remove_var("DATABASE_URL");
    }

    #[test]
    fn kafka_topics_parsed_correctly() {
        std::env::set_var("KAFKA_TOPICS", "topic.a, topic.b ,topic.c");
        let settings = IngestSettings::from_env().expect("should parse");
        assert_eq!(settings.kafka_topics, vec!["topic.a", "topic.b", "topic.c"]);
        std::env::remove_var("KAFKA_TOPICS");
    }
}
