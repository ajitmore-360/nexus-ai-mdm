use std::time::Duration;

use anyhow::Result;

use sqlx::PgPool;

use tokio::time::sleep;

use rdkafka::producer::FutureProducer;

use crate::outbox::poller::poll_outbox;

//
// ========================================
// START OUTBOX WORKER
// ========================================
//

pub async fn start_outbox_worker(
    pool: PgPool,
    producer: FutureProducer,
) -> Result<()> {

    println!(
        "Starting outbox worker..."
    );

    //
    // ====================================
    // CONTINUOUS POLLING LOOP
    // ====================================
    //

    loop {

        match poll_outbox(
            &pool,
            &producer,
        )
        .await
        {
            Ok(_) => {}

            Err(error) => {

                //
                // ====================================
                // NEVER CRASH WORKER
                // ====================================
                //

                eprintln!(
                    "Outbox polling failed: {:?}",
                    error
                );
            }
        }

        //
        // ====================================
        // POLLING INTERVAL
        // ====================================
        //

        sleep(
            Duration::from_secs(5)
        )
        .await;
    }
}