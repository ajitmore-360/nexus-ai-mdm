pub mod validator;

use anyhow::Result;
use sha2::{Digest, Sha256};
use sqlx::{PgPool, Row};
use tracing::{info, instrument};
use uuid::Uuid;

pub use validator::{LicenseTier, validate_license_token, generate_dev_license};

/// Import a signed license token into the platform.
///
/// 1. Validates the JWT signature and expiry
/// 2. Checks for duplicate (idempotent — same license_id is a no-op)
/// 3. Persists to `platform.licenses`
/// 4. Updates the feature registry for runtime enforcement
#[instrument(skip(pool, token))]
pub async fn import_license(pool: &PgPool, token: &str, imported_by: Option<Uuid>) -> Result<Uuid> {
    // Validate first — reject before any DB writes
    let claims = validate_license_token(token)?;

    let license_id = Uuid::parse_str(&claims.jti)
        .unwrap_or_else(|_| Uuid::new_v4());

    // Idempotency — return existing if already imported
    if let Some(existing_id) = sqlx::query_scalar::<_, Uuid>(
        "SELECT license_id FROM platform.licenses WHERE license_token = $1",
    )
    .bind(token)
    .fetch_optional(pool)
    .await?
    {
        info!(license_id=%existing_id, "license already imported — returning existing");
        return Ok(existing_id);
    }

    // Compute checksum for tamper-detection
    let checksum = {
        let mut h = Sha256::new();
        h.update(token.as_bytes());
        format!("{:x}", h.finalize())
    };

    let expires_at = claims.exp.map(|ts| {
        chrono::DateTime::from_timestamp(ts, 0)
            .unwrap_or(chrono::DateTime::UNIX_EPOCH)
    });

    sqlx::query(
        r#"
        INSERT INTO platform.licenses (
            license_id, organization, tier, issued_at, expires_at, is_trial,
            max_tenants, max_entities_per_tenant, max_users_per_tenant,
            max_source_systems, max_api_calls_per_day,
            features, license_token, status, imported_by, checksum
        ) VALUES (
            $1,$2,$3,to_timestamp($4),$5,$6,
            $7,$8,$9,$10,$11,
            $12,$13,'active',$14,$15
        )
        "#,
    )
    .bind(license_id)
    .bind(&claims.sub)
    .bind(claims.tier.to_string())
    .bind(claims.iat)
    .bind(expires_at)
    .bind(claims.is_trial)
    .bind(claims.limits.max_tenants.map(|v| v as i32))
    .bind(claims.limits.max_entities_per_tenant.map(|v| v as i64))
    .bind(claims.limits.max_users_per_tenant.map(|v| v as i32))
    .bind(claims.limits.max_source_systems.map(|v| v as i32))
    .bind(claims.limits.max_api_calls_per_day.map(|v| v as i64))
    .bind(serde_json::to_value(&claims.features)?)
    .bind(token)
    .bind(imported_by)
    .bind(&checksum)
    .execute(pool)
    .await?;

    info!(
        license_id   = %license_id,
        organization = %claims.sub,
        tier         = %claims.tier,
        features     = claims.features.len(),
        "license imported successfully"
    );

    Ok(license_id)
}

/// Check if a specific feature is enabled by the current active license.
pub async fn is_feature_enabled(pool: &PgPool, feature_key: &str) -> bool {
    let result = sqlx::query_scalar::<_, bool>(
        r#"
        SELECT features @> $1::jsonb
        FROM platform.active_license
        LIMIT 1
        "#,
    )
    .bind(serde_json::json!([feature_key]))
    .fetch_optional(pool)
    .await;

    match result {
        Ok(Some(enabled)) => enabled,
        _ => false, // No license = feature disabled
    }
}

/// Get all features enabled by the active license.
pub async fn active_features(pool: &PgPool) -> Vec<String> {
    let result = sqlx::query(
        "SELECT features FROM platform.active_license LIMIT 1",
    )
    .fetch_optional(pool)
    .await;

    match result {
        Ok(Some(row)) => {
            row.try_get::<serde_json::Value, _>("features")
                .ok()
                .and_then(|v| serde_json::from_value::<Vec<String>>(v).ok())
                .unwrap_or_default()
        }
        _ => vec![],
    }
}
