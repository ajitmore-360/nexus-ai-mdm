use std::sync::Arc;

use axum::{
    extract::{Extension, Multipart, State},
    http::StatusCode,
    response::IntoResponse,
    Json,
};
use azile_auth::Claims;
use azile_redis::queue::{task_types, Task};
use serde::Deserialize;
use serde_json::json;
use uuid::Uuid;

use crate::jobs::{create_job_pending, persist_job};
use crate::models::{IngestBatch, IngestRecord};
use crate::preflight;
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

    // Preflight: verify each unique entity type is configured before processing
    {
        let mut seen = std::collections::HashSet::new();
        let mut all_issues = Vec::new();
        for record in &batch.records {
            if seen.insert(record.entity_type.to_lowercase()) {
                match preflight::check_ingest_readiness(&state.pool, batch.tenant_id, &record.entity_type).await {
                    Ok(issues) => all_issues.extend(issues),
                    Err(e) => {
                        tracing::warn!(error=%e, entity_type=%record.entity_type, "preflight check failed — allowing ingest");
                    }
                }
            }
        }
        if !all_issues.is_empty() {
            return (
                StatusCode::UNPROCESSABLE_ENTITY,
                Json(json!({
                    "success": false,
                    "configuration_required": true,
                    "error": "System not configured — resolve the listed issues before ingesting",
                    "missing": all_issues.iter().map(|i| i.message.as_str()).collect::<Vec<_>>()
                })),
            );
        }
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

    // Preflight: verify entity type is configured before processing
    let preflight_issues = match preflight::check_ingest_readiness(&state.pool, claims.nxs_tenant_id, &req.entity_type).await {
        Ok(issues) => issues,
        Err(e) => {
            tracing::warn!(error=%e, entity_type=%req.entity_type, "preflight check failed — allowing ingest");
            vec![]
        }
    };
    if !preflight_issues.is_empty() {
        return (
            StatusCode::UNPROCESSABLE_ENTITY,
            Json(json!({
                "success": false,
                "configuration_required": true,
                "entity_type": req.entity_type,
                "error": format!("System not configured for '{}' ingest — configure the system first", req.entity_type),
                "missing": preflight_issues.iter().map(|i| i.message.as_str()).collect::<Vec<_>>()
            })),
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
// POST /ingest/csv  (CSV text body — kept for backward compat)
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

    // Preflight: verify entity type is configured before processing
    let preflight_issues = match preflight::check_ingest_readiness(&state.pool, claims.nxs_tenant_id, &req.entity_type).await {
        Ok(issues) => issues,
        Err(e) => {
            tracing::warn!(error=%e, entity_type=%req.entity_type, "preflight check failed — allowing ingest");
            vec![]
        }
    };
    if !preflight_issues.is_empty() {
        return (
            StatusCode::UNPROCESSABLE_ENTITY,
            Json(json!({
                "success": false,
                "configuration_required": true,
                "entity_type": req.entity_type,
                "error": format!("System not configured for '{}' ingest — configure the system first", req.entity_type),
                "missing": preflight_issues.iter().map(|i| i.message.as_str()).collect::<Vec<_>>()
            })),
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

// ============================================================
// POST /ingest/csv/upload  (multipart/form-data)
//
// Accepts a large CSV file, splits it into chunks, and enqueues
// each chunk as an `ingest.batch` Redis task for async processing.
// Returns 202 Accepted with a job_id immediately.
//
// Form fields:
//   source_system  text  (required)
//   entity_type    text  (required)
//   file           file  (.csv, any size)
// ============================================================

pub async fn ingest_csv_upload(
    State(state):      State<Arc<AppState>>,
    Extension(claims): Extension<Claims>,
    mut multipart:     Multipart,
) -> impl IntoResponse {
    let mut source_system: Option<String> = None;
    let mut entity_type:   Option<String> = None;
    let mut csv_bytes:     Option<Vec<u8>> = None;
    let mut file_name_opt: Option<String>  = None;

    while let Ok(Some(field)) = multipart.next_field().await {
        match field.name() {
            Some("source_system") => { source_system = field.text().await.ok(); }
            Some("entity_type")   => { entity_type   = field.text().await.ok(); }
            Some("file") => {
                file_name_opt = field.file_name().map(str::to_owned);
                csv_bytes     = field.bytes().await.ok().map(|b| b.to_vec());
            }
            _ => {}
        }
    }

    let (Some(source_system), Some(entity_type), Some(csv_bytes)) =
        (source_system, entity_type, csv_bytes)
    else {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({
                "success": false,
                "error": "multipart form requires 'source_system', 'entity_type', and 'file' fields"
            })),
        );
    };

    // ── Parse CSV ─────────────────────────────────────────────────────────
    let mut rdr = csv::Reader::from_reader(csv_bytes.as_slice());
    let headers = match rdr.headers() {
        Ok(h) => h.iter().map(str::to_owned).collect::<Vec<_>>(),
        Err(e) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({ "success": false, "error": format!("CSV header parse error: {e}") })),
            );
        }
    };

    let mut all_records: Vec<IngestRecord> = Vec::new();
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

                all_records.push(IngestRecord::new(
                    source_system.clone(),
                    source_id,
                    entity_type.clone(),
                    fields,
                ));
            }
            Err(e) => { tracing::warn!(error=%e, "skipping malformed CSV row"); }
        }
    }

    if all_records.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({ "success": false, "error": "CSV contained no valid rows" })),
        );
    }

    // Preflight: verify entity type is configured before creating the async job
    let preflight_issues = match preflight::check_ingest_readiness(&state.pool, claims.nxs_tenant_id, &entity_type).await {
        Ok(issues) => issues,
        Err(e) => {
            tracing::warn!(error=%e, entity_type=%entity_type, "preflight check failed — allowing upload");
            vec![]
        }
    };
    if !preflight_issues.is_empty() {
        return (
            StatusCode::UNPROCESSABLE_ENTITY,
            Json(json!({
                "success": false,
                "configuration_required": true,
                "entity_type": entity_type,
                "error": format!("System not configured for '{}' ingest — configure the system first", entity_type),
                "missing": preflight_issues.iter().map(|i| i.message.as_str()).collect::<Vec<_>>()
            })),
        );
    }

    let total_records = all_records.len();
    let chunk_size    = state.settings.chunk_size;
    let chunks: Vec<Vec<IngestRecord>> = all_records.chunks(chunk_size).map(|c| c.to_vec()).collect();
    let chunks_total  = chunks.len();

    // ── Create the job record immediately ────────────────────────────────
    let job_id = match create_job_pending(
        &state.pool,
        claims.nxs_tenant_id,
        &source_system,
        file_name_opt.as_deref(),
        total_records as i32,
        chunks_total  as i32,
        chunk_size    as i32,
    ).await {
        Ok(id) => id,
        Err(e) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "success": false, "error": format!("failed to create job: {e}") })),
            );
        }
    };

    // ── Enqueue all chunks ────────────────────────────────────────────────
    let Some(task_queue) = &state.task_queue else {
        return (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(json!({
                "success": false,
                "error": "Redis task queue not configured — set REDIS_URL to enable async CSV ingest"
            })),
        );
    };

    let mut enqueued = 0usize;
    for chunk in chunks {
        let task = Task::new(
            task_types::INGEST_BATCH,
            claims.nxs_tenant_id.to_string(),
            serde_json::json!({
                "job_id":        job_id,
                "batch_id":      Uuid::new_v4(),
                "tenant_id":     claims.nxs_tenant_id,
                "source_system": source_system,
                "records":       chunk,
            }),
        );
        match task_queue.enqueue(task_types::INGEST_BATCH, &task).await {
            Ok(())  => { enqueued += 1; }
            Err(e) => { tracing::error!(job_id=%job_id, error=%e, "failed to enqueue ingest chunk"); }
        }
    }

    (
        StatusCode::ACCEPTED,
        Json(json!({
            "success":       true,
            "job_id":        job_id,
            "total_records": total_records,
            "chunks_queued": enqueued,
            "chunk_size":    chunk_size,
            "message": format!(
                "Ingest job accepted. {} records split into {} chunks of up to {}. Poll /ingest/jobs/{} for progress.",
                total_records, enqueued, chunk_size, job_id
            )
        })),
    )
}
