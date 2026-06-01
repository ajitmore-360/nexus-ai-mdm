use anyhow::Result;

use sqlx::{
    PgPool,
    Postgres,
    Transaction,
};

use uuid::Uuid;

//
// ========================================
// TENANT TRANSACTION
// ========================================
//

pub async fn begin_tenant_transaction(
    pool: &PgPool,
    tenant_id: Uuid,
) -> Result<Transaction<'_, Postgres>> {

    let mut tx =
        pool.begin().await?;

    //
    // ========================================
    // SET RLS TENANT
    // ========================================
    //

    sqlx::query(
        r#"
        SET LOCAL app.current_tenant = $1
        "#
    )
    .bind(
        tenant_id.to_string()
    )
    .execute(
        &mut *tx
    )
    .await?;

    Ok(tx)
}