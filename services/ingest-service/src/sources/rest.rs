use std::sync::Arc;

use axum::{
    extract::{Extension, State},
    http::StatusCode,
    response::IntoResponse,
    Json,
};
use nexus_auth::Claims;
use serde::Deserialize;
use serde_json::json;
use uuid::Uuid;

use crate::jobs::persist_job;
use crate::models::{IngestBatch, IngestRecord};
use crate::state::AppState;

// ============================================================
// POST /ingest/batch
// ============================================================

pub async fn ingest_batch(
    State(state):      State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Json(mut batch):   Json<IngestBatch>,
) -> impl IntoResponse {
    // Enforce tenant isolation — always use the JWT-authenticated tenant, ignoring any body value.
    batch.tenant_id = claims.nxs_tenant_id;
    if batch.records.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({ "success": false, "error": "batch has no records" })),
        );
    }
    if batch.records.len() > state.settings.max_batch_size {
        return (
            StatusCode::PAYLOAD_TOO_LARGE,
            Json(json!({
                "success": false,
                "error": format!("batch exceeds max size of {}", state.settings.max_batch_size)
            })),
        );
    }

    match state.processor.process_batch(&batch, &[]).await {
        Ok(result) => {
            let job_id = match persist_job(&state.pool, &batch, &result).await {
                Ok(id) => Some(id),
                Err(e) => {
                    tracing::warn!(error=%e, "failed to persist ingest job — result still returned");
                    None
                }
            };
            (StatusCode::OK, Json(json!({ "success": true, "job_id": job_id, "result": result })))
        }
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() })),
        ),
    }
}

// ============================================================
// POST /ingest/entities  (array of raw entity objects)
// ============================================================

#[derive(Deserialize)]
pub struct RawEntitiesRequest {
    pub source_system: String,
    pub entity_type:   String,
    pub records:       Vec<serde_json::Map<String, serde_json::Value>>,
}

pub async fn ingest_entities(
    State(state):      State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Json(req):         Json<RawEntitiesRequest>,
) -> impl IntoResponse {
    if req.records.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({ "success": false, "error": "no records provided" })),
        );
    }

    let ingest_records: Vec<IngestRecord> = req
        .records
        .into_iter()
        .map(|obj| {
            let source_id = obj
                .get("id")
                .or_else(|| obj.get("source_id"))
                .and_then(|v| v.as_str())
                .map(str::to_owned)
                .unwrap_or_else(|| Uuid::new_v4().to_string());

            IngestRecord::new(
                req.source_system.clone(),
                source_id,
                req.entity_type.clone(),
                obj.into_iter()
                    .collect(),
            )
        })
        .collect();

    let batch = IngestBatch::new(claims.nxs_tenant_id, req.source_system.clone(), ingest_records);

    match state.processor.process_batch(&batch, &[]).await {
        Ok(result) => {
            let job_id = match persist_job(&state.pool, &batch, &result).await {
                Ok(id) => Some(id),
                Err(e) => {
                    tracing::warn!(error=%e, "failed to persist ingest job — result still returned");
                    None
                }
            };
            (StatusCode::OK, Json(json!({ "success": true, "job_id": job_id, "result": result })))
        }
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() })),
        ),
    }
}

// ============================================================
// POST /ingest/csv  (CSV text body)
// ============================================================

#[derive(Deserialize)]
pub struct CsvIngestRequest {
    pub source_system: String,
    pub entity_type:   String,
    pub csv_data:      String,
}

pub async fn ingest_csv(
    State(state):      State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    Json(req):         Json<CsvIngestRequest>,
) -> impl IntoResponse {
    let mut rdr = csv::Reader::from_reader(req.csv_data.as_bytes());
    let headers = match rdr.headers() {
        Ok(h) => h.iter().map(str::to_owned).collect::<Vec<_>>(),
        Err(e) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({ "success": false, "error": format!("CSV parse error: {e}") })),
            );
        }
    };

    let mut records = Vec::new();
    for result in rdr.records() {
        match result {
            Ok(row) => {
                let fields: std::collections::HashMap<String, serde_json::Value> = headers
                    .iter()
                    .zip(row.iter())
                    .map(|(h, v)| (h.clone(), serde_json::Value::String(v.to_string())))
                    .collect();

                let source_id = fields
                    .get("id")
                    .or_else(|| fields.get("source_id"))
                    .and_then(|v| v.as_str())
                    .map(str::to_owned)
                    .unwrap_or_else(|| Uuid::new_v4().to_string());

                records.push(IngestRecord::new(
                    req.source_system.clone(),
                    source_id,
                    req.entity_type.clone(),
                    fields,
                ));
            }
            Err(e) => {
                tracing::warn!(error=%e, "skipping malformed CSV row");
            }
        }
    }

    if records.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({ "success": false, "error": "CSV contained no valid rows" })),
        );
    }

    let batch = IngestBatch::new(claims.nxs_tenant_id, req.source_system.clone(), records);

    match state.processor.process_batch(&batch, &[]).await {
        Ok(result) => {
            let job_id = match persist_job(&state.pool, &batch, &result).await {
                Ok(id) => Some(id),
                Err(e) => {
                    tracing::warn!(error=%e, "failed to persist ingest job — result still returned");
                    None
                }
            };
            (StatusCode::OK, Json(json!({ "success": true, "job_id": job_id, "result": result })))
        }
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "success": false, "error": e.to_string() })),
        ),
    }
}
