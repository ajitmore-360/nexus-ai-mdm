use std::sync::Arc;

use anyhow::Result;
use rdkafka::{
    consumer::{CommitMode, Consumer, StreamConsumer},
    ClientConfig, Message,
};
use tracing::{error, info, warn};
use uuid::Uuid;

use crate::enricher::EnrichmentOrchestrator;
use crate::providers::EnrichmentRequest;

const ENTITY_EVENTS_TOPIC: &str = "mdm.entity.events";

/// Kafka consumer that triggers enrichment when EntityCreated/EntityUpdated
/// events arrive on the entity events topic.
pub struct EnrichmentConsumer {
    consumer:    StreamConsumer,
    orchestrator: Arc<EnrichmentOrchestrator>,
}

impl EnrichmentConsumer {
    pub fn new(
        brokers:      &str,
        group_id:     &str,
        orchestrator: Arc<EnrichmentOrchestrator>,
    ) -> Result<Self> {
        let consumer: StreamConsumer = ClientConfig::new()
            .set("bootstrap.servers",        brokers)
            .set("group.id",                 group_id)
            .set("enable.auto.commit",       "false")
            .set("auto.offset.reset",        "latest")
            .set("session.timeout.ms",       "30000")
            .set("max.poll.interval.ms",     "300000")
            .create()?;

        consumer.subscribe(&[ENTITY_EVENTS_TOPIC])?;
        info!(topic=ENTITY_EVENTS_TOPIC, group=group_id, "enrichment Kafka consumer started");

        Ok(Self { consumer, orchestrator })
    }

    /// Run the consumer loop indefinitely.
    pub async fn run(self) -> Result<()> {
        use futures::StreamExt;
        let mut stream = self.consumer.stream();

        while let Some(msg) = stream.next().await {
            match msg {
                Err(e) => {
                    warn!(error=%e, "Kafka consumer error");
                }
                Ok(msg) => {
                    let payload = match msg.payload_view::<str>() {
                        Some(Ok(s))  => s.to_string(),
                        Some(Err(e)) => { warn!(error=%e, "invalid UTF-8 in message"); continue; }
                        None         => { continue; }
                    };

                    if let Err(e) = self.process_event(&payload).await {
                        error!(error=%e, "enrichment event processing failed");
                    }

                    // At-least-once delivery: commit after processing
                    let _ = self.consumer.commit_message(&msg, CommitMode::Async);
                }
            }
        }
        Ok(())
    }

    async fn process_event(&self, payload: &str) -> Result<()> {
        let event: serde_json::Value = serde_json::from_str(payload)?;

        // Only process EntityCreated and EntityUpdated events
        let event_type = event.get("event_type")
            .and_then(|v| v.as_str())
            .unwrap_or("");

        if !matches!(event_type, "EntityCreated" | "EntityUpdated") {
            return Ok(());
        }

        // Extract entity data from the event payload
        let entity = match event.get("payload").or_else(|| event.get("data")) {
            Some(e) => e,
            None    => return Ok(()),
        };

        let entity_id = entity.get("entity_id")
            .and_then(|v| v.as_str())
            .and_then(|s| Uuid::parse_str(s).ok());

        let tenant_id = entity.get("tenant_id")
            .and_then(|v| v.as_str())
            .and_then(|s| Uuid::parse_str(s).ok());

        let (entity_id, tenant_id) = match (entity_id, tenant_id) {
            (Some(eid), Some(tid)) => (eid, tid),
            _ => {
                warn!("entity event missing entity_id or tenant_id — skipping enrichment");
                return Ok(());
            }
        };

        let entity_type = entity.get("entity_type")
            .and_then(|v| v.as_str())
            .unwrap_or("Unknown")
            .to_string();

        let attributes = entity.get("attributes")
            .cloned()
            .unwrap_or(serde_json::Value::Object(Default::default()));

        let req = EnrichmentRequest { entity_id, tenant_id, entity_type, attributes };

        // Enrich asynchronously — failures are logged but don't fail the consumer
        if let Err(e) = self.orchestrator.enrich(&req).await {
            warn!(entity_id=%entity_id, error=%e, "enrichment failed for entity");
        }

        Ok(())
    }
}
