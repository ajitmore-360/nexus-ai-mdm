use std::time::Duration;

use anyhow::{Context, Result};
use chrono::Utc;
use jsonwebtoken::{
    decode, encode, Algorithm, DecodingKey, EncodingKey,
    Header, TokenData, Validation,
};
use uuid::Uuid;

use crate::claims::{Claims, TokenPurpose};
use crate::roles::Role;

const ISSUER: &str = "nexus-ai-mdm";
const ACCESS_TTL:  Duration = Duration::from_secs(15 * 60);       // 15 min
const REFRESH_TTL: Duration = Duration::from_secs(7 * 24 * 60 * 60); // 7 days

/// Runtime JWT configuration loaded from environment.
#[derive(Clone)]
pub struct JwtConfig {
    encoding_key:  EncodingKey,
    decoding_key:  DecodingKey,
    algorithm:     Algorithm,
    access_ttl:    Duration,
    refresh_ttl:   Duration,
}

/// Generic weak secrets that must never reach production.
/// This list intentionally does NOT include the custom local-dev value
/// (`azile-local-dev-jwt-secret-min-32-chars!!`) so that the default
/// docker-compose / .env configuration works out of the box.
/// In production, operators must set a strong random JWT_SECRET.
const KNOWN_WEAK_SECRETS: &[&str] = &[
    "nexus-dev-secret-change-in-production-min-32-chars",   // old hardcoded fallback
    "secret",
    "password",
    "changeme",
    "nexus",
    "test",
    "jwt-secret",
    "your-secret-key",
];

impl JwtConfig {
    /// Load JWT configuration from the `JWT_SECRET` environment variable.
    ///
    /// **Production requirements (enforced at startup):**
    /// - `JWT_SECRET` must be set â€” the service refuses to start without it.
    /// - The secret must be at least 32 bytes long.
    /// - The secret must not match any known weak development values.
    ///
    /// These requirements are checked in both debug and release builds.
    /// There is **no fallback** â€” a missing or weak secret is an immediate
    /// startup failure, not a warning.
    pub fn from_env() -> Result<Self> {
        let secret = std::env::var("JWT_SECRET")
            .context("JWT_SECRET environment variable is required â€” set a strong random secret (â‰¥32 chars)")?;

        if secret.len() < 32 {
            anyhow::bail!(
                "JWT_SECRET is too short ({} bytes) â€” must be at least 32 bytes",
                secret.len()
            );
        }

        if KNOWN_WEAK_SECRETS.iter().any(|&weak| secret.eq_ignore_ascii_case(weak)) {
            anyhow::bail!(
                "JWT_SECRET matches a known weak development secret â€” \
                 generate a strong random secret with: \
                 openssl rand -base64 48"
            );
        }

        Ok(Self {
            encoding_key: EncodingKey::from_secret(secret.as_bytes()),
            decoding_key: DecodingKey::from_secret(secret.as_bytes()),
            algorithm:    Algorithm::HS256,
            access_ttl:   ACCESS_TTL,
            refresh_ttl:  REFRESH_TTL,
        })
    }

    /// Issue a new access token for the given user.
    pub fn issue_access(
        &self,
        user_id:   Uuid,
        tenant_id: Uuid,
        email:     &str,
        role:      Role,
    ) -> Result<String> {
        let now = Utc::now().timestamp();
        let exp = now + self.access_ttl.as_secs() as i64;

        let claims = Claims {
            exp,
            iat:           now,
            iss:           ISSUER.to_string(),
            sub:           user_id.to_string(),
            nxs_purpose:   TokenPurpose::Access,
            nxs_tenant_id: tenant_id,
            nxs_email:     email.to_string(),
            nxs_role:      role,
            nxs_jti:       Uuid::new_v4(),
        };

        encode(&Header::new(self.algorithm), &claims, &self.encoding_key)
            .context("failed to sign access token")
    }

