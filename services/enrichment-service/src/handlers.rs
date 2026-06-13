use std::sync::Arc;

use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde::Deserialize;
use serde_json::json;
use uuid::Uuid;

use crate::providers::EnrichmentRequest;
use crate::state::AppState;

/// POST /enrich/:entity_id?tenant_id=<uuid>&entity_type=<str>
///
/// On-demand enrichment for a single entity.
pub async fn enrich_entity(
    State(state):  State<AppState>,
    Path(entity_id): Path<Uuid>,
    Json(body):    Json<EnrichRequest>,
) -> Response {
    let req = EnrichmentRequest {
        entity_id,
        tenant_id:   body.tenant_id,
        entity_type: body.entity_type.clone(),
        attributes:  body.attributes.clone().unwrap_or(serde_json::Value::Null),
    };

    match state.orchestrator.enrich(&req).await {
        Ok(results) => (StatusCode::OK, Json(json!({
            "success":        true,
            "entity_id":      entity_id,
            "providers_run":  results.len(),
            "results":        results,
        })))
            .into_response(),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() })),
        )
            .into_response(),
    }
}

#[derive(Debug, Deserialize)]
pub struct EnrichRequest {
    pub tenant_id:   Uuid,
    pub entity_type: String,
    pub attributes:  Option<serde_json::Value>,
}

/// POST /enrich/batch
///
/// Enrich a batch of entities. Processes them concurrently (max 10 at once).
pub async fn enrich_batch(
    State(state): State<AppState>,
    Json(req):    Json<BatchEnrichRequest>,
) -> Response {
    use futures::stream::{self, StreamExt};

    let orchestrator = Arc::clone(&state.orchestrator);

    let results: Vec<_> = stream::iter(req.entities)
        .map(|item| {
            let orch = Arc::clone(&orchestrator);
            async move {
                let enrich_req = EnrichmentRequest {
                    entity_id:   item.entity_id,
                    tenant_id:   req.tenant_id,
                    entity_type: item.entity_type.clone(),
                    attributes:  item.attributes.unwrap_or(serde_json::Value::Null),
                };
                let result = orch.enrich(&enrich_req).await;
                json!({
                    "entity_id": item.entity_id,
                    "success":   result.is_ok(),
                    "providers": result.map(|r| r.len()).unwrap_or(0),
                })
            }
        })
        .buffer_unordered(10)
        .collect()
        .await;

    (StatusCode::OK, Json(json!({
        "success": true,
        "processed": results.len(),
        "results":   results,
    })))
        .into_response()
}

#[derive(Debug, Deserialize)]
pub struct BatchEnrichRequest {
    pub tenant_id: Uuid,
    pub entities:  Vec<BatchItem>,
}

#[derive(Debug, Deserialize)]
pub struct BatchItem {
    pub entity_id:   Uuid,
    pub entity_type: String,
    pub attributes:  Option<serde_json::Value>,
}
