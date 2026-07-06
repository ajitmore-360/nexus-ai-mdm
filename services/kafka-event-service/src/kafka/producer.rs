use std::time::Duration;

use anyhow::{
    anyhow,
    Result,
};

use rdkafka::{
    producer::{
        FutureProducer,
        FutureRecord,
    },
    ClientConfig,
    Message,
};

/// Apply SASL/TLS settings from environment variables to a `ClientConfig`.
///
/// Recognised variables (all optional — absent → no security layer):
///
/// | Variable                  | Example value          |
/// |---------------------------|------------------------|
/// | `KAFKA_SECURITY_PROTOCOL` | `SASL_SSL`             |
/// | `KAFKA_SASL_MECHANISM`    | `SCRAM-SHA-512`        |
/// | `KAFKA_SASL_USERNAME`     | `nexus-producer`       |
/// | `KAFKA_SASL_PASSWORD`     | `s3cr3t`               |
/// | `KAFKA_SSL_CA_LOCATION`   | `/etc/ssl/ca-cert.pem` |
pub(crate) fn apply_security(cfg: &mut ClientConfig) {
    if let Ok(protocol) = std::env::var("KAFKA_SECURITY_PROTOCOL") {
        cfg.set("security.protocol", &protocol);
        tracing::debug!(protocol = %protocol, "Kafka security.protocol set");
    }
    if let Ok(mechanism) = std::env::var("KAFKA_SASL_MECHANISM") {
        cfg.set("sasl.mechanism", &mechanism);
    }
    if let (Ok(user), Ok(pass)) = (
        std::env::var("KAFKA_SASL_USERNAME"),
        std::env::var("KAFKA_SASL_PASSWORD"),
    ) {
        cfg.set("sasl.username", &user);
        cfg.set("sasl.password", &pass);
    }
    if let Ok(ca) = std::env::var("KAFKA_SSL_CA_LOCATION") {
        cfg.set("ssl.ca.location", &ca);
    }
}

//
// ========================================
// CREATE PRODUCER
// ========================================
//

pub fn create_producer(brokers: &str) -> Result<FutureProducer> {
    let mut cfg = ClientConfig::new();
    cfg.set("bootstrap.servers", brokers)
        .set("acks", "all")
        .set("retries", "10")
        .set("compression.type", "gzip")
        .set("message.timeout.ms", "5000");

    apply_security(&mut cfg);

    let producer = cfg.create()?;
    Ok(producer)
}

//
// ========================================
// PUBLISH EVENT
// ========================================
//

pub async fn publish_event(
    producer: &FutureProducer,
    topic: &str,
    key: &str,
    payload: &str,
) -> Result<()> {

    let delivery_result =
        producer
            .send(
                FutureRecord::to(topic)
                    .payload(payload)
                    .key(key),
                Duration::from_secs(5),
            )
            .await;

    //
    // HANDLE DELIVERY RESULT
    //
    // rdkafka version compatibility
    //

    match delivery_result {

        //
        // SUCCESS
        //

        Ok((partition, offset)) => {

            tracing::debug!(
                topic     = %topic,
                partition = partition,
                offset    = offset,
                "Kafka message delivered"
            );

            Ok(())
        }

        //
        // FAILURE
        //

        Err((err, owned_message)) => {

            Err(anyhow!(
                "Kafka publish failed. topic={}, key={}, error={}, payload={:?}",
                topic,
                key,
                err,
                owned_message.payload()
            ))
        }
    }
}