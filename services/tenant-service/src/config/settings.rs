#[allow(dead_code)]
pub struct TenantServiceSettings {
    pub port:         u16,
    pub database_url: String,
    pub redis_url:    String,
}

impl TenantServiceSettings {
    pub fn from_env() -> Self {
        Self {
            port:         std::env::var("TENANT_SERVICE_PORT")
                              .ok().and_then(|v| v.parse().ok()).unwrap_or(8090),
            database_url: std::env::var("DATABASE_URL")
                              .expect("DATABASE_URL required"),
            redis_url:    std::env::var("REDIS_URL")
                              .unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string()),
        }
    }
}
