use std::sync::Arc;
use std::time::Instant;

use chrono::{DateTime, Utc};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::pool::DbPool;
use crate::unit_of_work::UnitOfWork;

/// Context propagated across the entire request lifecycle.
///
/// This is the backbone for:
///
/// - Tenant Isolation
/// - Distributed Tracing
/// - Audit Logging
/// - Outbox Publishing
/// - Unit Of Work
///
#[derive(Debug, Clone)]
pub struct RequestContext {
    pub request_id: Uuid,

    pub correlation_id: Uuid,

    pub trace_id: String,

    pub tenant_id: Uuid,

    pub user_id: Option<Uuid>,

    pub started_at: DateTime<Utc>,

    pub created_instant: Arc<Instant>,
}

impl RequestContext {
    pub fn new(
        tenant_id: Uuid,
        user_id: Option<Uuid>,
        trace_id: String,
    ) -> Self {
        Self {
            request_id: Uuid::new_v4(),

            correlation_id: Uuid::new_v4(),

            trace_id,

            tenant_id,

            user_id,

            started_at: Utc::now(),

            created_instant: Arc::new(Instant::now()),
        }
    }

    pub fn elapsed_ms(&self) -> u128 {
        self.created_instant.elapsed().as_millis()
    }
}

//
// ======================================================
// REQUEST TRANSACTION CONTEXT
// ======================================================
//

pub struct TransactionContext<'a> {
    pub ctx: RequestContext,

    pub tx: Transaction<'a, Postgres>,
}

impl<'a> TransactionContext<'a> {
    pub fn new(
        ctx: RequestContext,
        tx: Transaction<'a, Postgres>,
    ) -> Self {
        Self { ctx, tx }
    }

    pub async fn commit(self) -> Result<(), sqlx::Error> {
        self.tx.commit().await
    }

    pub async fn rollback(self) -> Result<(), sqlx::Error> {
        self.tx.rollback().await
    }
}

//
// ======================================================
// DB CONTEXT FACTORY
// ======================================================
//

pub struct RequestContextFactory {
    pool: DbPool,
}

impl RequestContextFactory {
    pub fn new(pool: DbPool) -> Self {
        Self { pool }
    }

    pub async fn begin(
        &self,
        tenant_id: Uuid,
        user_id: Option<Uuid>,
        trace_id: String,
    ) -> Result<TransactionContext<'_>, sqlx::Error> {
        let ctx = RequestContext::new(
            tenant_id,
            user_id,
            trace_id,
        );

        let mut tx = self.pool.begin().await?;

        //
        // Set RLS Tenant Context
        //
        sqlx::query(
            r#"
            SELECT set_config(
                'app.current_tenant',
                $1,
                true
            )
            "#,
        )
        .bind(tenant_id.to_string())
        .execute(&mut *tx)
        .await?;

        //
        // Request Id
        //
        sqlx::query(
            r#"
            SELECT set_config(
                'app.request_id',
                $1,
                true
            )
            "#,
        )
        .bind(ctx.request_id.to_string())
        .execute(&mut *tx)
        .await?;

        //
        // Correlation Id
        //
        sqlx::query(
            r#"
            SELECT set_config(
                'app.correlation_id',
                $1,
                true
            )
            "#,
        )
        .bind(ctx.correlation_id.to_string())
        .execute(&mut *tx)
        .await?;

        Ok(TransactionContext::new(ctx, tx))
    }

    /// Begin a transaction with full RLS context AND return a `UnitOfWork`
    /// that accumulates outbox events and flushes them atomically on commit.
    ///
    /// This is the **primary entry point** for all write operations in the
    /// service layer.  It sets every PostgreSQL session variable required by
    /// RLS policies before any query touches the data.
    pub async fn begin_uow(
        &self,
        tenant_id: Uuid,
        user_id: Option<Uuid>,
        trace_id: String,
    ) -> Result<UnitOfWork<'_>, sqlx::Error> {
        let ctx = RequestContext::new(tenant_id, user_id, trace_id);
        let mut tx = self.pool.begin().await?;

        // Tenant isolation (read by RLS policies)
        sqlx::query("SELECT set_config('app.current_tenant', $1, true)")
            .bind(tenant_id.to_string())
            .execute(&mut *tx)
            .await?;

        // Distributed tracing
        sqlx::query("SELECT set_config('app.request_id', $1, true)")
            .bind(ctx.request_id.to_string())
            .execute(&mut *tx)
            .await?;

        sqlx::query("SELECT set_config('app.correlation_id', $1, true)")
            .bind(ctx.correlation_id.to_string())
            .execute(&mut *tx)
            .await?;

        sqlx::query("SELECT set_config('app.trace_id', $1, true)")
            .bind(&ctx.trace_id)
            .execute(&mut *tx)
            .await?;

        // Audit: current user (nullable)
        if let Some(uid) = user_id {
            sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
                .bind(uid.to_string())
                .execute(&mut *tx)
                .await?;
        }

        Ok(UnitOfWork::new(ctx, tx))
    }
}