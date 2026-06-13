use anyhow::Result;

use chrono::Utc;

use serde_json::Value;

use sqlx::{
    PgPool,
    Postgres,
    Row,
    Transaction,
};

use uuid::Uuid;

//
// ========================================
// EVENT REPOSITORY
// ========================================
//

#[derive(Clone)]
pub struct EventRepository {

    pub pool:
        PgPool,
}

impl EventRepository {

    //
    // ====================================
    // CONSTRUCTOR
    // ====================================
    //

    pub fn new(
        pool: PgPool,
    ) -> Self {

        Self {
            pool,
        }
    }

    //
    // ====================================
    // HEALTH CHECK
    // ====================================
    //

    pub async fn health_check(
        &self,
    ) -> Result<i64> {

        let result: (i64,) =
            sqlx::query_as(
                "SELECT 1"
            )
            .fetch_one(
                &self.pool
            )
            .await?;

        Ok(result.0)
    }

    //
    // ====================================
    // INSERT OUTBOX EVENT
    // ====================================
    //

    #[allow(clippy::too_many_arguments)]
    pub async fn insert_outbox_event(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        tenant_id: Uuid,
        aggregate_type: &str,
        aggregate_id: Uuid,
        event_type: &str,
        topic_name: &str,
        payload: Value,
    ) -> Result<Uuid> {

        let event_id =
            Uuid::new_v4();

        sqlx::query(
            r#"
            INSERT INTO event_store.outbox_events (
                event_id,
                tenant_id,
                aggregate_type,
                aggregate_id,
                event_type,
                topic_name,
                event_payload,
                published,
                retry_count,
                created_at
            )
            VALUES (
                $1,$2,$3,$4,$5,$6,$7,false,0,$8
            )
            "#
        )
        .bind(event_id)
        .bind(tenant_id)
        .bind(aggregate_type)
        .bind(aggregate_id)
        .bind(event_type)
        .bind(topic_name)
        .bind(payload)
        .bind(Utc::now())
        .execute(&mut **tx)
        .await?;

        Ok(event_id)
    }

    //
    // ====================================
    // MARK EVENT PUBLISHED
    // ====================================
    //

    pub async fn mark_event_published(
        &self,
        event_id: Uuid,
    ) -> Result<u64> {

        let result =
            sqlx::query(
                r#"
                UPDATE event_store.outbox_events
                SET
                    published = true,
                    published_at = $1,
                    updated_at = $2
                WHERE event_id = $3
                "#
            )
            .bind(Utc::now())
            .bind(Utc::now())
            .bind(event_id)
            .execute(&self.pool)
            .await?;

        Ok(
            result.rows_affected()
        )
    }

    //
    // ====================================
    // INCREMENT RETRY COUNT
    // ====================================
    //

    pub async fn increment_retry_count(
        &self,
        event_id: Uuid,
        error_message: Option<String>,
    ) -> Result<u64> {

        let result =
            sqlx::query(
                r#"
                UPDATE event_store.outbox_events
                SET
                    retry_count = retry_count + 1,
                    last_error = $1,
                    updated_at = $2
                WHERE event_id = $3
                "#
            )
            .bind(error_message)
            .bind(Utc::now())
            .bind(event_id)
            .execute(&self.pool)
            .await?;

        Ok(
            result.rows_affected()
        )
    }

    //
    // ====================================
    // FETCH UNPUBLISHED EVENTS
    // ====================================
    //

    pub async fn fetch_unpublished_events(
        &self,
        batch_size: i64,
    ) -> Result<Vec<OutboxEventRecord>> {

        let rows =
            sqlx::query(
                r#"
                SELECT
                    event_id,
                    tenant_id,
                    aggregate_type,
                    aggregate_id,
                    event_type,
                    topic_name,
                    event_payload,
                    retry_count,
                    created_at
                FROM event_store.outbox_events
                WHERE published = false
                ORDER BY created_at ASC
                LIMIT $1
                "#
            )
            .bind(batch_size)
            .fetch_all(&self.pool)
            .await?;

        let events =
            rows
                .into_iter()
                .map(|row| {

                    OutboxEventRecord {

                        event_id:
                            row.get("event_id"),

                        tenant_id:
                            row.get("tenant_id"),

                        aggregate_type:
                            row.get("aggregate_type"),

                        aggregate_id:
                            row.get("aggregate_id"),

                        event_type:
                            row.get("event_type"),

                        topic_name:
                            row.get("topic_name"),

                        event_payload:
                            row.get("event_payload"),

                        retry_count:
                            row.get("retry_count"),

                        created_at:
                            row.get("created_at"),
                    }
                })
                .collect();

        Ok(events)
    }

    //
    // ====================================
    // FETCH EVENT BY ID
    // ====================================
    //

    pub async fn fetch_event_by_id(
        &self,
        event_id: Uuid,
    ) -> Result<Option<OutboxEventRecord>> {

        let row =
            sqlx::query(
                r#"
                SELECT
                    event_id,
                    tenant_id,
                    aggregate_type,
                    aggregate_id,
                    event_type,
                    topic_name,
                    event_payload,
                    retry_count,
                    created_at
                FROM event_store.outbox_events
                WHERE event_id = $1
                "#
            )
            .bind(event_id)
            .fetch_optional(&self.pool)
            .await?;

        let Some(row) = row else {
            return Ok(None);
        };

        Ok(
            Some(
                OutboxEventRecord {

                    event_id:
                        row.get("event_id"),

                    tenant_id:
                        row.get("tenant_id"),

                    aggregate_type:
                        row.get("aggregate_type"),

                    aggregate_id:
                        row.get("aggregate_id"),

                    event_type:
                        row.get("event_type"),

                    topic_name:
                        row.get("topic_name"),

                    event_payload:
                        row.get("event_payload"),

                    retry_count:
                        row.get("retry_count"),

                    created_at:
                        row.get("created_at"),
                }
            )
        )
    }

    //
    // ====================================
    // COUNT PENDING EVENTS
    // ====================================
    //

    pub async fn count_pending_events(
        &self,
    ) -> Result<i64> {

        let row =
            sqlx::query(
                r#"
                SELECT COUNT(*)
                FROM event_store.outbox_events
                WHERE published = false
                "#
            )
            .fetch_one(&self.pool)
            .await?;

        Ok(
            row.get::<i64, _>(0)
        )
    }
}

//
// ========================================
// OUTBOX EVENT RECORD
// ========================================
//

#[derive(Debug, Clone)]
pub struct OutboxEventRecord {

    pub event_id:
        Uuid,

    pub tenant_id:
        Uuid,

    pub aggregate_type:
        String,

    pub aggregate_id:
        Uuid,

    pub event_type:
        String,

    pub topic_name:
        String,

    pub event_payload:
        Value,

    pub retry_count:
        i32,

    pub created_at:
        chrono::DateTime<Utc>,
}