use std::time::Instant;

use anyhow::Result;
use chrono::Utc;
use reqwest::Client;
use tracing::{info, instrument, warn};
use uuid::Uuid;

use contracts::mdm::distribution::{CreateEntityRequest, EntityRecordOrigin};
use contracts::mdm::entity::{
    CanonicalEntity, EntityAttribute, EntityStatus, EntityType,
};
use contracts::mdm::common::AuditMetadata;

use crate::models::{IngestBatch, IngestResult, SchemaMapping};
use crate::pipeline::{Normalizer, SchemaMapper};

/// System-managed fields that external callers must never be able to inject via ingest.
/// Stripping these prevents mass-assignment attacks where a malicious source system
/// tries to set trust scores, override golden record links, or inject ML scores.
const INTERNAL_FIELDS: &[&str] = &[
    "entity_id",
    "golden_record_id",
    "trust_score",
    "quality_score",
    "ai_score",
    "vector_embedding",
    "embedding",
    "match_status",
    "survivorship_score",
    "merge_refs",
    "policy_refs",
    "created_at",
    "updated_at",
    "recorded_at",
    "valid_from",
    "valid_to",
    "version",
    "tenant_id",   // tenant always comes from the batch, never field data
];

/// Orchestrates the full ingest pipeline for a batch of records:
///
/// 1. Schema mapping   — rename source fields → canonical names
/// 2. Normalization    — apply field transforms (phone, email, date, etc.)
/// 3. Entity building  — convert mapped fields → `CanonicalEntity`
/// 4. MDM-Core write   — POST /entities to persist and trigger matching
pub struct IngestProcessor {
    http:         Client,
    mdm_core_url: String,
    normalizer:   Normalizer,
}

impl IngestProcessor {
    pub fn new(http: Client, mdm_core_url: String) -> Self {
        Self {
            http,
            mdm_core_url,
            normalizer: Normalizer::new(),
        }
    }

    #[instrument(skip(self, batch), fields(
        batch_id  = %batch.batch_id,
        tenant_id = %batch.tenant_id,
        records   = batch.records.len(),
    ))]
    pub async fn process_batch(
        &self,
        batch:    &IngestBatch,
        mappings: &[SchemaMapping],
    ) -> Result<IngestResult> {
        let started = Instant::now();
        let mut result = IngestResult::new(batch.batch_id);
        // If caller provides explicit mappings use those; otherwise apply defaults
        // (email_address→email, phone_number→phone, company→legal_name, etc.)
        let mapper = if mappings.is_empty() {
            SchemaMapper::with_defaults()
        } else {
            SchemaMapper::new(mappings.to_vec())
        };

        for record in &batch.records {
            // ── 0. Strip internal/privileged fields (mass-assignment prevention)
            // Callers must never be able to inject system-managed fields via ingest.
            let mut sanitized_fields = record.raw_fields.clone();
            for field in INTERNAL_FIELDS {
                sanitized_fields.remove(*field);
            }
            let mut sanitized_record = record.clone();
            sanitized_record.raw_fields = sanitized_fields;
            let record = &sanitized_record;

            // ── 1. Schema mapping ───────────────────────────────────────────
            let mapped_fields = mapper.map(record.raw_fields.clone());

            // ── 2. Normalization ────────────────────────────────────────────
            let mut normalised_record = record.clone();
            normalised_record.raw_fields = mapped_fields;
            let normalised = self.normalizer.normalize_record(normalised_record, mappings);

            // ── 3. Build CanonicalEntity ────────────────────────────────────
            let entity = build_entity(batch.tenant_id, &normalised);

            // ── 4. POST to MDM-Core ─────────────────────────────────────────
            let request = CreateEntityRequest {
                entity,
                record_origin:       EntityRecordOrigin::Ingested,
                distribute:          false,
                distribution_targets: vec![],
            };

            let url = format!("{}/entities", self.mdm_core_url.trim_end_matches('/'));

            match self.http
                .post(&url)
                .header("x-tenant-id", batch.tenant_id.to_string())
                .header("x-source-system", &normalised.source_system)
                .json(&request)
                .send()
                .await
            {
                Ok(resp) if resp.status().is_success() => {
                    if let Ok(body) = resp.json::<serde_json::Value>().await {
                        if let Some(eid) = body
                            .pointer("/data/entity_id")
                            .and_then(|v| v.as_str())
                            .and_then(|s| Uuid::parse_str(s).ok())
                        {
                            result.entity_ids.push(eid);
                        }
                    }
                    result.processed += 1;
                }
                Ok(resp) => {
                    let status = resp.status();
                    let body   = resp.text().await.unwrap_or_default();
                    warn!(
                        source_entity_id=%normalised.source_entity_id,
                        http_status=%status,
                        body=%body,
                        "mdm-core rejected record"
                    );
                    result.failed += 1;
                    result.errors.push(format!(
                        "{}: http {} — {}",
                        normalised.source_entity_id, status, body
                    ));
                }
                Err(e) => {
                    warn!(
                        source_entity_id=%normalised.source_entity_id,
                        error=%e,
                        "failed to send record to mdm-core"
                    );
                    result.failed += 1;
                    result.errors.push(format!(
                        "{}: network error — {}",
                        normalised.source_entity_id, e
                    ));
                }
            }
        }

        result.finalize(started.elapsed().as_millis() as u64);

        info!(
            batch_id=%batch.batch_id,
            processed=result.processed,
            failed=result.failed,
            duration_ms=result.duration_ms,
            "batch processing complete"
        );

        Ok(result)
    }
}

