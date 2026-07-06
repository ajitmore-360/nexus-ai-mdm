use std::sync::Arc;

use reqwest::Client;
use sqlx::PgPool;

use nexus_auth::jwt::JwtConfig;

use crate::config::settings::IngestSettings;
use crate::processor::IngestProcessor;

#[derive(Clone)]
pub struct AppState {
    pub settings:   Arc<IngestSettings>,
    pub processor:  Arc<IngestProcessor>,
    pub pool:       PgPool,
    pub jwt_config: Arc<JwtConfig>,
    #[allow(dead_code)]
    pub http:       Client,
}

impl AppState {
    pub fn new(settings: IngestSettings, pool: PgPool, jwt_config: JwtConfig) -> Self {
        let timeout = std::time::Duration::from_secs(settings.ingest_timeout_secs);
        let http = Client::builder()
            .timeout(timeout)
            .pool_max_idle_per_host(10)
            .build()
            .expect("failed to build HTTP client");

        let processor = Arc::new(IngestProcessor::new(
            http.clone(),
            settings.mdm_core_url.clone(),
        ));

        Self {
            settings:   Arc::new(settings),
            processor,
            pool,
            jwt_config: Arc::new(jwt_config),
            http,
        }
    }
}
