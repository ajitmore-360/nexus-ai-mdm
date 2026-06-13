use std::env;

//
// ========================================
// POLICY SERVICE SETTINGS
// ========================================
//

#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct PolicySettings {

    // =========================================
    // SERVER
    // =========================================

    /// Host to bind the policy service on
    pub host: String,

    /// Port to bind the policy service on (default: 8084)
    pub port: u16,

    // =========================================
    // DATABASE
    // =========================================

    /// PostgreSQL connection URL
    pub database_url: String,

    /// Max connections in pool
    pub db_max_connections: u32,

    /// Min idle connections in pool
    pub db_min_connections: u32,

    // =========================================
    // REDIS
    // =========================================

    /// Redis connection URL
    pub redis_url: String,

    // =========================================
    // OPA (Open Policy Agent)
    // =========================================

    /// Base URL of the OPA HTTP API (default: http://localhost:8181)
    pub opa_url: String,

    /// Timeout in seconds for OPA HTTP calls (default: 5)
    pub opa_timeout_secs: u64,

    // =========================================
    // CACHE
    // =========================================

    /// TTL in seconds for cached policy decisions (default: 300)
    pub cache_ttl_secs: u64,

    // =========================================
    // OBSERVABILITY
    // =========================================

    /// Log level filter string (e.g. "info", "debug")
    pub log_level: String,

    /// Application environment tag
    pub app_env: String,
}

impl PolicySettings {

    // =========================================
    // FROM ENV
    // =========================================

    pub fn from_env() -> Self {

        dotenvy::dotenv().ok();

        Self {

            // =====================================
            // SERVER
            // =====================================

            host: env::var("POLICY_SERVICE_HOST")
                .unwrap_or_else(|_| "0.0.0.0".into()),

            port: env::var("POLICY_SERVICE_PORT")
                .unwrap_or_else(|_| "8084".into())
                .parse()
                .unwrap_or(8084),

            // =====================================
            // DATABASE
            // =====================================

            database_url: env::var("DATABASE_URL")
                .expect("DATABASE_URL environment variable is required"),

            db_max_connections: env::var("DB_MAX_CONNECTIONS")
                .unwrap_or_else(|_| "20".into())
                .parse()
                .unwrap_or(20),

            db_min_connections: env::var("DB_MIN_CONNECTIONS")
                .unwrap_or_else(|_| "2".into())
                .parse()
                .unwrap_or(2),

            // =====================================
            // REDIS
            // =====================================

            redis_url: env::var("REDIS_URL")
                .unwrap_or_else(|_| "redis://127.0.0.1/".into()),

            // =====================================
            // OPA
            // =====================================

            opa_url: env::var("OPA_URL")
                .unwrap_or_else(|_| "http://localhost:8181".into()),

            opa_timeout_secs: env::var("OPA_TIMEOUT_SECS")
                .unwrap_or_else(|_| "5".into())
                .parse()
                .unwrap_or(5),

            // =====================================
            // CACHE
            // =====================================

            cache_ttl_secs: env::var("POLICY_CACHE_TTL_SECS")
                .unwrap_or_else(|_| "300".into())
                .parse()
                .unwrap_or(300),

            // =====================================
            // OBSERVABILITY
            // =====================================

            log_level: env::var("RUST_LOG")
                .unwrap_or_else(|_| "info".into()),

            app_env: env::var("APP_ENV")
                .unwrap_or_else(|_| "development".into()),
        }
    }

    // =========================================
    // BIND ADDRESS
    // =========================================

    #[allow(dead_code)]
    pub fn bind_address(&self) -> String {
        format!("{}:{}", self.host, self.port)
    }
}
