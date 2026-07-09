use axum::http::StatusCode;
use sqlx::PgPool;
use uuid::Uuid;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use chrono::{DateTime, Utc};

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct EnrichmentProvider {
    pub provider_code:          String,
    pub display_name:           String,
    pub category:               String,
    pub description:            Option<String>,
    pub logo_url:               Option<String>,
    pub config_schema:          Value,
    pub supported_entity_types: Value,
    pub is_active:              bool,
    pub docs_url:               Option<String>,
}

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct TenantEnrichmentConfig {
    pub enrichment_config_id: Uuid,
    pub tenant_id:            Uuid,
    pub provider_code:        String,
    pub is_enabled:           bool,
    pub config:               Value,
    pub auto_enrich:          bool,
    pub entity_type_filter:   Value,
    pub field_mapping:        Value,
    pub daily_quota:          Option<i32>,
    pub quota_used_today:     i32,
    pub quota_reset_at:       Option<DateTime<Utc>>,
    pub created_at:           DateTime<Utc>,
    pub updated_at:           Option<DateTime<Utc>>,
}

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct EnrichmentRequest {
    pub request_id:      Uuid,
    pub tenant_id:       Uuid,
    pub entity_id:       Uuid,
    pub provider_code:   String,
    pub status:          String,
    pub fields_enriched: Value,
    pub error_message:   Option<String>,
    pub created_at:      DateTime<Utc>,
    pub completed_at:    Option<DateTime<Utc>>,
}

#[derive(Debug, Deserialize)]
pub struct UpsertEnrichmentConfig {
    pub is_enabled:          Option<bool>,
    pub api_key:             Option<String>,
    pub config:              Option<Value>,
    pub auto_enrich:         Option<bool>,
    pub entity_type_filter:  Option<Value>,
    pub field_mapping:       Option<Value>,
    pub daily_quota:         Option<i32>,
}

pub struct EnrichmentService {
    db: PgPool,
}

impl EnrichmentService {
    pub fn new(db: PgPool) -> Self {
        Self { db }
    }

    pub async fn list_providers(&self) -> Result<Vec<EnrichmentProvider>, StatusCode> {
        sqlx::query_as!(
            EnrichmentProvider,
            r#"SELECT provider_code, display_name, category, description, logo_url,
                      config_schema, supported_entity_types, is_active, docs_url
               FROM core_mdm.enrichment_providers
               WHERE is_active = TRUE
               ORDER BY category, display_name"#
        )
        .fetch_all(&self.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
    }

    pub async fn list_configs(&self, tenant_id: Uuid) -> Result<Vec<TenantEnrichmentConfig>, StatusCode> {
        sqlx::query_as!(
            TenantEnrichmentConfig,
            r#"SELECT enrichment_config_id, tenant_id, provider_code, is_enabled,
                      config, auto_enrich, entity_type_filter, field_mapping,
                      daily_quota, quota_used_today, quota_reset_at, created_at, updated_at
               FROM core_mdm.tenant_enrichment_configs
               WHERE tenant_id = $1
               ORDER BY provider_code"#,
            tenant_id
        )
        .fetch_all(&self.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
    }

    pub async fn upsert_config(
        &self,
        tenant_id: Uuid,
        provider_code: &str,
        req: UpsertEnrichmentConfig,
    ) -> Result<TenantEnrichmentConfig, StatusCode> {
        let is_enabled         = req.is_enabled.unwrap_or(false);
        let config             = req.config.unwrap_or(serde_json::json!({}));
        let auto_enrich        = req.auto_enrich.unwrap_or(false);
        let entity_type_filter = req.entity_type_filter.unwrap_or(serde_json::json!([]));
        let field_mapping      = req.field_mapping.unwrap_or(serde_json::json!({}));

        sqlx::query_as!(
            TenantEnrichmentConfig,
            r#"INSERT INTO core_mdm.tenant_enrichment_configs
                   (tenant_id, provider_code, is_enabled, config, auto_enrich,
                    entity_type_filter, field_mapping, daily_quota)
               VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
               ON CONFLICT (tenant_id, provider_code)
               DO UPDATE SET
                   is_enabled          = EXCLUDED.is_enabled,
                   config              = EXCLUDED.config,
                   auto_enrich         = EXCLUDED.auto_enrich,
                   entity_type_filter  = EXCLUDED.entity_type_filter,
                   field_mapping       = EXCLUDED.field_mapping,
                   daily_quota         = EXCLUDED.daily_quota,
                   updated_at          = NOW()
               RETURNING enrichment_config_id, tenant_id, provider_code, is_enabled,
                         config, auto_enrich, entity_type_filter, field_mapping,
                         daily_quota, quota_used_today, quota_reset_at, created_at, updated_at"#,
            tenant_id, provider_code, is_enabled, config, auto_enrich,
            entity_type_filter, field_mapping, req.daily_quota
        )
        .fetch_one(&self.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
    }

    pub async fn delete_config(&self, tenant_id: Uuid, provider_code: &str) -> Result<(), StatusCode> {
        let rows = sqlx::query!(
            "DELETE FROM core_mdm.tenant_enrichment_configs WHERE tenant_id=$1 AND provider_code=$2",
            tenant_id, provider_code
        )
        .execute(&self.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .rows_affected();

        if rows == 0 { Err(StatusCode::NOT_FOUND) } else { Ok(()) }
    }

    pub async fn list_requests(
        &self,
        tenant_id: Uuid,
        entity_id: Option<Uuid>,
    ) -> Result<Vec<EnrichmentRequest>, StatusCode> {
        sqlx::query_as!(
            EnrichmentRequest,
            r#"SELECT request_id, tenant_id, entity_id, provider_code, status,
                      fields_enriched, error_message, created_at, completed_at
               FROM core_mdm.enrichment_requests
               WHERE tenant_id=$1 AND ($2::uuid IS NULL OR entity_id=$2)
               ORDER BY created_at DESC LIMIT 200"#,
            tenant_id, entity_id
        )
        .fetch_all(&self.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
    }

    pub async fn trigger_enrichment(
        &self,
        tenant_id: Uuid,
        entity_id: Uuid,
        provider_code: &str,
    ) -> Result<EnrichmentRequest, StatusCode> {
        sqlx::query_as!(
            EnrichmentRequest,
            r#"INSERT INTO core_mdm.enrichment_requests
                   (tenant_id, entity_id, provider_code, request_payload)
               VALUES ($1,$2,$3,'{}')
               RETURNING request_id, tenant_id, entity_id, provider_code, status,
                         fields_enriched, error_message, created_at, completed_at"#,
            tenant_id, entity_id, provider_code
        )
        .fetch_one(&self.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
    }
}
