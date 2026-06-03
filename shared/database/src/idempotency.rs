use anyhow::Result;

use sqlx::{
    PgPool,
};

pub struct IdempotencyService {
    pool: PgPool,
}

impl IdempotencyService {
    pub fn new(
        pool: PgPool,
    ) -> Self {
        Self { pool }
    }

    pub async fn exists(
        &self,
        key: &str,
    ) -> Result<bool> {

        let exists: bool =
            sqlx::query_scalar(
                r#"
                SELECT EXISTS(
                    SELECT 1
                    FROM platform.idempotency_keys
                    WHERE idempotency_key = $1
                )
                "#
            )
            .bind(key)
            .fetch_one(&self.pool)
            .await?;

        Ok(exists)
    }

    pub async fn register(
        &self,
        key: &str,
    ) -> Result<()> {

        sqlx::query(
            r#"
            INSERT INTO
            platform.idempotency_keys
            (
                idempotency_key
            )
            VALUES
            (
                $1
            )
            ON CONFLICT DO NOTHING
            "#
        )
        .bind(key)
        .execute(&self.pool)
        .await?;

        Ok(())
    }
}