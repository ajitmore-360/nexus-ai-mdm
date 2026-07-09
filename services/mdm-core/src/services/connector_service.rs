use axum::http::StatusCode;
use sqlx::PgPool;
use uuid::Uuid;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use chrono::{DateTime, Utc};

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct ConnectorCatalogEntry {
    pub connector_code:  String,
    pub display_name:    String,
    pub vendor:          String,
    pub category:        String,
    pub connector_type:  String,
    pub description:     Option<String>,
    pub logo_url:        Option<String>,
    pub config_schema:   Value,
    pub auth_type:       String,
    pub is_certified:    bool,
    pub is_active:       bool,
    pub docs_url:        Option<String>,
}

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct TenantConnector {
    pub connector_instance_id: Uuid,
    pub tenant_id:             Uuid,
    pub connector_code:        String,
    pub instance_name:         String,
    pub config:                Value,
    pub is_active:             bool,
    pub last_sync_at:          Option<DateTime<Utc>>,
    pub sync_status:           Option<String>,
    pub sync_error:            Option<String>,
    pub created_at:            DateTime<Utc>,
    pub updated_at:            Option<DateTime<Utc>>,
}

#[derive(Debug, Deserialize)]
pub struct CreateConnectorInstance {
    pub connector_code: String,
    pub instance_name:  String,
    pub config:         Option<Value>,
}

pub struct ConnectorService {
    db: PgPool,
}

impl ConnectorService {
    pub fn new(db: PgPool) -> Self {
        Self { db }
    }

    pub async fn list_catalog(&self) -> Result<Vec<ConnectorCatalogEntry>, StatusCode> {
        sqlx::query_as::<_, ConnectorCatalogEntry>(
            "SELECT connector_code, display_name, vendor, category, connector_type,
                    description, logo_url, config_schema, auth_type, is_certified,
                    is_active, docs_url
             FROM core_mdm.connector_catalog
             WHERE is_active = TRUE
             ORDER BY category, display_name"
        )
        .fetch_all(&self.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
    }

    pub async fn list_instances(&self, tenant_id: Uuid) -> Result<Vec<TenantConnector>, StatusCode> {
        sqlx::query_as::<_, TenantConnector>(
            "SELECT connector_instance_id, tenant_id, connector_code, instance_name,
                    config, is_active, last_sync_at, sync_status, sync_error,
                    created_at, updated_at
             FROM core_mdm.tenant_connectors
             WHERE tenant_id = $1
             ORDER BY created_at DESC"
        )
        .bind(tenant_id)
        .fetch_all(&self.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
    }

    pub async fn get_instance(&self, tenant_id: Uuid, instance_id: Uuid) -> Result<TenantConnector, StatusCode> {
        sqlx::query_as::<_, TenantConnector>(
            "SELECT connector_instance_id, tenant_id, connector_code, instance_name,
                    config, is_active, last_sync_at, sync_status, sync_error,
                    created_at, updated_at
             FROM core_mdm.tenant_connectors
             WHERE tenant_id=$1 AND connector_instance_id=$2"
        )
        .bind(tenant_id)
        .bind(instance_id)
        .fetch_optional(&self.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::NOT_FOUND)
    }

    pub async fn create_instance(
        &self,
        tenant_id: Uuid,
        actor: Uuid,
        req: CreateConnectorInstance,
    ) -> Result<TenantConnector, StatusCode> {
        let config = req.config.unwrap_or(serde_json::json!({}));

        sqlx::query_as::<_, TenantConnector>(
            "INSERT INTO core_mdm.tenant_connectors
                 (tenant_id, connector_code, instance_name, config, created_by)
             VALUES ($1,$2,$3,$4,$5)
             RETURNING connector_instance_id, tenant_id, connector_code, instance_name,
                       config, is_active, last_sync_at, sync_status, sync_error,
                       created_at, updated_at"
        )
        .bind(tenant_id)
        .bind(req.connector_code)
        .bind(req.instance_name)
        .bind(config)
        .bind(actor)
        .fetch_one(&self.db)
        .await
        .map_err(|e| {
            let msg = e.to_string();
            if msg.contains("unique") { StatusCode::CONFLICT }
            else if msg.contains("foreign key") { StatusCode::BAD_REQUEST }
            else { StatusCode::INTERNAL_SERVER_ERROR }
        })
    }

    pub async fn update_instance(
        &self,
        tenant_id: Uuid,
        instance_id: Uuid,
        config: Value,
    ) -> Result<TenantConnector, StatusCode> {
        sqlx::query_as::<_, TenantConnector>(
            "UPDATE core_mdm.tenant_connectors
             SET config=$3, updated_at=NOW()
             WHERE tenant_id=$1 AND connector_instance_id=$2
             RETURNING connector_instance_id, tenant_id, connector_code, instance_name,
                       config, is_active, last_sync_at, sync_status, sync_error,
                       created_at, updated_at"
        )
        .bind(tenant_id)
        .bind(instance_id)
        .bind(config)
        .fetch_optional(&self.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::NOT_FOUND)
    }

    pub async fn delete_instance(&self, tenant_id: Uuid, instance_id: Uuid) -> Result<(), StatusCode> {
        let rows = sqlx::query(
            "DELETE FROM core_mdm.tenant_connectors WHERE tenant_id=$1 AND connector_instance_id=$2"
        )
        .bind(tenant_id)
        .bind(instance_id)
        .execute(&self.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .rows_affected();

        if rows == 0 { Err(StatusCode::NOT_FOUND) } else { Ok(()) }
    }

    /// Stub connectivity test — in production this would open a real connection.
    pub async fn test_instance(&self, _tenant_id: Uuid, instance_id: Uuid) -> Result<Value, StatusCode> {
        sqlx::query(
            "UPDATE core_mdm.tenant_connectors SET sync_status='idle', last_sync_at=NOW() WHERE connector_instance_id=$1"
        )
        .bind(instance_id)
        .execute(&self.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

        Ok(serde_json::json!({
            "success": true,
            "latency_ms": 42,
            "error": null
        }))
    }
}
