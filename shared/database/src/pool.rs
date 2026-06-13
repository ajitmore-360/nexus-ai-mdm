use std::time::Duration;

use anyhow::{Context, Result};
use sqlx::{
    postgres::{
        PgPoolOptions,
        PgConnectOptions,
    },
    Pool,
    Postgres,
    pool::PoolConnection,
};
use tracing::info;

pub type DbPool = Pool<Postgres>;

///
/// Production Database Pool Factory
///
pub struct DatabasePool;

impl DatabasePool {
    pub async fn create(
        database_url: &str,
        max_connections: u32,
        min_connections: u32,
    ) -> Result<DbPool> {

        let options: PgConnectOptions =
            database_url.parse()?;

        let pool = PgPoolOptions::new()
            .max_connections(max_connections)
            .min_connections(min_connections)
            .acquire_timeout(Duration::from_secs(10))
            .idle_timeout(Duration::from_secs(300))
            .max_lifetime(Duration::from_secs(1800))
            .test_before_acquire(true)
            .connect_with(options)
            .await
            .context(
                "failed to create postgres pool"
            )?;

        sqlx::query("SELECT 1")
            .execute(&pool)
            .await
            .context(
                "postgres connectivity check failed"
            )?;

        info!(
            "postgres pool initialized successfully"
        );

        Ok(pool)
    }

    pub async fn health_check(
        pool: &DbPool,
    ) -> bool {

        match sqlx::query("SELECT 1")
            .execute(pool)
            .await
        {
            Ok(_) => true,

            Err(error) => {
                tracing::error!(
                    error=?error,
                    "database health check failed"
                );

                false
            }
        }
    }

    pub async fn close(
        pool: DbPool,
    ) {
        info!("closing postgres pool");

        pool.close().await;
    }
}

pub async fn acquire_connection(
    pool: &DbPool,
) -> Result<PoolConnection<Postgres>> {

    let connection =
        pool.acquire().await
            .context(
                "failed to acquire db connection"
            )?;

    Ok(connection)
}