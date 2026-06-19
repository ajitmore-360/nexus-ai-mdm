/// Initialise structured tracing for a service.
///
/// Reads `RUST_LOG` for log-level filtering.
/// Reads `JSON_LOGS=true` to emit JSON-structured logs (production).
/// Reads `OTEL_EXPORTER_OTLP_ENDPOINT` to forward spans to Tempo/Jaeger via OTLP/gRPC.
///
/// Call `shutdown_tracing()` during graceful shutdown to flush pending spans.
pub fn init_tracing(service_name: &str) {
    use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};

    let env_filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| {
            EnvFilter::new(format!("{}=info,tower_http=info", service_name))
        });

    let json_logs = std::env::var("JSON_LOGS")
        .map(|v| v == "true" || v == "1")
        .unwrap_or(false);

    let otlp_endpoint = std::env::var("OTEL_EXPORTER_OTLP_ENDPOINT").ok();

    match (json_logs, otlp_endpoint) {
        (true, Some(endpoint)) => {
            tracing_subscriber::registry()
                .with(env_filter)
                .with(
                    tracing_subscriber::fmt::layer()
                        .json()
                        .with_target(true)
                        .with_thread_ids(true),
                )
                .with(tracing_opentelemetry::layer().with_tracer(
                    init_otlp_tracer(service_name, &endpoint),
                ))
                .init();
        }
        (true, None) => {
            tracing_subscriber::registry()
                .with(env_filter)
                .with(
                    tracing_subscriber::fmt::layer()
                        .json()
                        .with_target(true)
                        .with_thread_ids(true),
                )
                .init();
        }
        (false, Some(endpoint)) => {
            tracing_subscriber::registry()
                .with(env_filter)
                .with(
                    tracing_subscriber::fmt::layer()
                        .with_target(true)
                        .with_thread_ids(false)
                        .pretty(),
                )
                .with(tracing_opentelemetry::layer().with_tracer(
                    init_otlp_tracer(service_name, &endpoint),
                ))
                .init();
        }
        (false, None) => {
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
    }

    tracing::info!(service = service_name, "tracing initialised");
}

/// Flush and shut down the global OpenTelemetry tracer provider.
/// Call this from your graceful shutdown handler to ensure all spans are exported
/// before the process exits. No-op if OTLP was not configured.
pub fn shutdown_tracing() {
    opentelemetry::global::shutdown_tracer_provider();
}

fn init_otlp_tracer(
    service_name: &str,
    endpoint: &str,
) -> opentelemetry_sdk::trace::Tracer {
    use opentelemetry::{global, KeyValue};
    use opentelemetry_otlp::WithExportConfig;
    use opentelemetry_sdk::{
        propagation::TraceContextPropagator,
        runtime::Tokio,
        trace::{self, RandomIdGenerator, Sampler},
        Resource,
    };

    // Propagate W3C Trace Context headers across service boundaries.
    global::set_text_map_propagator(TraceContextPropagator::new());

    let resource = Resource::new(vec![
        KeyValue::new("service.name", service_name.to_string()),
        KeyValue::new("service.version", env!("CARGO_PKG_VERSION")),
    ]);

    opentelemetry_otlp::new_pipeline()
        .tracing()
        .with_exporter(
            opentelemetry_otlp::new_exporter()
                .tonic()
                .with_endpoint(endpoint),
        )
        .with_trace_config(
            trace::Config::default()
                .with_sampler(Sampler::AlwaysOn)
                .with_id_generator(RandomIdGenerator::default())
                .with_resource(resource),
        )
        .install_batch(Tokio)
        .expect("failed to initialize OTLP tracer — check OTEL_EXPORTER_OTLP_ENDPOINT")
}
