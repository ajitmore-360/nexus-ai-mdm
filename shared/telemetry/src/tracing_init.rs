/// Initialise structured tracing for a service.
///
/// Respects the `RUST_LOG` environment variable for log-level filtering.
/// In production, outputs JSON-structured logs for log aggregation systems.
/// In development (when `RUST_LOG` includes a service name), outputs
/// human-readable coloured output.
pub fn init_tracing(service_name: &str) {
    use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};

    let env_filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| {
            EnvFilter::new(format!("{}=info,tower_http=info", service_name))
        });

    // Check if we want JSON output (set JSON_LOGS=true in production)
    let json_logs = std::env::var("JSON_LOGS")
        .map(|v| v == "true" || v == "1")
        .unwrap_or(false);

    if json_logs {
        tracing_subscriber::registry()
            .with(env_filter)
            .with(
                tracing_subscriber::fmt::layer()
                    .json()
                    .with_target(true)
                    .with_thread_ids(true)
                    .with_current_span(true),
            )
            .init();
    } else {
        tracing_subscriber::registry()
            .with(env_filter)
            .with(
                tracing_subscriber::fmt::layer()
                    .with_target(true)
                    .with_thread_ids(false)
                    .pretty(),
            )
            .init();
    }

    tracing::info!(service = service_name, "tracing initialised");
}
