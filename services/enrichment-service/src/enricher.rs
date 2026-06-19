use std::collections::HashMap;
use std::sync::Arc;

use anyhow::Result;
use reqwest::Client;
use tracing::{info, instrument, warn};
use uuid::Uuid;

use crate::providers::{EnrichmentData, EnrichmentProvider, EnrichmentRequest};

/// Orchestrates enrichment across all registered providers for a single entity.
pub struct EnrichmentOrchestrator {
    providers:    Vec<Arc<dyn EnrichmentProvider>>,
    http:         Client,
    mdm_core_url: String,
}

impl EnrichmentOrchestrator {
    pub fn new(providers: Vec<Arc<dyn EnrichmentProvider>>, mdm_core_url: String) -> Self {
        let http = Client::builder()
            .timeout(std::time::Duration::from_secs(30))
            .build()
            .expect("failed to build enrichment HTTP client");
        Self { providers, http, mdm_core_url }
    }

    /// Run all applicable providers for `req`, merge results, and PATCH the
    /// entity in mdm-core with the enriched attributes.
    #[instrument(skip(self, req), fields(entity_id=%req.entity_id, entity_type=%req.entity_type))]
    pub async fn enrich(&self, req: &EnrichmentRequest) -> Result<Vec<EnrichmentData>> {
        let mut results = Vec::new();

        for provider in &self.providers {
            if !provider.applies_to(req) {
                continue;
            }
            match provider.enrich(req).await {
                Ok(data) => {
                    info!(
                        provider  = provider.name(),
                        fields    = data.fields.len(),
                        confidence = data.confidence,
                        "enrichment complete"
                    );
                    results.push(data);
                }
                Err(e) => {
                    warn!(provider=provider.name(), error=%e, "enrichment failed; continuing");
                }
            }
        }

        if !results.is_empty() {
            // Merge all enriched fields
            let mut merged: HashMap<String, serde_json::Value> = HashMap::new();
            for data in &results {
                merged.extend(data.fields.clone());
            }

            // PATCH entity attributes via mdm-core; on success record lineage
            match self.patch_entity(req.tenant_id, req.entity_id, &merged).await {
                Ok(()) => {
                    if let Err(e) = self.record_lineage(req.tenant_id, req.entity_id).await {
                        warn!(entity_id=%req.entity_id, error=%e, "lineage recording failed (non-fatal)");
                    }
                }
                Err(e) => {
                    warn!(entity_id=%req.entity_id, error=%e, "failed to patch enriched entity");
                }
            }
        }

        Ok(results)
    }

    async fn record_lineage(&self, tenant_id: Uuid, entity_id: Uuid) -> Result<()> {
        let url = format!("{}/lineage", self.mdm_core_url.trim_end_matches('/'));
        let resp = self.http
            .post(&url)
            .header("x-tenant-id", tenant_id.to_string())
            .header("x-source", "enrichment-service")
            .json(&serde_json::json!({
                "tenant_id":        tenant_id,
                "source_entity_id": entity_id,
                "target_entity_id": entity_id,
                "lineage_type":     "enriched",
                "metadata": {
                    "source": "enrichment-service"
                }
            }))
            .send()
            .await?;

        if !resp.status().is_success() {
            let status = resp.status();
            let body   = resp.text().await.unwrap_or_default();
            anyhow::bail!("mdm-core POST /lineage returned {}: {}", status, body);
        }

        Ok(())
    }

    async fn patch_entity(
        &self,
        tenant_id: Uuid,
        entity_id: Uuid,
        new_fields: &HashMap<String, serde_json::Value>,
    ) -> Result<()> {
        let url = format!(
            "{}/entities/{}/attributes",
            self.mdm_core_url.trim_end_matches('/'),
            entity_id
        );

        let resp = self.http
            .patch(&url)
            .header("x-tenant-id", tenant_id.to_string())
            .header("x-source", "enrichment-service")
            .json(&serde_json::json!({ "attributes": new_fields }))
            .send()
            .await?;

        if !resp.status().is_success() {
            let status = resp.status();
            let body   = resp.text().await.unwrap_or_default();
            anyhow::bail!("mdm-core PATCH returned {}: {}", status, body);
        }

        Ok(())
    }
}
