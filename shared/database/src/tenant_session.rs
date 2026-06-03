use anyhow::Result;

use sqlx::{
    Postgres,
    Transaction,
};

use uuid::Uuid;

pub async fn initialize_tenant_session(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    request_id: Uuid,
    correlation_id: Uuid,
) -> Result<()> {

    sqlx::query(
        r#"
        SET LOCAL row_security = on
        "#
    )
    .execute(&mut **tx)
    .await?;

    sqlx::query(
        r#"
        SELECT set_config(
            'app.current_tenant',
            $1,
            true
        )
        "#
    )
    .bind(
        tenant_id.to_string()
    )
    .execute(&mut **tx)
    .await?;

    sqlx::query(
        r#"
        SELECT set_config(
            'app.request_id',
            $1,
            true
        )
        "#
    )
    .bind(
        request_id.to_string()
    )
    .execute(&mut **tx)
    .await?;

    sqlx::query(
        r#"
        SELECT set_config(
            'app.correlation_id',
            $1,
            true
        )
        "#
    )
    .bind(
        correlation_id.to_string()
    )
    .execute(&mut **tx)
    .await?;

    Ok(())
}