use anyhow::Result;
use sqlx::{PgPool, Row};
use uuid::Uuid;
use serde_json::json;

//
// ========================================
// STRUCTS
// ========================================
//

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct TenantLicense {
    pub license_id:  Uuid,
    pub tenant_id:   Uuid,
    pub tier:        String,
    pub status:      String,
    pub max_domains: i32,
    pub max_records: i64,
    pub max_stewards: i32,
    pub features:    serde_json::Value,
    pub expires_at:  Option<chrono::DateTime<chrono::Utc>>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct TenantUsage {
    pub golden_records:  i64,
    pub active_domains:  i32,
    pub active_stewards: i32,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct QuotaStatus {
    pub allowed: bool,
    pub current: i64,
    pub limit:   i64,
    pub tier:    String,
}

//
// ========================================
// ESSENTIALS CORE FEATURES
// Features always open regardless of license.
// ========================================
//

const ESSENTIALS_ALWAYS_ON: &[&str] = &[
    "stewardship",
    "lineage",
    "ingest",
    "search",
    "dashboard",
    "audit",
    "data_quality_basic",
];

//
// ========================================
// LICENSE SERVICE
// ========================================
//

pub struct LicenseService {
    db: PgPool,
}

impl LicenseService {
    pub fn new(db: PgPool) -> Self {
        Self { db }
    }

    /// Fetch the active license for a tenant.
    pub async fn get_license(
        &self,
        tenant_id: Uuid,
    ) -> Result<Option<TenantLicense>> {
        let row = sqlx::query(
            r#"
            SELECT
                license_id,
                tenant_id,
                tier,
                status,
                max_domains,
                max_records,
                max_stewards,
                features,
                expires_at
            FROM core_mdm.tenant_licenses
            WHERE tenant_id = $1
            "#,
        )
        .bind(tenant_id)
        .fetch_optional(&self.db)
        .await?;

        match row {
            None => Ok(None),
            Some(r) => Ok(Some(TenantLicense {
                license_id:   r.try_get("license_id")?,
                tenant_id:    r.try_get("tenant_id")?,
                tier:         r.try_get("tier")?,
                status:       r.try_get("status")?,
                max_domains:  r.try_get("max_domains")?,
                max_records:  r.try_get("max_records")?,
                max_stewards: r.try_get("max_stewards")?,
                features:     r.try_get("features")?,
                expires_at:   r.try_get("expires_at")?,
            })),
        }
    }

    /// Fetch current usage counters for a tenant.
    /// Returns zeroed struct when no row exists yet.
    pub async fn get_usage(
        &self,
        tenant_id: Uuid,
    ) -> Result<TenantUsage> {
        let row = sqlx::query(
            r#"
            SELECT
                golden_records,
                active_domains,
                active_stewards
            FROM core_mdm.tenant_usage
            WHERE tenant_id = $1
            "#,
        )
        .bind(tenant_id)
        .fetch_optional(&self.db)
        .await?;

        match row {
            None => Ok(TenantUsage {
                golden_records:  0,
                active_domains:  0,
                active_stewards: 0,
            }),
            Some(r) => Ok(TenantUsage {
                golden_records:  r.try_get("golden_records")?,
                active_domains:  r.try_get("active_domains")?,
                active_stewards: r.try_get("active_stewards")?,
            }),
        }
    }

    /// Returns true when the tenant's license grants access to `feature`.
    /// Essentials core features are always open. Enterprise tier is always open.
    /// No license row defaults to essentials (core features open, premium gated).
    pub async fn has_feature(
        &self,
        tenant_id: Uuid,
        feature:   &str,
    ) -> Result<bool> {
        // Essentials always-on features bypass license check.
        if ESSENTIALS_ALWAYS_ON.contains(&feature) {
            return Ok(true);
        }

        let license = self.get_license(tenant_id).await?;

        match license {
            // No license row → treat as essentials; premium features closed.
            None => Ok(false),
            Some(l) => {
                // Enterprise: everything is unlocked.
                if l.tier == "enterprise" {
                    return Ok(true);
                }
                // Otherwise check the features JSONB map.
                Ok(l.features
                    .get(feature)
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false))
            }
        }
    }

    /// Check whether the tenant is within their golden-record quota.
    pub async fn check_record_quota(
        &self,
        tenant_id: Uuid,
    ) -> Result<QuotaStatus> {
        let (max_records, tier) = match self.get_license(tenant_id).await? {
            Some(l) => (l.max_records, l.tier),
            // Default essentials limits when no license row exists.
            None => (500_000_i64, "essentials".to_string()),
        };

        let usage = self.get_usage(tenant_id).await?;

        if max_records == -1 {
            return Ok(QuotaStatus {
                allowed: true,
                current: usage.golden_records,
                limit:   -1,
                tier,
            });
        }

        Ok(QuotaStatus {
            allowed: usage.golden_records < max_records,
            current: usage.golden_records,
            limit:   max_records,
            tier,
        })
    }

    /// Check whether the tenant is within their active-domain quota.
    pub async fn check_domain_quota(
        &self,
        tenant_id: Uuid,
    ) -> Result<QuotaStatus> {
        let (max_domains, tier) = match self.get_license(tenant_id).await? {
            Some(l) => (l.max_domains as i64, l.tier),
            None => (1_i64, "essentials".to_string()),
        };

        let usage = self.get_usage(tenant_id).await?;

        if max_domains == -1 {
            return Ok(QuotaStatus {
                allowed: true,
                current: usage.active_domains as i64,
                limit:   -1,
                tier,
            });
        }

        Ok(QuotaStatus {
            allowed: (usage.active_domains as i64) < max_domains,
            current: usage.active_domains as i64,
            limit:   max_domains,
            tier,
        })
    }

    /// Check whether the tenant is within their active-steward quota.
    pub async fn check_steward_quota(
        &self,
        tenant_id: Uuid,
    ) -> Result<QuotaStatus> {
        let (max_stewards, tier) = match self.get_license(tenant_id).await? {
            Some(l) => (l.max_stewards as i64, l.tier),
            None => (5_i64, "essentials".to_string()),
        };

        let usage = self.get_usage(tenant_id).await?;

        if max_stewards == -1 {
            return Ok(QuotaStatus {
                allowed: true,
                current: usage.active_stewards as i64,
                limit:   -1,
                tier,
            });
        }

        Ok(QuotaStatus {
            allowed: (usage.active_stewards as i64) < max_stewards,
            current: usage.active_stewards as i64,
            limit:   max_stewards,
            tier,
        })
    }

    /// Create or replace a license for a tenant.
    /// Returns the license_id (new or existing).
    pub async fn upsert_license(
        &self,
        tenant_id: Uuid,
        tier:      &str,
        notes:     Option<&str>,
    ) -> Result<Uuid> {
        let (features, max_domains, max_records, max_stewards): (serde_json::Value, i32, i64, i32) =
            match tier {
                "essentials" => (
                    json!({}),
                    1,
                    500_000,
                    5,
                ),
                "professional" => (
                    json!({
                        "matching_semantic": true,
                        "ai_copilot":        true,
                        "relationships":     true,
                        "domain_policies":   true,
                        "data_quality":      true,
                        "analytics":         true,
                        "governance":        true,
                        "distribution":      true
                    }),
                    5,
                    5_000_000,
                    20,
                ),
                "enterprise" => (
                    json!({
                        "matching_semantic": true,
                        "ai_copilot":        true,
                        "relationships":     true,
                        "domain_policies":   true,
                        "data_quality":      true,
                        "analytics":         true,
                        "governance":        true,
                        "distribution":      true,
                        "white_label":       true
                    }),
                    -1,
                    -1,
                    -1,
                ),
                // trial and any unknown tier
                _ => (
                    json!({}),
                    1,
                    100_000,
                    3,
                ),
            };

        let row = sqlx::query(
            r#"
            INSERT INTO core_mdm.tenant_licenses (
                license_id,
                tenant_id,
                tier,
                status,
                max_domains,
                max_records,
                max_stewards,
                features,
                notes,
                starts_at,
                created_at,
                updated_at
            ) VALUES (
                gen_random_uuid(),
                $1,
                $2,
                'active',
                $3,
                $4,
                $5,
                $6,
                $7,
                NOW(),
                NOW(),
                NOW()
            )
            ON CONFLICT (tenant_id) DO UPDATE SET
                tier         = EXCLUDED.tier,
                status       = 'active',
                max_domains  = EXCLUDED.max_domains,
                max_records  = EXCLUDED.max_records,
                max_stewards = EXCLUDED.max_stewards,
                features     = EXCLUDED.features,
                notes        = EXCLUDED.notes,
                updated_at   = NOW()
            RETURNING license_id
            "#,
        )
        .bind(tenant_id)
        .bind(tier)
        .bind(max_domains)
        .bind(max_records)
        .bind(max_stewards)
        .bind(&features)
        .bind(notes)
        .fetch_one(&self.db)
        .await?;

        Ok(row.try_get("license_id")?)
    }

    /// Request a background recompute of tenant usage counters.
    /// Delegates to the `core_mdm.recompute_tenant_usage` stored procedure.
    pub async fn trigger_usage_recompute(
        &self,
        tenant_id: Uuid,
    ) -> Result<()> {
        sqlx::query("SELECT core_mdm.recompute_tenant_usage($1)")
            .bind(tenant_id)
            .execute(&self.db)
            .await?;

        Ok(())
    }
}
