use std::collections::HashMap;
use std::time::Instant;

use anyhow::Result;
use serde_json::Value;
use uuid::Uuid;

use crate::summary::GenerationSummary;

// ── JSON output ───────────────────────────────────────────────────────────────

pub fn write_json(entities: &[HashMap<String, Value>], entity_type: &str) -> Result<()> {
    let wrapper = serde_json::json!({
        "entity_type": entity_type,
        "count":       entities.len(),
        "entities":    entities,
    });
    println!("{}", serde_json::to_string_pretty(&wrapper)?);
    Ok(())
}

// ── CSV output ────────────────────────────────────────────────────────────────

pub fn write_csv(entities: &[HashMap<String, Value>], _entity_type: &str) -> Result<()> {
    if entities.is_empty() {
        return Ok(());
    }

    // Collect all keys in stable order
    let mut keys: Vec<String> = entities[0].keys().cloned().collect();
    keys.sort();

    let mut wtr = csv::Writer::from_writer(std::io::stdout());
    wtr.write_record(&keys)?;

    for entity in entities {
        let row: Vec<String> = keys.iter().map(|k| {
            entity.get(k)
                .map(|v| match v {
                    Value::String(s) => s.clone(),
                    Value::Null      => String::new(),
                    other            => other.to_string().trim_matches('"').to_string(),
                })
                .unwrap_or_default()
        }).collect();
        wtr.write_record(&row)?;
    }

    wtr.flush()?;
    Ok(())
}

// ── API output — POST to ingest service ───────────────────────────────────────

pub async fn post_to_api(
    entities:    Vec<HashMap<String, Value>>,
    entity_type: &str,
    tenant_id:   Uuid,
    api_url:     &str,
    token:       &str,
    batch_size:  usize,
) -> Result<GenerationSummary> {
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(60))
        .build()?;

    let total  = entities.len();
    let chunks: Vec<_> = entities.chunks(batch_size).collect();
    let total_batches  = chunks.len();

    let mut summary = GenerationSummary {
        total_generated: total,
        ..Default::default()
    };

    let url = format!("{}/ingest/entities", api_url.trim_end_matches('/'));
    let started = Instant::now();

    for (i, chunk) in chunks.iter().enumerate() {
        let batch_num = i + 1;
        print!("  Batch {}/{} ({} records)... ", batch_num, total_batches, chunk.len());

        let body = serde_json::json!({
            "tenant_id":     tenant_id,
            "source_system": "nexus-datagen",
            "entity_type":   entity_type,
            "records":       chunk,
        });

        match client
            .post(&url)
            .header("Authorization", format!("Bearer {}", token))
            .header("x-tenant-id", tenant_id.to_string())
            .json(&body)
            .send()
            .await
        {
            Ok(resp) if resp.status().is_success() => {
                let result: serde_json::Value = resp.json().await.unwrap_or_default();
                let created = result
                    .pointer("/data/result/processed")
                    .and_then(|v| v.as_u64())
                    .unwrap_or(chunk.len() as u64) as usize;
                let failed = result
                    .pointer("/data/result/failed")
                    .and_then(|v| v.as_u64())
                    .unwrap_or(0) as usize;

                summary.total_created += created;
                summary.total_failed  += failed;
                summary.batches_sent  += 1;
                println!("✓ {} created, {} failed", created, failed);
            }
            Ok(resp) => {
                let status = resp.status();
                let body   = resp.text().await.unwrap_or_default();
                summary.total_failed += chunk.len();
                println!("✗ HTTP {} — {}", status, &body[..body.len().min(80)]);
            }
            Err(e) => {
                summary.total_failed += chunk.len();
                println!("✗ Network error: {}", e);
            }
        }
    }

    summary.duration_ms = started.elapsed().as_millis() as u64;
    Ok(summary)
}
