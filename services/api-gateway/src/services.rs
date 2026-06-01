use reqwest::Client;

use std::time::Duration;

//
// ========================================
// 🌐 SHARED SERVICE CLIENTS
// ========================================
//

#[derive(Clone)]
pub struct ServiceClients {

    // Shared HTTP client
    pub http: Client,
}

impl ServiceClients {

    //
    // ====================================
    // 🚀 INITIALIZE CLIENTS
    // ====================================
    //

    pub fn new() -> Self {

        // ====================================
        // 🌐 REQWEST CLIENT
        // ====================================

        let http = Client::builder()

            // Connection pooling
            .pool_max_idle_per_host(20)

            // Timeouts
            .connect_timeout(Duration::from_secs(5))
            .timeout(Duration::from_secs(60))

            // TCP keepalive
            .tcp_keepalive(Duration::from_secs(30))

            // User agent
            .user_agent("nexus-api-gateway/1.0")

            // Build
            .build()
            .expect("failed to build reqwest client");

        Self {
            http,
        }
    }
}