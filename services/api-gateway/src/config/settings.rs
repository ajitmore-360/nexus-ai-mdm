use std::env;

#[allow(dead_code)]
#[derive(Clone, Debug)]
pub struct Settings {

    // =========================================
    // GATEWAY
    // =========================================
    pub gateway_host: String,
    pub gateway_port: u16,

    // =========================================
    // SERVICES
    // =========================================
    pub ai_service_url:           String,
    pub mdm_core_url:             String,
    pub ingest_service_url:       String,
    pub policy_service_url:       String,
    pub search_service_url:       String,
    pub notification_service_url: String,
    pub distribution_service_url: String,

    // =========================================
    // WEBSOCKET
    // =========================================
    pub websocket_url: String,

    // =========================================
    // INFRA
    // =========================================
    pub redis_url: String,
    pub kafka_brokers: String,

    // =========================================
    // HTTP
    // =========================================
    pub request_timeout_seconds: u64,
    pub max_retries: u32,

    // =========================================
    // OBSERVABILITY
    // =========================================
    pub enable_tracing: bool,
    pub log_level: String,
}

impl Settings {

    pub fn from_env() -> Self {

        dotenvy::dotenv().ok();

        Self {

            // =====================================
            // GATEWAY
            // =====================================
            gateway_host: env::var("GATEWAY_HOST")
                .unwrap_or_else(|_| "127.0.0.1".into()),

            gateway_port: env::var("GATEWAY_PORT")
                .unwrap_or_else(|_| "8080".into())
                .parse()
                .unwrap_or(8080),

            // =====================================
            // SERVICES
            // =====================================
            ai_service_url: env::var("AI_SERVICE_URL")
                .unwrap_or_else(|_| {
                    "http://127.0.0.1:8082".into()
                }),

            mdm_core_url: env::var("MDM_CORE_URL")
                .unwrap_or_else(|_| {
                    "http://127.0.0.1:8081".into()
                }),

            ingest_service_url: env::var("INGEST_SERVICE_URL")
                .unwrap_or_else(|_| {
                    "http://127.0.0.1:8083".into()
                }),

            policy_service_url: env::var("POLICY_SERVICE_URL")
                .unwrap_or_else(|_| "http://127.0.0.1:8084".into()),

            search_service_url: env::var("SEARCH_SERVICE_URL")
                .unwrap_or_else(|_| "http://127.0.0.1:8085".into()),

            notification_service_url: env::var("NOTIFICATION_SERVICE_URL")
                .unwrap_or_else(|_| "http://127.0.0.1:8086".into()),

            distribution_service_url: env::var("DISTRIBUTION_SERVICE_URL")
                .unwrap_or_else(|_| "http://127.0.0.1:8089".into()),

            // =====================================
            // WEBSOCKET
            // =====================================
            websocket_url: env::var("WEBSOCKET_URL")
                .unwrap_or_else(|_| {
                    "ws://127.0.0.1:4000".into()
                }),

            // =====================================
            // INFRA
            // =====================================
            redis_url: env::var("REDIS_URL")
                .unwrap_or_else(|_| {
                    "redis://127.0.0.1/".into()
                }),

            kafka_brokers: env::var("KAFKA_BROKERS")
                .unwrap_or_else(|_| {
                    "localhost:9092".into()
                }),

            // =====================================
            // HTTP
            // =====================================
            request_timeout_seconds: env::var("REQUEST_TIMEOUT_SECONDS")
                .unwrap_or_else(|_| "30".into())
                .parse()
                .unwrap_or(30),

            max_retries: env::var("MAX_RETRIES")
                .unwrap_or_else(|_| "3".into())
                .parse()
                .unwrap_or(3),

            // =====================================
            // OBSERVABILITY
            // =====================================
            enable_tracing: env::var("ENABLE_TRACING")
                .unwrap_or_else(|_| "true".into())
                .parse()
                .unwrap_or(true),

            log_level: env::var("LOG_LEVEL")
                .unwrap_or_else(|_| "info".into()),
        }
    }

    // =========================================
    // FULL GATEWAY ADDRESS
    // =========================================
    #[allow(dead_code)]
    pub fn gateway_address(&self) -> String {
        format!("{}:{}", self.gateway_host, self.gateway_port)
    }
}