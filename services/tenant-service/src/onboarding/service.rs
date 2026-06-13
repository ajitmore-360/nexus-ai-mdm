use anyhow::Result;
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use tracing::{info, instrument};
use uuid::Uuid;

use nexus_auth::hash_password;

/// Complete request to onboard a new organisation.
#[derive(Debug, Deserialize)]
pub struct OnboardOrganizationRequest {
    // ── Organisation identity ────────────────────────────────────────────────
    pub tenant_code:    String,     // URL-safe slug: "acme-corp"
    pub display_name:   String,     // "Acme Corporation"
    pub legal_name:     Option<String>,
    pub tax_id:         Option<String>,
    pub industry:       Option<String>,
    pub country:        Option<String>,
    pub timezone:       Option<String>,
    pub currency:       Option<String>,
    pub logo_url:       Option<String>,
    pub primary_color:  Option<String>,

    // ── Admin user ───────────────────────────────────────────────────────────
    pub admin_email:       String,
    pub admin_password:    String,
    pub admin_name:        String,

    // ── Entity types to activate ────────────────────────────────────────────
    /// Which entity types this tenant wants active.
    /// If empty, all standard types are activated.
    pub entity_types:      Option<Vec<String>>,

    // ── License ─────────────────────────────────────────────────────────────
    /// License JWT to bind to this tenant on creation.
    pub license_token:     Option<String>,
}

#[derive(Debug, Serialize)]
pub struct OnboardingResult {
    pub tenant_id:    Uuid,
    pub admin_user_id: Uuid,
    pub tenant_code:  String,
    pub message:      String,
}

/// Onboard a new organisation in a single atomic operation:
///
/// 1. Create tenant record
/// 2. Create extended tenant profile
/// 3. Create admin user with hashed password
/// 4. Initialise number sequences for each entity type
/// 5. Optionally import + bind a license
#[instrument(skip(pool, req))]
pub async fn onboard_organization(
    pool: &PgPool,
    req:  OnboardOrganizationRequest,
) -> Result<OnboardingResult> {

    // Check tenant_code uniqueness
    let exists: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM core_mdm.tenants WHERE tenant_code = $1)",
    )
    .bind(&req.tenant_code)
    .fetch_one(pool)
    .await?;

    if exists {
        anyhow::bail!("tenant_code '{}' is already taken", req.tenant_code);
    }

    let tenant_id  = Uuid::new_v4();
    let admin_id   = Uuid::new_v4();
    let pw_hash    = hash_password(&req.admin_password)?;

    let mut tx = pool.begin().await?;

    // ── 1. Create tenant ─────────────────────────────────────────────────────
    sqlx::query(
        r#"
        INSERT INTO core_mdm.tenants (
            tenant_id, tenant_code, display_name, plan, status,
            settings, features, created_at, updated_at
        ) VALUES (
            $1,$2,$3,'enterprise','active','{}',
            '{"ai_matching":true,"rag_copilot":true,"vector_blocking":true}',
            NOW(),NOW()
        )
        "#,
    )
    .bind(tenant_id)
    .bind(&req.tenant_code)
    .bind(&req.display_name)
    .execute(&mut *tx)
    .await?;

    // ── 2. Create tenant profile ─────────────────────────────────────────────
    sqlx::query(
        r#"
        INSERT INTO core_mdm.tenant_profiles (
            tenant_id, legal_name, tax_id, industry, country,
            timezone, currency, logo_url, primary_color,
            admin_email, onboarding_status, onboarding_step
        ) VALUES (
            $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,'in_progress',1
        )
        "#,
    )
    .bind(tenant_id)
    .bind(req.legal_name.as_deref().unwrap_or(&req.display_name))
    .bind(req.tax_id.as_deref())
    .bind(req.industry.as_deref())
    .bind(req.country.as_deref().unwrap_or("US"))
    .bind(req.timezone.as_deref().unwrap_or("UTC"))
    .bind(req.currency.as_deref().unwrap_or("USD"))
    .bind(req.logo_url.as_deref())
    .bind(req.primary_color.as_deref().unwrap_or("#00C896"))
    .bind(&req.admin_email)
    .execute(&mut *tx)
    .await?;

    // ── 3. Create admin user ─────────────────────────────────────────────────
    sqlx::query(
        r#"
        INSERT INTO core_mdm.users (
            user_id, tenant_id, email, display_name, role,
            password_hash, status, is_verified, created_at
        ) VALUES (
            $1,$2,$3,$4,'admin',$5,'active',TRUE,NOW()
        )
        "#,
    )
    .bind(admin_id)
    .bind(tenant_id)
    .bind(&req.admin_email)
    .bind(&req.admin_name)
    .bind(&pw_hash)
    .execute(&mut *tx)
    .await?;

    // ── 4. Initialise number sequences ───────────────────────────────────────
    let entity_types_to_init: Vec<(&str, &str)> = vec![
        ("Customer",     "CUST"),
        ("Vendor",       "VEND"),
        ("Product",      "PROD"),
        ("Material",     "MATL"),
        ("Account",      "ACCT"),
        ("Employee",     "EMP"),
        ("Location",     "LOC"),
        ("Organization", "ORG"),
        ("Asset",        "ASST"),
    ];

    // Only init the requested entity types, or all if none specified
    let active_types: Vec<&str> = match &req.entity_types {
        Some(list) if !list.is_empty() => {
            entity_types_to_init.iter()
                .filter(|(et, _)| list.iter().any(|r| r.eq_ignore_ascii_case(et)))
                .map(|(et, _)| *et)
                .collect()
        }
        _ => entity_types_to_init.iter().map(|(et, _)| *et).collect(),
    };

    for (entity_type, prefix) in &entity_types_to_init {
        if active_types.contains(entity_type) {
            sqlx::query(
                "INSERT INTO core_mdm.entity_sequences (tenant_id, entity_type, prefix) \
                 VALUES ($1, $2, $3) ON CONFLICT DO NOTHING",
            )
            .bind(tenant_id)
            .bind(entity_type)
            .bind(prefix)
            .execute(&mut *tx)
            .await?;
        }
    }

    // ── 5. Mark onboarding complete ──────────────────────────────────────────
    sqlx::query(
        "UPDATE core_mdm.tenant_profiles \
         SET onboarding_status='completed', onboarding_step=5, onboarded_at=NOW() \
         WHERE tenant_id=$1",
    )
    .bind(tenant_id)
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;

    // ── 6. Import license if provided (outside transaction — idempotent) ─────
    if let Some(license_token) = &req.license_token {
        match crate::license::import_license(pool, license_token, Some(admin_id)).await {
            Ok(lid) => info!(license_id=%lid, tenant_id=%tenant_id, "license bound to new tenant"),
            Err(e)  => tracing::warn!(error=%e, "license import failed — tenant created without license"),
        }
    }

    info!(
        tenant_id=%tenant_id,
        tenant_code=%req.tenant_code,
        admin_id=%admin_id,
        "organisation onboarded successfully"
    );

    Ok(OnboardingResult {
        tenant_id,
        admin_user_id: admin_id,
        tenant_code:   req.tenant_code,
        message:       format!(
            "Organisation '{}' onboarded. Admin: {}. {} entity type(s) activated.",
            req.display_name, req.admin_email, active_types.len()
        ),
    })
}
