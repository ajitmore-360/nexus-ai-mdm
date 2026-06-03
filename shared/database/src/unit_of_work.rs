use anyhow::Result;
use serde_json::Value;
use sqlx::{
    Postgres,
    Transaction,
};
use uuid::Uuid;

use crate::request_context::{
    RequestContext,
};

///
/// Outbox Event
///
#[derive(Debug, Clone)]
pub struct PendingOutboxEvent {

    pub event_id: Uuid,

    pub tenant_id: Uuid,

    pub aggregate_type: String,

    pub aggregate_id: Uuid,

    pub event_type: String,

    pub payload: Value,

    pub metadata: Value,

    pub topic_name: String,
}

impl PendingOutboxEvent {

    pub fn new(
        tenant_id: Uuid,
        aggregate_type: String,
        aggregate_id: Uuid,
        event_type: String,
        payload: Value,
        metadata: Value,
        topic_name: String,
    ) -> Self {

        Self {
            event_id: Uuid::new_v4(),
            tenant_id,
            aggregate_type,
            aggregate_id,
            event_type,
            payload,
            metadata,
            topic_name,
        }
    }
}

//
// ======================================================
// UNIT OF WORK
// ======================================================
//

pub struct UnitOfWork<'a> {

    pub context: RequestContext,

    pub tx: Transaction<'a, Postgres>,

    pending_events:
        Vec<PendingOutboxEvent>,
}

impl<'a> UnitOfWork<'a> {

    pub fn new(
        context: RequestContext,
        tx: Transaction<'a, Postgres>,
    ) -> Self {

        Self {
            context,
            tx,
            pending_events: Vec::new(),
        }
    }

    //
    // Queue Outbox Event
    //
    pub fn add_event(
        &mut self,
        event: PendingOutboxEvent,
    ) {
        self.pending_events.push(event);
    }

    //
    // Persist Outbox Events
    //
    async fn persist_events(
        &mut self,
    ) -> Result<()> {

        for event in &self.pending_events {

            sqlx::query(
                r#"
                INSERT INTO
                event_store.outbox_events
                (
                    event_id,
                    tenant_id,
                    aggregate_type,
                    aggregate_id,
                    event_type,
                    event_payload,
                    event_metadata,
                    topic_name
                )
                VALUES
                (
                    $1,$2,$3,$4,$5,$6,$7,$8
                )
                "#,
            )
            .bind(event.event_id)
            .bind(event.tenant_id)
            .bind(&event.aggregate_type)
            .bind(event.aggregate_id)
            .bind(&event.event_type)
            .bind(&event.payload)
            .bind(&event.metadata)
            .bind(&event.topic_name)
            .execute(&mut *self.tx)
            .await?;
        }

        Ok(())
    }

    //
    // Commit
    //
    pub async fn commit(
        mut self,
    ) -> Result<()> {

        self.persist_events().await?;

        self.tx.commit().await?;

        Ok(())
    }

    //
    // Rollback
    //
    pub async fn rollback(
        self,
    ) -> Result<()> {

        self.tx.rollback().await?;

        Ok(())
    }
}