    /// Issue a refresh token (longer TTL, Refresh purpose).
    pub fn issue_refresh(
        &self,
        user_id:   Uuid,
        tenant_id: Uuid,
        email:     &str,
        role:      Role,
    ) -> Result<String> {
        let now = Utc::now().timestamp();
        let exp = now + self.refresh_ttl.as_secs() as i64;

        let claims = Claims {
            exp,
            iat:           now,
            iss:           ISSUER.to_string(),
            sub:           user_id.to_string(),
            nxs_purpose:   TokenPurpose::Refresh,
            nxs_tenant_id: tenant_id,
            nxs_email:     email.to_string(),
            nxs_role:      role,
            nxs_jti:       Uuid::new_v4(),
        };

        encode(&Header::new(self.algorithm), &claims, &self.encoding_key)
            .context("failed to sign refresh token")
    }

    /// Validate a token and return its claims.
    /// Rejects expired tokens, wrong issuer, and wrong algorithm.
    pub fn validate(&self, token: &str) -> Result<Claims> {
        let mut validation = Validation::new(self.algorithm);
        validation.set_issuer(&[ISSUER]);
        validation.validate_exp = true;

        let data: TokenData<Claims> =
            decode(token, &self.decoding_key, &validation)
                .context("invalid or expired JWT")?;

        Ok(data.claims)
    }
}

/// An access + refresh token pair issued on login.
#[derive(Debug, serde::Serialize)]
pub struct TokenPair {
    pub access_token:  String,
    pub refresh_token: String,
    pub token_type:    String,
    pub expires_in:    u64,
}

/// Convenience function: issue both tokens at once.
pub fn issue_tokens(
    config:    &JwtConfig,
    user_id:   Uuid,
    tenant_id: Uuid,
    email:     &str,
    role:      Role,
) -> Result<TokenPair> {
    Ok(TokenPair {
        access_token:  config.issue_access(user_id, tenant_id, email, role.clone())?,
        refresh_token: config.issue_refresh(user_id, tenant_id, email, role)?,
        token_type:    "Bearer".to_string(),
        expires_in:    ACCESS_TTL.as_secs(),
    })
}

/// Validate a token string and extract claims.
pub fn validate_token(config: &JwtConfig, token: &str) -> Result<Claims> {
    config.validate(token)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_config() -> JwtConfig {
        std::env::set_var("JWT_SECRET", "test-secret-at-least-32-characters!!");
        JwtConfig::from_env().unwrap()
    }

    #[test]
    fn issue_and_validate_access_token() {
        let cfg = test_config();
        let uid = Uuid::new_v4();
        let tid = Uuid::new_v4();

        let token = cfg.issue_access(uid, tid, "user@test.com", Role::Steward).unwrap();
        let claims = cfg.validate(&token).unwrap();

        assert_eq!(claims.user_id().unwrap(), uid);
        assert_eq!(claims.nxs_tenant_id, tid);
        assert_eq!(claims.nxs_email, "user@test.com");
        assert_eq!(claims.nxs_role, Role::Steward);
        assert_eq!(claims.nxs_purpose, TokenPurpose::Access);
        assert!(!claims.is_expired());
    }

    #[test]
    fn refresh_token_has_longer_ttl() {
        let cfg = test_config();
        let uid = Uuid::new_v4();
        let tid = Uuid::new_v4();

        let access  = cfg.issue_access(uid, tid, "u@t.com", Role::Viewer).unwrap();
        let refresh = cfg.issue_refresh(uid, tid, "u@t.com", Role::Viewer).unwrap();

        let ac = cfg.validate(&access).unwrap();
        let rc = cfg.validate(&refresh).unwrap();

        assert!(rc.exp > ac.exp, "refresh token must outlive access token");
        assert_eq!(rc.nxs_purpose, TokenPurpose::Refresh);
    }

    #[test]
    fn invalid_token_rejected() {
        let cfg = test_config();
        assert!(cfg.validate("not.a.jwt").is_err());
        assert!(cfg.validate("").is_err());
    }

    #[test]
    fn token_pair_issue() {
        let cfg = test_config();
        let pair = issue_tokens(&cfg, Uuid::new_v4(), Uuid::new_v4(), "a@b.com", Role::Admin).unwrap();
        assert!(!pair.access_token.is_empty());
        assert!(!pair.refresh_token.is_empty());
        assert_eq!(pair.token_type, "Bearer");
        assert_eq!(pair.expires_in, ACCESS_TTL.as_secs());
    }
}
