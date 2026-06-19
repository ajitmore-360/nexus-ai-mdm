use anyhow::Result;
use chrono::{DateTime, Utc};
use sqlx::PgPool;
use uuid::Uuid;

use crate::models::{ConsentRecord, ConsentType, RecordConsentRequest};

/// Manages consent records for GDPR Article 6/7 compliance.
#[derive(Clone)]
pub struct ConsentRepository {
    pool: PgPool,
}

impl ConsentRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Record a new consent grant or withdrawal for a data subject.
    pub async fn record_consent(&self, req: &RecordConsentRequest) -> Result<ConsentRecord> {
        let consent_id = Uuid::new_v4();
        let now = Utc::now();

        let granted_at: Option<DateTime<Utc>> =
            if req.consent_given { Some(now) } else { None };

        sqlx::query(
            r#"
            INSERT INTO core_mdm.consent_records
                (consent_id, tenant_id, entity_id, consent_type, legal_basis,
                 consent_given, purpose, source, granted_at, expires_at,
                 recorded_by, metadata)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
            "#,
        )
        .bind(consent_id)
        .bind(req.tenant_id)
        .bind(req.entity_id)
        .bind(req.consent_type.to_string())
        .bind(&req.legal_basis)
        .bind(req.consent_given)
        .bind(&req.purpose)
        .bind(&req.source)
        .bind(granted_at)
        .bind(req.expires_at)
        .bind(&req.recorded_by)
        .bind(req.metadata.clone().unwrap_or(serde_json::Value::Object(Default::default())))
        .execute(&self.pool)
        .await?;

        Ok(ConsentRecord {
            consent_id,
            tenant_id:     req.tenant_id,
            entity_id:     req.entity_id,
            consent_type:  req.consent_type.clone(),
            legal_basis:   req.legal_basis.clone().unwrap_or_else(|| "consent".to_string()),
            consent_given: req.consent_given,
            purpose:       req.purpose.clone(),
            source:        req.source.clone(),
            granted_at,
            withdrawn_at:  None,
            expires_at:    req.expires_at,
            recorded_by:   req.recorded_by.clone(),
            metadata:      req.metadata.clone().unwrap_or(serde_json::Value::Object(Default::default())),
            created_at:    now,
            updated_at:    now,
        })
    }

    /// List all consent records for an entity (active and withdrawn).
    pub async fn list_by_entity(
        &self,
        tenant_id: Uuid,
        entity_id: Uuid,
    ) -> Result<Vec<ConsentRecord>> {
        let rows = sqlx::query_as::<_, ConsentRow>(
            r#"
            SELECT consent_id, tenant_id, entity_id, consent_type, legal_basis,
                   consent_given, purpose, source, granted_at, withdrawn_at,
                   expires_at, recorded_by, metadata, created_at, updated_at
            FROM core_mdm.consent_records
            WHERE tenant_id = $1 AND entity_id = $2
            ORDER BY created_at DESC
            "#,
        )
        .bind(tenant_id)
        .bind(entity_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(rows.into_iter().map(|r| r.into()).collect())
    }

    /// Withdraw a specific consent record.
    /// Returns true if a record was found and updated, false if not found.
    pub async fn withdraw(&self, tenant_id: Uuid, consent_id: Uuid) -> Result<bool> {
        let result = sqlx::query(
            r#"
            UPDATE core_mdm.consent_records
            SET consent_given = false,
                withdrawn_at  = NOW(),
                updated_at    = NOW()
            WHERE consent_id = $1
              AND tenant_id  = $2
              AND withdrawn_at IS NULL
            "#,
        )
        .bind(consent_id)
        .bind(tenant_id)
        .execute(&self.pool)
        .await?;

        Ok(result.rows_affected() > 0)
    }

    /// Check whether an entity has active consent for a given type.
    #[allow(dead_code)]
    pub async fn has_active_consent(
        &self,
        tenant_id: Uuid,
        entity_id: Uuid,
        consent_type: &ConsentType,
    ) -> Result<bool> {
        let exists: bool = sqlx::query_scalar(
            r#"
            SELECT EXISTS (
                SELECT 1 FROM core_mdm.consent_records
                WHERE tenant_id    = $1
                  AND entity_id    = $2
                  AND consent_type = $3
                  AND consent_given  = true
                  AND withdrawn_at IS NULL
                  AND (expires_at  IS NULL OR expires_at > NOW())
            )
            "#,
        )
        .bind(tenant_id)
        .bind(entity_id)
        .bind(consent_type.to_string())
        .fetch_one(&self.pool)
        .await?;

        Ok(exists)
    }
}

// ── Internal SQLx row type ────────────────────────────────────────────────────

#[derive(sqlx::FromRow)]
struct ConsentRow {
    consent_id:    Uuid,
    tenant_id:     Uuid,
    entity_id:     Uuid,
    consent_type:  String,
    legal_basis:   String,
    consent_given: bool,
    purpose:       Option<String>,
    source:        Option<String>,
    granted_at:    Option<DateTime<Utc>>,
    withdrawn_at:  Option<DateTime<Utc>>,
    expires_at:    Option<DateTime<Utc>>,
    recorded_by:   Option<String>,
    metadata:      serde_json::Value,
    created_at:    DateTime<Utc>,
    updated_at:    DateTime<Utc>,
}

impl From<ConsentRow> for ConsentRecord {
    fn from(r: ConsentRow) -> Self {
        Self {
            consent_id:    r.consent_id,
            tenant_id:     r.tenant_id,
            entity_id:     r.entity_id,
            consent_type:  r.consent_type.parse().unwrap_or(ConsentType::Processing),
            legal_basis:   r.legal_basis,
            consent_given: r.consent_given,
            purpose:       r.purpose,
            source:        r.source,
            granted_at:    r.granted_at,
            withdrawn_at:  r.withdrawn_at,
            expires_at:    r.expires_at,
            recorded_by:   r.recorded_by,
            metadata:      r.metadata,
            created_at:    r.created_at,
            updated_at:    r.updated_at,
        }
    }
}
