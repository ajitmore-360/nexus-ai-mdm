use prometheus::{
    HistogramOpts, HistogramVec,
    IntCounterVec, Opts, Registry,
};
use std::sync::OnceLock;

static REGISTRY: OnceLock<MetricsRegistry> = OnceLock::new();

/// Central Prometheus metric registry for Nexus AI MDM services.
///
/// All services share the same metric NAMES — Prometheus differentiates
/// instances via the `service` label.  This means a single Grafana dashboard
/// works for every service.
pub struct MetricsRegistry {
    pub registry: Registry,

    // ── HTTP ────────────────────────────────────────────────────────────────
    /// Total HTTP requests by service, method, path, and status.
    pub http_requests_total: IntCounterVec,
    /// HTTP request duration histogram (seconds) by service, method, path.
    pub http_request_duration_seconds: HistogramVec,

    // ── Business ────────────────────────────────────────────────────────────
    /// Entity CRUD operations (service, operation, entity_type, status).
    pub entity_operations_total: IntCounterVec,
    /// Match pipeline executions (service, result: matched/review/rejected).
    pub match_executions_total: IntCounterVec,
    /// AI service calls (model, operation, status).
    pub ai_requests_total: IntCounterVec,
    /// Kafka outbox events published (topic, status: published/failed).
    pub kafka_events_published_total: IntCounterVec,

    // ── Latency histograms ──────────────────────────────────────────────────
    /// Entity creation latency in milliseconds.
    pub entity_create_duration_ms: HistogramVec,
    /// Match pipeline latency in milliseconds.
    pub match_duration_ms: HistogramVec,
    /// LLM inference latency in milliseconds.
    pub llm_inference_duration_ms: HistogramVec,
}

impl MetricsRegistry {
    fn new(service_name: &str) -> anyhow::Result<Self> {
        let registry = Registry::new_custom(
            Some("nexus".to_string()),
            Some([("service".to_string(), service_name.to_string())].into()),
        )?;

        let http_requests_total = IntCounterVec::new(
            Opts::new("http_requests_total", "Total HTTP requests"),
            &["method", "path", "status"],
        )?;

        let http_request_duration_seconds = HistogramVec::new(
            HistogramOpts::new(
                "http_request_duration_seconds",
                "HTTP request duration in seconds",
            )
            .buckets(vec![0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0]),
            &["method", "path"],
        )?;

        let entity_operations_total = IntCounterVec::new(
            Opts::new("entity_operations_total", "Entity CRUD operations"),
            &["operation", "entity_type", "status"],
        )?;

        let match_executions_total = IntCounterVec::new(
            Opts::new("match_executions_total", "Match pipeline executions"),
            &["result"],
        )?;

        let ai_requests_total = IntCounterVec::new(
            Opts::new("ai_requests_total", "AI service requests"),
            &["model", "operation", "status"],
        )?;

        let kafka_events_published_total = IntCounterVec::new(
            Opts::new("kafka_events_published_total", "Kafka outbox events published"),
            &["topic", "status"],
        )?;

        let entity_create_duration_ms = HistogramVec::new(
            HistogramOpts::new(
                "entity_create_duration_ms",
                "Entity creation duration in milliseconds",
            )
            .buckets(vec![5.0, 10.0, 25.0, 50.0, 100.0, 250.0, 500.0, 1000.0]),
            &["entity_type"],
        )?;

        let match_duration_ms = HistogramVec::new(
            HistogramOpts::new("match_duration_ms", "Match pipeline duration in milliseconds")
                .buckets(vec![10.0, 25.0, 50.0, 100.0, 250.0, 500.0, 1000.0, 2500.0]),
            &["blocking_strategy"],
        )?;

        let llm_inference_duration_ms = HistogramVec::new(
            HistogramOpts::new("llm_inference_duration_ms", "LLM inference duration in ms")
                .buckets(vec![100.0, 250.0, 500.0, 1000.0, 2500.0, 5000.0, 10000.0]),
            &["model", "operation"],
        )?;

        // Register all metrics
        registry.register(Box::new(http_requests_total.clone()))?;
        registry.register(Box::new(http_request_duration_seconds.clone()))?;
        registry.register(Box::new(entity_operations_total.clone()))?;
        registry.register(Box::new(match_executions_total.clone()))?;
        registry.register(Box::new(ai_requests_total.clone()))?;
        registry.register(Box::new(kafka_events_published_total.clone()))?;
        registry.register(Box::new(entity_create_duration_ms.clone()))?;
        registry.register(Box::new(match_duration_ms.clone()))?;
        registry.register(Box::new(llm_inference_duration_ms.clone()))?;

        Ok(Self {
            registry,
            http_requests_total,
            http_request_duration_seconds,
            entity_operations_total,
            match_executions_total,
            ai_requests_total,
            kafka_events_published_total,
            entity_create_duration_ms,
            match_duration_ms,
            llm_inference_duration_ms,
        })
    }
}

/// Initialise the global metrics registry for a named service.
/// Must be called once at startup before any metrics are recorded.
pub fn init_metrics(service_name: &str) -> &'static MetricsRegistry {
    REGISTRY.get_or_init(|| {
        MetricsRegistry::new(service_name).expect("failed to initialise metrics registry")
    })
}

/// Get the global metrics registry (panics if `init_metrics` was not called).
pub fn metrics() -> &'static MetricsRegistry {
    REGISTRY.get().expect("metrics registry not initialised — call init_metrics() at startup")
}

/// Convenience: record a completed HTTP request.
pub fn record_http_request(method: &str, path: &str, status: u16, duration_secs: f64) {
    if let Some(reg) = REGISTRY.get() {
        reg.http_requests_total
            .with_label_values(&[method, path, &status.to_string()])
            .inc();
        reg.http_request_duration_seconds
            .with_label_values(&[method, path])
            .observe(duration_secs);
    }
}

// ── Re-exports for convenience ───────────────────────────────────────────────

pub fn http_requests_total() -> Option<&'static IntCounterVec> {
    REGISTRY.get().map(|r| &r.http_requests_total)
}
pub fn http_request_duration_seconds() -> Option<&'static HistogramVec> {
    REGISTRY.get().map(|r| &r.http_request_duration_seconds)
}
pub fn entity_operations_total() -> Option<&'static IntCounterVec> {
    REGISTRY.get().map(|r| &r.entity_operations_total)
}
pub fn match_executions_total() -> Option<&'static IntCounterVec> {
    REGISTRY.get().map(|r| &r.match_executions_total)
}
pub fn ai_requests_total() -> Option<&'static IntCounterVec> {
    REGISTRY.get().map(|r| &r.ai_requests_total)
}
pub fn kafka_events_published_total() -> Option<&'static IntCounterVec> {
    REGISTRY.get().map(|r| &r.kafka_events_published_total)
}

/// Render all registered metrics as a Prometheus text exposition.
pub fn render_metrics() -> anyhow::Result<String> {
    if let Some(reg) = REGISTRY.get() {
        use prometheus::Encoder;
        let encoder = prometheus::TextEncoder::new();
        let mf = reg.registry.gather();
        let mut buf = Vec::new();
        encoder.encode(&mf, &mut buf)?;
        Ok(String::from_utf8(buf)?)
    } else {
        Ok("# metrics not initialised\n".to_string())
    }
}
