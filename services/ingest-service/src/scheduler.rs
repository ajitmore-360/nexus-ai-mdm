use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

use sqlx::PgPool;
use uuid::Uuid;

use crate::crypto::decrypt_config;
use crate::models::{IngestBatch, IngestRecord};
use crate::processor::IngestProcessor;

/// Minimum poll interval — guards against misconfigured 0-second schedules.
const MIN_INTERVAL_SECS: u64 = 60;
/// Default pull interval when sync_schedule is absent or unparseable.
const DEFAULT_INTERVAL_SECS: u64 = 3_600;

struct ScheduledSource {
    id:                Uuid,
    tenant_id:         Uuid,
    code:              String,
    connection_config: serde_json::Value,
    sync_schedule:     Option<String>,
}

/// Spawn a background pull loop for every active REST connector configured with
/// `sync_mode = 'scheduled'`. Each connector gets its own tokio task that fires
/// according to its `sync_schedule` (seconds) and feeds results through the
/// standard ingest pipeline.
pub async fn start_scheduled_pulls(pool: Arc<PgPool>, processor: Arc<IngestProcessor>) {
    match load_sources(&pool).await {
        Ok(sources) => {
            let n = sources.len();
            for src in sources {
                let pool_c = Arc::clone(&pool);
                let proc_c = Arc::clone(&processor);
                tokio::spawn(pull_loop(src, pool_c, proc_c));
            }
            tracing::info!(count = n, "Scheduled REST pull loops started");
        }
        Err(e) => {
            tracing::error!(error=%e, "Failed to load scheduled REST sources; pull scheduler not started");
        }
    }
}

async fn load_sources(pool: &PgPool) -> anyhow::Result<Vec<ScheduledSource>> {
    let rows = sqlx::query_as::<_, (Uuid, Uuid, String, serde_json::Value, Option<String>)>(
        "SELECT id, tenant_id, code, connection_config, sync_schedule
         FROM core_mdm.source_systems_registry
         WHERE connector_type = 'rest_api'
           AND sync_mode      = 'scheduled'
           AND is_active      = TRUE",
    )
    .fetch_all(pool)
    .await?;

    Ok(rows
        .into_iter()
        .map(|(id, tenant_id, code, connection_config, sync_schedule)| ScheduledSource {
            id,
            tenant_id,
            code,
            connection_config,
            sync_schedule,
        })
        .collect())
}

async fn pull_loop(src: ScheduledSource, pool: Arc<PgPool>, processor: Arc<IngestProcessor>) {
    let interval_secs = parse_interval_secs(src.sync_schedule.as_deref());
    let config = decrypt_config(&src.connection_config);

    tracing::info!(
        source_system = %src.code,
        tenant_id     = %src.tenant_id,
        interval_secs,
        "REST pull loop started",
    );

    let mut ticker = tokio::time::interval(Duration::from_secs(interval_secs));
    ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);

    loop {
        ticker.tick().await;

        if let Err(e) = pull_once(&src, &config, &pool, &processor).await {
            tracing::warn!(
                source_system = %src.code,
                tenant_id     = %src.tenant_id,
                error         = %e,
                "Scheduled REST pull failed — will retry next interval",
            );
        }
    }
}

async fn pull_once(
    src: &ScheduledSource,
    config: &serde_json::Value,
    pool: &PgPool,
    processor: &IngestProcessor,
) -> anyhow::Result<()> {
    let base_url = config
        .get("base_url")
        .and_then(|v| v.as_str())
        .ok_or_else(|| anyhow::anyhow!("base_url not configured for {}", src.code))?;

    let endpoint = config
        .get("endpoint_path")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    let entity_type = config
        .get("entity_type")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown");

    let url = if endpoint.is_empty() {
        base_url.trim_end_matches('/').to_string()
    } else if endpoint.starts_with('/') {
        format!("{}{}", base_url.trim_end_matches('/'), endpoint)
    } else {
        format!("{}/{}", base_url.trim_end_matches('/'), endpoint)
    };

    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(30))
        .build()?;

    let req = apply_auth(client.get(&url), config);
    let response = req.send().await?;
    let status = response.status();
    if !status.is_success() {
        return Err(anyhow::anyhow!("REST pull returned HTTP {} for {}", status, url));
    }

    let body: serde_json::Value = response.json().await?;

    // Accept a root JSON array or {"data":[...]}, {"items":[...]}, {"records":[...]}
    let arr_val = if body.is_array() {
        body
    } else {
        body.get("data")
            .or_else(|| body.get("items"))
            .or_else(|| body.get("records"))
            .cloned()
            .unwrap_or(serde_json::Value::Array(vec![]))
    };

    let arr = arr_val
        .as_array()
        .ok_or_else(|| anyhow::anyhow!("REST response from {} did not contain a JSON array", url))?;

    if arr.is_empty() {
        tracing::debug!(source_system = %src.code, "Pull returned 0 records");
        return Ok(());
    }

    let ingest_records: Vec<IngestRecord> = arr
        .iter()
        .filter_map(|item| {
            let obj = item.as_object()?;
            let source_id = obj
                .get("id")
                .or_else(|| obj.get("source_id"))
                .and_then(|v| v.as_str())
                .map(str::to_owned)
                .unwrap_or_else(|| Uuid::new_v4().to_string());

            let fields: HashMap<String, serde_json::Value> =
                obj.iter().map(|(k, v)| (k.clone(), v.clone())).collect();

            Some(IngestRecord::new(
                src.code.clone(),
                source_id,
                entity_type.to_string(),
                fields,
            ))
        })
        .collect();

    let count = ingest_records.len();
    let batch = IngestBatch::new(src.tenant_id, src.code.clone(), ingest_records);
    let result = processor.process_batch(&batch, &[]).await?;

    tracing::info!(
        source_system = %src.code,
        tenant_id     = %src.tenant_id,
        fetched       = count,
        ingested      = result.processed,
        failed        = result.failed,
        "Scheduled REST pull complete",
    );

    let _ = sqlx::query(
        "UPDATE core_mdm.source_systems_registry
         SET last_sync_at = NOW(), updated_at = NOW()
         WHERE id = $1",
    )
    .bind(src.id)
    .execute(pool)
    .await;

    Ok(())
}

/// Apply authentication from `connection_config` to a request builder.
/// Supports `auth_type`: "bearer", "basic", "api_key", or "none".
pub fn apply_auth(
    req: reqwest::RequestBuilder,
    config: &serde_json::Value,
) -> reqwest::RequestBuilder {
    match config
        .get("auth_type")
        .and_then(|v| v.as_str())
        .unwrap_or("none")
    {
        "bearer" => {
            if let Some(token) = config.get("token").and_then(|v| v.as_str()) {
                req.bearer_auth(token)
            } else {
                req
            }
        }
        "basic" => {
            let username = config
                .get("username")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            let password = config
                .get("password")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            req.basic_auth(username, Some(password))
        }
        "api_key" => {
            let header = config
                .get("api_key_header")
                .and_then(|v| v.as_str())
                .unwrap_or("X-API-Key");
            let value = config
                .get("api_key_value")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            req.header(header, value)
        }
        _ => req,
    }
}

fn parse_interval_secs(schedule: Option<&str>) -> u64 {
    schedule
        .and_then(|s| s.parse::<u64>().ok())
        .map(|v| v.max(MIN_INTERVAL_SECS))
        .unwrap_or(DEFAULT_INTERVAL_SECS)
}
