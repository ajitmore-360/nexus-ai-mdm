use uuid::Uuid;

use tracing::{
    Span,
    info_span,
};

#[derive(Debug, Clone)]
pub struct TraceContext {
    pub trace_id: String,
    pub correlation_id: Uuid,
    pub request_id: Uuid,
}

impl TraceContext {
    pub fn new() -> Self {
        Self {
            trace_id: Uuid::new_v4().to_string(),
            correlation_id: Uuid::new_v4(),
            request_id: Uuid::new_v4(),
        }
    }

    pub fn child(&self) -> Self {
        Self {
            trace_id: self.trace_id.clone(),
            correlation_id: self.correlation_id,
            request_id: Uuid::new_v4(),
        }
    }

    pub fn span(
        &self,
        operation: &str,
    ) -> Span {
        info_span!(
            "operation",
            operation = operation,
            trace_id = %self.trace_id,
            correlation_id = %self.correlation_id,
            request_id = %self.request_id
        )
    }
}

pub fn extract_trace_id(
    value: Option<&str>,
) -> String {
    value
        .map(|v| v.to_string())
        .unwrap_or_else(|| {
            Uuid::new_v4().to_string()
        })
}