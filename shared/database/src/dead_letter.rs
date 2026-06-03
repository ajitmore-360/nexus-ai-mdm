use anyhow::Result;

use chrono::{
    DateTime,
    Utc,
};

use serde::{
    Deserialize,
    Serialize,
};

use serde_json::Value;

use sqlx::PgPool;

use uuid::Uuid;

#[derive(
    Debug,
    Clone,
    Serialize,
    Deserialize,
)]
pub struct DeadLetterEvent {

    pub dead_letter_id: Uuid,

    pub original_event_id: Option<Uuid>,

    pub tenant_id: Option<Uuid>,

    pub topic_name: Option<String>,

    pub payload: Value,

    pub error_message: String,

    pub retry_attempts: i32,

    pub failed_at: DateTime<Utc>,
}

pub struct DeadLetterRepository {
    pool: PgPool,
}

impl DeadLetterRepository {

    pub fn new(
        pool: PgPool,
    ) -> Self {
        Self { pool }
    }

    pub async fn save(
        &self,
        event: DeadLetterEvent,
    ) -> Result<()> {

        sqlx::query(
            r#"
            INSERT INTO
            event_store.dead_letter_events
            (
                dead_letter_id,
                original_event_id,
                tenant_id,
                topic_name,
                payload,
                error_message,
                retry_attempts,
                failed_at
            )
            VALUES
            (
                $1,$2,$3,$4,$5,$6,$7,$8
            )
            "#
        )
        .bind(event.dead_letter_id)
        .bind(event.original_event_id)
        .bind(event.tenant_id)
        .bind(event.topic_name)
        .bind(event.payload)
        .bind(event.error_message)
        .bind(event.retry_attempts)
        .bind(event.failed_at)
        .execute(&self.pool)
        .await?;

        Ok(())
    }
}