use sqlx::{
    PgPool,
    pool::PoolConnection,
    Postgres,
};

pub async fn acquire_connection(
    pool: &PgPool,
) -> anyhow::Result<
    PoolConnection<Postgres>
> {

    let conn =
        pool.acquire().await?;

    Ok(conn)
}