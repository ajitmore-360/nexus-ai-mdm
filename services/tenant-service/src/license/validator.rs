use anyhow::{anyhow, Context, Result};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// License tier â€” determines which features are unlocked.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub enum LicenseTier {
    Community,
    Professional,
    Enterprise,
    Oem,
}

impl std::fmt::Display for LicenseTier {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let s = match self {
            LicenseTier::Community    => "Community",
            LicenseTier::Professional => "Professional",
            LicenseTier::Enterprise   => "Enterprise",
            LicenseTier::Oem          => "OEM",
        };
        write!(f, "{}", s)
    }
}

/// License limits.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LicenseLimits {
    pub max_tenants:              Option<u32>,
    pub max_entities_per_tenant:  Option<u64>,
    pub max_users_per_tenant:     Option<u32>,
    pub max_source_systems:       Option<u32>,
    pub max_api_calls_per_day:    Option<u64>,
}

/// Decoded claims from a signed license JWT.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LicenseClaims {
    // Standard JWT claims
    pub jti: String,            // license_id
    pub iss: String,            // "azile-mdm-vendor"
    pub sub: String,            // organization name
    pub iat: i64,
    pub exp: Option<i64>,       // None = perpetual

    // Nexus-specific claims
    pub tier:     LicenseTier,
    pub features: Vec<String>,
    pub limits:   LicenseLimits,
    pub is_trial: bool,
}

/// Nexus MDM vendor public key for license JWT verification.
/// In production this is the vendor's RSA-2048 or Ed25519 public key.
/// For development we use HS256 with a well-known key.
///
/// IMPORTANT: In a real deployment, replace this with the actual vendor public key.
/// The private key is held only by the Nexus MDM vendor for signing licenses.
const VENDOR_LICENSE_SECRET: &str =
    "azile-mdm-vendor-license-signing-key-v1-do-not-share";

/// Validate and decode a license JWT token.
///
/// Returns the decoded `LicenseClaims` if the token is valid.
/// Rejects: invalid signature, expired tokens, wrong issuer.
pub fn validate_license_token(token: &str) -> Result<LicenseClaims> {
    use jsonwebtoken::{decode, Algorithm, DecodingKey, Validation};

    let key = DecodingKey::from_secret(VENDOR_LICENSE_SECRET.as_bytes());
    let mut validation = Validation::new(Algorithm::HS256);
    validation.set_issuer(&["azile-mdm-vendor"]);
    // exp is optional â€” perpetual licenses have no expiry claim.
    // Disable both the automatic exp validation AND the required-claim check.
    validation.validate_exp = false;
    validation.required_spec_claims = {
        let mut s = std::collections::HashSet::new();
        s.insert("iss".to_string()); // issuer is always required
        s
    };

    let token_data = decode::<LicenseClaims>(token, &key, &validation)
        .context("license token signature is invalid or has been tampered with")?;

    let claims = token_data.claims;

    // Manual expiry check (since we disabled automatic)
    if let Some(exp) = claims.exp {
        if exp < Utc::now().timestamp() {
            return Err(anyhow!(
                "license expired on {}",
                chrono::DateTime::from_timestamp(exp, 0)
                    .map(|d| d.to_rfc3339())
                    .unwrap_or_else(|| exp.to_string())
            ));
        }
    }

    Ok(claims)
}

/// Generate a development/trial license token for testing.
/// This should only be called by vendor tooling, not by the platform itself.
pub fn generate_dev_license(
    organization: &str,
    tier:         LicenseTier,
    days_valid:   Option<u32>,
) -> Result<String> {
    use jsonwebtoken::{encode, Algorithm, EncodingKey, Header};

    let now = Utc::now().timestamp();
    let exp = days_valid.map(|d| now + d as i64 * 86400);

    let claims = LicenseClaims {
        jti:      Uuid::new_v4().to_string(),
        iss:      "azile-mdm-vendor".to_string(),
        sub:      organization.to_string(),
        iat:      now,
        exp,
        tier:     tier.clone(),
        is_trial: matches!(tier, LicenseTier::Community),
        features: default_features_for_tier(&tier),
        limits:   default_limits_for_tier(&tier),
    };

    let key = EncodingKey::from_secret(VENDOR_LICENSE_SECRET.as_bytes());
    encode(&Header::new(Algorithm::HS256), &claims, &key)
        .context("failed to sign license token")
}

fn default_features_for_tier(tier: &LicenseTier) -> Vec<String> {
    let community = vec![
        "entity_management", "basic_matching", "merge_workflow", "golden_records",
    ];
    let professional = {
        let mut f = community.clone();
        f.extend(["api_access","ai_matching","rag_copilot","data_enrichment",
                   "advanced_search","bulk_ingest","custom_attributes"]);
        f
    };
    let enterprise = {
        let mut f = professional.clone();
        f.extend(["kafka_streaming","multi_tenant","adaptive_ai",
                   "policy_engine","gdpr_compliance","webhooks"]);
        f
    };

    let base = match tier {
        LicenseTier::Community    => community,
        LicenseTier::Professional => professional,
        LicenseTier::Enterprise | LicenseTier::Oem => enterprise,
    };
    base.into_iter().map(str::to_owned).collect()
}

fn default_limits_for_tier(tier: &LicenseTier) -> LicenseLimits {
    match tier {
        LicenseTier::Community => LicenseLimits {
            max_tenants:             Some(1),
            max_entities_per_tenant: Some(100_000),
            max_users_per_tenant:    Some(5),
            max_source_systems:      Some(3),
            max_api_calls_per_day:   Some(10_000),
        },
        LicenseTier::Professional => LicenseLimits {
            max_tenants:             Some(5),
            max_entities_per_tenant: Some(10_000_000),
            max_users_per_tenant:    Some(50),
            max_source_systems:      Some(20),
            max_api_calls_per_day:   Some(1_000_000),
        },
        LicenseTier::Enterprise | LicenseTier::Oem => LicenseLimits {
            max_tenants:             None,
            max_entities_per_tenant: None,
            max_users_per_tenant:    None,
            max_source_systems:      None,
            max_api_calls_per_day:   None,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generate_and_validate_dev_license() {
        let token = generate_dev_license("Test Corp", LicenseTier::Enterprise, Some(365)).unwrap();
        let claims = validate_license_token(&token).unwrap();
        assert_eq!(claims.sub, "Test Corp");
        assert!(claims.features.contains(&"ai_matching".to_string()));
        assert!(claims.limits.max_tenants.is_none());
    }

    #[test]
    fn reject_expired_license() {
        let token = generate_dev_license("Expired Co", LicenseTier::Community, Some(0)).unwrap();
        // 0 days â†’ already expired
        std::thread::sleep(std::time::Duration::from_secs(1));
        assert!(validate_license_token(&token).is_err());
    }

    #[test]
    fn perpetual_license_no_expiry() {
        let token = generate_dev_license("Perpetual Corp", LicenseTier::Enterprise, None).unwrap();
        let claims = validate_license_token(&token).unwrap();
        assert!(claims.exp.is_none());
    }
}
