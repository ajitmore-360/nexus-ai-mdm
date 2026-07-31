-- =============================================================================
-- Migration: 0024_sso_scim
--
-- Adds is_active + auth_provider to identities for SCIM/SAML support.

ALTER TABLE core_mdm.identities
    ADD COLUMN IF NOT EXISTS is_active     BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS auth_provider TEXT    NOT NULL DEFAULT 'password';

COMMENT ON COLUMN core_mdm.identities.is_active
    IS 'Set to false by SCIM to deactivate users without deleting them.';
COMMENT ON COLUMN core_mdm.identities.auth_provider
    IS 'password | saml | oidc | scim — tracks how this identity was provisioned.';

-- =============================================================================
-- Original: 0024_sso_scim
--
-- Adds enterprise SSO (SAML 2.0) and SCIM 2.0 provisioning tables.
--
--   core_mdm.sso_configurations  — per-tenant SAML / OIDC IdP config
--   core_mdm.saml_sessions       — in-flight SAML state (RelayState → redirect)
--   core_mdm.scim_tokens         — bearer tokens for SCIM 2.0 provisioning
-- =============================================================================

-- ── 1. SSO / IdP configuration ───────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.sso_configurations (
    sso_config_id   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL REFERENCES core_mdm.tenants(tenant_id) ON DELETE CASCADE,
    provider_type   TEXT        NOT NULL CHECK (provider_type IN ('saml', 'oidc')),
    is_enabled      BOOLEAN     NOT NULL DEFAULT false,

    -- SAML 2.0 fields
    idp_entity_id   TEXT,                   -- e.g. https://accounts.google.com/o/saml2/...
    idp_sso_url     TEXT,                   -- IdP SSO redirect binding URL
    idp_slo_url     TEXT,                   -- IdP single-logout URL (optional)
    idp_certificate TEXT,                   -- PEM-encoded X.509 cert from IdP metadata

    -- SP config (auto-derived from tenant, override if needed)
    sp_entity_id    TEXT,                   -- our SP entity ID (URL)
    sp_acs_url      TEXT,                   -- our assertion consumer URL
    sp_name_id_format TEXT NOT NULL DEFAULT 'urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress',

    -- OIDC fields (for future per-tenant OIDC)
    oidc_client_id          TEXT,
    oidc_client_secret_enc  TEXT,           -- AES-256-GCM encrypted
    oidc_discovery_url      TEXT,
    oidc_scopes             TEXT[] NOT NULL DEFAULT ARRAY['openid', 'email', 'profile'],

    -- Attribute → identity field mapping
    attribute_mappings JSONB NOT NULL DEFAULT '{"email": "NameID", "name": "displayName", "groups": "memberOf"}',

    -- Provisioning policy
    default_role    TEXT        NOT NULL DEFAULT 'steward',
    auto_provision  BOOLEAN     NOT NULL DEFAULT true,   -- create identity if not found
    auto_deprovision BOOLEAN    NOT NULL DEFAULT false,  -- deactivate if removed from IdP group

    -- JIT group → role mapping: { "MDM_Admins": "admin", "MDM_Stewards": "steward" }
    group_role_mappings JSONB   NOT NULL DEFAULT '{}',

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by      UUID,

    UNIQUE(tenant_id, provider_type)
);

CREATE INDEX IF NOT EXISTS idx_sso_config_tenant
    ON core_mdm.sso_configurations (tenant_id);

-- Enable RLS (admin-only access enforced in application layer via tenant_id check)
ALTER TABLE core_mdm.sso_configurations ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON core_mdm.sso_configurations
    USING (tenant_id = current_setting('app.current_tenant', true)::uuid);

-- ── 2. In-flight SAML sessions (RelayState → return URL mapping) ─────────────

CREATE TABLE IF NOT EXISTS core_mdm.saml_sessions (
    session_id      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    relay_state     TEXT        NOT NULL UNIQUE,
    tenant_id       UUID        NOT NULL REFERENCES core_mdm.tenants(tenant_id) ON DELETE CASCADE,
    redirect_url    TEXT        NOT NULL DEFAULT '/dashboard',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at      TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '10 minutes'
);

CREATE INDEX IF NOT EXISTS idx_saml_sessions_relay
    ON core_mdm.saml_sessions (relay_state);
CREATE INDEX IF NOT EXISTS idx_saml_sessions_expires
    ON core_mdm.saml_sessions (expires_at);

-- Auto-clean expired sessions via a partial index hint
-- (actual cleanup triggered by periodic DELETE in application)

-- ── 3. SCIM 2.0 bearer tokens ─────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.scim_tokens (
    token_id        UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL REFERENCES core_mdm.tenants(tenant_id) ON DELETE CASCADE,
    -- SHA-256 hash of the raw token; the raw token is only shown once at creation
    token_hash      TEXT        NOT NULL UNIQUE,
    description     TEXT        NOT NULL DEFAULT '',
    created_by      UUID        REFERENCES core_mdm.identities(identity_id) ON DELETE SET NULL,
    last_used_at    TIMESTAMPTZ,
    expires_at      TIMESTAMPTZ,
    is_active       BOOLEAN     NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_scim_tokens_tenant
    ON core_mdm.scim_tokens (tenant_id, is_active);
CREATE INDEX IF NOT EXISTS idx_scim_tokens_hash
    ON core_mdm.scim_tokens (token_hash);
