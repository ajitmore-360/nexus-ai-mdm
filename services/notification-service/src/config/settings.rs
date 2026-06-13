#[allow(dead_code)]
pub struct NotificationSettings {
    pub port:             u16,
    pub database_url:     String,
    pub redis_url:        String,
    pub redis_key_prefix: String,
    /// Interval (seconds) for pruning stale client connections
    pub heartbeat_secs:   u64,
}

impl NotificationSettings {
    pub fn from_env() -> Self {
        Self {
            port:             env_u16("NOTIFICATION_PORT", 8086),
            database_url:     std::env::var("DATABASE_URL").expect("DATABASE_URL required"),
            redis_url:        std::env::var("REDIS_URL")
                                  .unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string()),
            redis_key_prefix: std::env::var("REDIS_KEY_PREFIX")
                                  .unwrap_or_else(|_| "nexus".to_string()),
            heartbeat_secs:   env_u64("NOTIFICATION_HEARTBEAT_SECS", 30),
        }
    }
}

fn env_u16(k: &str, d: u16) -> u16 {
    std::env::var(k).ok().and_then(|v| v.parse().ok()).unwrap_or(d)
}
fn env_u64(k: &str, d: u64) -> u64 {
    std::env::var(k).ok().and_then(|v| v.parse().ok()).unwrap_or(d)
}
