use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::roles::Role;

/// What the JWT was issued for.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TokenPurpose {
    /// Short-lived access token (15 minutes default).
    Access,
    /// Long-lived refresh token (7 days default).
    Refresh,
    /// Single-use password-reset token (1 hour).
    PasswordReset,
    /// Email verification token (24 hours).
    EmailVerification,
}

/// JWT claims embedded in every Nexus AI MDM token.
///
/// Standard registered claims (`exp`, `iat`, `iss`, `sub`) plus
/// Nexus-specific extension claims prefixed with `nxs_`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Claims {
    // ── Registered claims ─────────────────────────────────────────────────
    /// Expiry timestamp (Unix epoch seconds).
    pub exp: i64,
    /// Issued-at timestamp.
    pub iat: i64,
    /// Issuer — always "nexus-ai-mdm".
    pub iss: String,
    /// Subject — the user_id UUID as a string.
    pub sub: String,

    // ── Nexus extension claims ─────────────────────────────────────────────
    /// Token purpose — access or refresh.
    pub nxs_purpose: TokenPurpose,
    /// Tenant the user belongs to.
    pub nxs_tenant_id: Uuid,
    /// User's display email.
    pub nxs_email: String,
    /// User's platform role.
    pub nxs_role: Role,
    /// Unique token ID (for revocation / jti).
    pub nxs_jti: Uuid,
}

impl Claims {
    pub fn user_id(&self) -> Option<Uuid> {
        Uuid::parse_str(&self.sub).ok()
    }

    pub fn is_expired(&self) -> bool {
        let now = chrono::Utc::now().timestamp();
        self.exp < now
    }
}
