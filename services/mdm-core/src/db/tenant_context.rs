use anyhow::Result;
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

/// Call `app_context.set_tenant(tenant_id)` at the start of every transaction
/// that touches tenant-scoped tables.
///
/// This activates the Row-Level Security policies defined on those tables
/// (migration 002004 removes BYPASSRLS from nexus_app).  The setting is
/// transaction-local (`is_local=true` inside the DB function), so it is
/// automatically cleared on COMMIT or ROLLBACK — no connection-pool leakage.
///
/// # Usage
///
/// ```rust
/// let mut tx = pool.begin().await?;
/// set_tenant_ctx(&mut tx, tenant_id).await?;
/// // ... repository queries ...
/// tx.commit().await?;
/// ```
pub async fn set_tenant_ctx(
    tx:        &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
) -> Result<()> {
    sqlx::query("SELECT app_context.set_tenant($1)")
        .bind(tenant_id)
        .execute(&mut **tx)
        .await?;
    Ok(())
}
