use sqlx::{
    Executor,
    Postgres,
};

pub async fn enable_rls<'a, E>(
    executor: E,
) -> anyhow::Result<()>
where
    E: Executor<'a, Database = Postgres>,
{
    sqlx::query(
        r#"
        SET row_security = on
        "#
    )
    .execute(executor)
    .await?;

    Ok(())
}