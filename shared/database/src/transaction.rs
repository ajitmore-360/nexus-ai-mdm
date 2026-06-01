use sqlx::{
    PgPool,
    Postgres,
    Transaction,
};

pub async fn begin_tx(
    pool: &PgPool,
) -> anyhow::Result<
    Transaction<'_, Postgres>
> {

    let tx =
        pool.begin().await?;

    Ok(tx)
}