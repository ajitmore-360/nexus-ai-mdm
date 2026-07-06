use anyhow::Result;
use serde::{Deserialize, Serialize};
use sqlx::{PgPool, Row};
use uuid::Uuid;

// ─────────────────────────────────────────────────────────────────────────────
// Domain types
// ─────────────────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TenantBranding {
    pub tenant_id:    Uuid,
    pub product_name: Option<String>,
    pub logo_url:     Option<String>,
    pub favicon_url:  Option<String>,
    pub primary_color: Option<String>,
    pub accent_color:  Option<String>,
    pub support_email: Option<String>,
    pub support_url:   Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpsertBranding {
    pub product_name:  Option<String>,
    pub logo_url:      Option<String>,
    pub favicon_url:   Option<String>,
    pub primary_color: Option<String>,
    pub accent_color:  Option<String>,
    pub support_email: Option<String>,
    pub support_url:   Option<String>,
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

pub struct BrandingService {
    db: PgPool,
}

impl BrandingService {
    pub fn new(db: PgPool) -> Self {
        Self { db }
    }

    pub async fn get(&self, tenant_id: Uuid) -> Result<Option<TenantBranding>> {
        let row = sqlx::query(
            r#"
            SELECT tenant_id, product_name, logo_url, favicon_url,
                   primary_color, accent_color, support_email, support_url
            FROM core_mdm.tenant_branding
            WHERE tenant_id = $1
            "#,
        )
        .bind(tenant_id)
        .fetch_optional(&self.db)
        .await?;

        match row {
            None => Ok(None),
            Some(r) => Ok(Some(TenantBranding {
                tenant_id:     r.try_get("tenant_id")?,
                product_name:  r.try_get("product_name")?,
                logo_url:      r.try_get("logo_url")?,
                favicon_url:   r.try_get("favicon_url")?,
                primary_color: r.try_get("primary_color")?,
                accent_color:  r.try_get("accent_color")?,
                support_email: r.try_get("support_email")?,
                support_url:   r.try_get("support_url")?,
            })),
        }
    }

    pub async fn upsert(
        &self,
        tenant_id: Uuid,
        b: UpsertBranding,
    ) -> Result<TenantBranding> {
        let row = sqlx::query(
            r#"
            INSERT INTO core_mdm.tenant_branding (
                tenant_id, product_name, logo_url, favicon_url,
                primary_color, accent_color, support_email, support_url,
                created_at, updated_at
            ) VALUES (
                $1, $2, $3, $4, $5, $6, $7, $8, NOW(), NOW()
            )
            ON CONFLICT (tenant_id) DO UPDATE SET
                product_name  = EXCLUDED.product_name,
                logo_url      = EXCLUDED.logo_url,
                favicon_url   = EXCLUDED.favicon_url,
                primary_color = EXCLUDED.primary_color,
                accent_color  = EXCLUDED.accent_color,
                support_email = EXCLUDED.support_email,
                support_url   = EXCLUDED.support_url,
                updated_at    = NOW()
            RETURNING tenant_id, product_name, logo_url, favicon_url,
                      primary_color, accent_color, support_email, support_url
            "#,
        )
        .bind(tenant_id)
        .bind(&b.product_name)
        .bind(&b.logo_url)
        .bind(&b.favicon_url)
        .bind(&b.primary_color)
        .bind(&b.accent_color)
        .bind(&b.support_email)
        .bind(&b.support_url)
        .fetch_one(&self.db)
        .await?;

        Ok(TenantBranding {
            tenant_id:     row.try_get("tenant_id")?,
            product_name:  row.try_get("product_name")?,
            logo_url:      row.try_get("logo_url")?,
            favicon_url:   row.try_get("favicon_url")?,
            primary_color: row.try_get("primary_color")?,
            accent_color:  row.try_get("accent_color")?,
            support_email: row.try_get("support_email")?,
            support_url:   row.try_get("support_url")?,
        })
    }

    pub async fn delete(&self, tenant_id: Uuid) -> Result<()> {
        sqlx::query("DELETE FROM core_mdm.tenant_branding WHERE tenant_id = $1")
            .bind(tenant_id)
            .execute(&self.db)
            .await?;
        Ok(())
    }
}
