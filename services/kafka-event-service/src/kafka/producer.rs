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

//
// ========================================
// CREATE PRODUCER
// ========================================
//

pub fn create_producer(
    brokers: &str,
) -> Result<FutureProducer> {

    let producer =
        ClientConfig::new()

            //
            // Kafka brokers
            //
            .set(
                "bootstrap.servers",
                brokers,
            )

            //
            // Reliability
            //
            .set(
                "acks",
                "all",
            )

            //
            // Retry strategy
            //
            .set(
                "retries",
                "10",
            )

            //
            // Compression
            //
            .set(
                "compression.type",
                "gzip",
            )

            //
            // Timeout
            //
            .set(
                "message.timeout.ms",
                "5000",
            )

            //
            // Create producer
            //
            .create()?;

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