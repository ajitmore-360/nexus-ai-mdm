use anyhow::Result;
use rdkafka::{
    consumer::StreamConsumer,
    ClientConfig,
};

use crate::kafka::producer::apply_security;

/// Create a Kafka consumer for DLQ inspection or replay verification.
///
/// Auto-commit is disabled so messages are only marked as consumed after
/// successful processing. Callers must call `consumer.commit_message()` or
/// `consumer.store_offset()` explicitly.
///
/// SASL/TLS settings are picked up from the same environment variables as the
/// producer — see `kafka::producer::apply_security`.
pub fn create_consumer(brokers: &str, group_id: &str) -> Result<StreamConsumer> {
    let mut cfg = ClientConfig::new();
    cfg.set("bootstrap.servers", brokers)
        .set("group.id", group_id)
        .set("enable.auto.commit", "false")
        .set("auto.offset.reset", "earliest")
        .set("session.timeout.ms", "30000")
        .set("max.poll.interval.ms", "300000");

    apply_security(&mut cfg);

    let consumer: StreamConsumer = cfg.create()?;
    Ok(consumer)
}