/// Convert an `IngestRecord` (after mapping + normalisation) into a
/// `CanonicalEntity` ready to POST to MDM-Core.
fn build_entity(tenant_id: Uuid, record: &crate::models::IngestRecord) -> CanonicalEntity {
    let now = Utc::now();

    let attributes: Vec<EntityAttribute> = record
        .raw_fields
        .iter()
        .map(|(k, v)| EntityAttribute {
            attribute_id:            Uuid::new_v4(),
            key:                     k.clone(),
            value:                   v.clone(),
            data_type:               "string".to_string(),
            confidence:              None,
            provenance:              None,
            policy_tags:             vec![],
            semantic_type:           None,
            aliases:                 vec![],
            embedding_ref:           None,
            ai_annotations:          vec![],
            searchable:              true,
            indexed:                 true,
            encrypted:               false,
            survivorship_eligible:   true,
            updated_at:              Some(now),
            attribute_version:       1,
            metadata:                Default::default(),
        })
        .collect();

    CanonicalEntity {
        entity_id:       Uuid::new_v4(),
        tenant_id,
        entity_type:     EntityType::Customer,
        status:          EntityStatus::Active,
        external_ids:    [(
            record.source_system.clone(),
            record.source_entity_id.clone(),
        )]
        .into(),
        attributes,
        relationships:   vec![],
        source_snapshots: vec![],
        version_info:    contracts::mdm::common::VersionInfo {
            schema_version:   "v1".to_string(),
            contract_version: "1.0".to_string(),
            entity_version:   1,
        },
        audit:           AuditMetadata {
            created_at:     now,
            updated_at:     now,
            created_by:     None,
            updated_by:     None,
            correlation_id: None,
            causation_id:   None,
            request_id:     None,
        },
        tags:            vec![],
        data_quality:    None,
        metadata:        Default::default(),
        embedding_refs:  vec![],
        trust_score:     Some(0.5),
        master_record:   None,
        lineage_refs:    vec![],
        merge_refs:      vec![],
        survivorship_refs: vec![],
        workflow_refs:   vec![],
        policy_refs:     vec![],
        changes:         vec![],
        semantic_identity: None,
        vector_namespace: None,
        valid_from:      Some(now),
        valid_to:        None,
    }
}
