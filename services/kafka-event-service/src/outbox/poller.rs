use anyhow::Result;

use sqlx::PgPool;

use rdkafka::producer::FutureProducer;

use crate::outbox::{
    publisher::publish_outbox_event,
    repository::fetch_unpublished_events,
};

//
// ========================================
// POLL OUTBOX
// ========================================
//

pub async fn poll_outbox(
    pool: &PgPool,
    producer: &FutureProducer,
) -> Result<()> {

    //
    // ====================================
    // FETCH EVENTS
    // ====================================
    //

    let events =
        fetch_unpublished_events(pool)
            .await?;

    if events.is_empty() {

        return Ok(());
    }

    println!(
        "Fetched {} unpublished outbox events",
        events.len()
    );

    //
    // ====================================
    // PUBLISH EVENTS
    // ====================================
    //

    for event in events {

        let event_id =
            event.event_id;

        let topic =
            event.topic_name.clone();

        match publish_outbox_event(
            pool,
            producer,
            event,
        )
        .await
        {
            Ok(_) => {

                println!(
                    "Successfully published event_id={} topic={}",
                    event_id,
                    topic
                );
            }

            Err(error) => {

                //
                // ====================================
                // DO NOT FAIL ENTIRE BATCH
                // ====================================
                //

                eprintln!(
                    "Failed to publish outbox event. event_id={} topic={} error={:?}",
                    event_id,
                    topic,
                    error
                );
            }
        }
    }

    Ok(())
}