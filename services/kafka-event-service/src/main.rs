use dotenvy::dotenv;

use sqlx::{
    postgres::PgPoolOptions,
    PgPool,
};

use std::{
    env,
    time::Duration,
};

use tracing::{
    error,
    info,
};

use tokio::signal;

use rdkafka::producer::FutureProducer;

mod kafka;
mod models;
mod outbox;
mod workers;

use kafka::producer::create_producer;

use workers::outbox_worker::start_outbox_worker;

//
// ========================================
// MAIN
// ========================================
//

#[tokio::main]
async fn main() -> anyhow::Result<()> {

    //
    // ====================================
    // LOAD ENVIRONMENT
    // ====================================
    //

    dotenv().ok();

    //
    // ====================================
    // INIT LOGGING
    // ====================================
    //

    tracing_subscriber::fmt::init();

    info!(
        "Starting Kafka Event Service..."
    );

    //
    // ====================================
    // DATABASE URL
    // ====================================
    //

    let database_url =
        env::var("DATABASE_URL")
            .expect(
                "DATABASE_URL missing"
            );

    //
    // ====================================
    // KAFKA BROKERS
    // ====================================
    //

    let kafka_brokers =
        env::var("KAFKA_BROKERS")
            .unwrap_or_else(|_| {

                "localhost:9092"
                    .to_string()
            });

    //
    // ====================================
    // CONNECT POSTGRES
    // ====================================
    //

    let pool: PgPool =
        PgPoolOptions::new()

            //
            // Pool sizing
            //
            .max_connections(20)
            .min_connections(5)

            //
            // Timeouts
            //
            .acquire_timeout(
                Duration::from_secs(10)
            )

            //
            // Connect
            //
            .connect(&database_url)
            .await?;

    info!(
        "Connected to PostgreSQL"
    );

    //
    // ====================================
    // CREATE KAFKA PRODUCER
    // ====================================
    //

    let producer: FutureProducer =
        create_producer(
            &kafka_brokers
        )?;

    info!(
        "Kafka producer initialized"
    );

    //
    // ====================================
    // START OUTBOX WORKER
    // ====================================
    //

    let worker_pool =
        pool.clone();

    let worker_producer =
        producer.clone();

    tokio::spawn(async move {

        if let Err(error) =
            start_outbox_worker(
                worker_pool,
                worker_producer,
            )
            .await
        {
            error!(
                "Outbox worker crashed: {:?}",
                error
            );
        }
    });

    info!(
        "Outbox worker started"
    );

    info!(
        "Kafka Event Service is running"
    );

    //
    // ====================================
    // GRACEFUL SHUTDOWN
    // ====================================
    //

    signal::ctrl_c().await?;

    info!(
        "Shutdown signal received"
    );

    info!(
        "Kafka Event Service stopped"
    );

    Ok(())
}