use anyhow::Result;

use sqlx::{
    migrate::Migrator,
    PgPool,
};

static MIGRATOR: Migrator =
    sqlx::migrate!("./migrations");

pub async fn run_migrations(
    pool: &PgPool,
) -> Result<()> {

    MIGRATOR
        .run(pool)
        .await?;

    Ok(())
}