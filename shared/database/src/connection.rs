use std::time::Duration;

use sqlx::{
    postgres::PgPoolOptions,
    PgPool,
};

use anyhow::Result;

use crate::config::DatabaseConfig;

pub async fn create_pool(
    config: &DatabaseConfig,
) -> Result<PgPool> {

    let options =
        PgConnectOptions::from_str(
            database_url
        )?
        .ssl_mode(PgSslMode::Require)
        .application_name("nexus-ai-mdm");

    let pool =
        PgPoolOptions::new()

            .max_connections(config.max_connections)

            .min_connections(config.min_connections)

            .acquire_timeout(
                std::time::Duration::from_secs(10)
            )

            .idle_timeout(
                std::time::Duration::from_secs(600)
            )

            .max_lifetime(
                std::time::Duration::from_secs(1800)
            )

            // ====================================
            // HEALTH
            // ====================================
            //

            .test_before_acquire(true)

            .connect(
                &config.database_url
            )
            .await?;

    Ok(pool)
}