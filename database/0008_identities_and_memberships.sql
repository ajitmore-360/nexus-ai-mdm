-- =============================================================================
-- Migration: 0008_identities_and_memberships
--
-- The original 0003_production_tables migration created core_mdm.users (a
-- per-tenant user table with no password_hash column).  The auth system was
-- later redesigned to split identity from tenant membership:
--
--   core_mdm.identities         — who you are (global, email UNIQUE)
--   core_mdm.tenant_memberships — what role you have in which tenant
--
-- This migration:
--   1. Creates core_mdm.identities and core_mdm.tenant_memberships.
--   2. Migrates existing rows from core_mdm.users into the new tables.
--   3. Adds password_hash to identities (was never in the old users table).
--   4. Adds additional columns to core_mdm.tenants expected by the codebase.
--   5. Seeds a development admin (admin@nexus.ai / Admin@123) for the
--      default tenant so the UI works on a fresh install.
-- =============================================================================

-- ── 1. Add missing columns to core_mdm.tenants expected by tenant-service ────

ALTER TABLE core_mdm.tenants
    ADD COLUMN IF NOT EXISTS subscription_plan TEXT,
    ADD COLUMN IF NOT EXISTS tenant_name       TEXT,
    ADD COLUMN IF NOT EXISTS metadata          JSONB NOT NULL DEFAULT '{}';

-- Back-fill legacy aliases so existing rows stay consistent
UPDATE core_mdm.tenants SET tenant_name       = display_name WHERE tenant_name       IS NULL;
UPDATE core_mdm.tenants SET subscription_plan = plan         WHERE subscription_plan IS NULL;

-- ── 2. Create core_mdm.identities ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.identities (
    identity_id   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    email         CITEXT      NOT NULL UNIQUE,
    password_hash TEXT,
    display_name  TEXT        NOT NULL DEFAULT '',
    avatar_url    TEXT,
    is_verified   BOOLEAN     NOT NULL DEFAULT false,
    verified_at   TIMESTAMPTZ,
    last_login_at TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_identities_email ON core_mdm.identities (email);

-- ── 3. Create core_mdm.tenant_memberships ─────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.tenant_memberships (
    membership_id UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    identity_id   UUID        NOT NULL REFERENCES core_mdm.identities(identity_id) ON DELETE CASCADE,
    tenant_id     UUID        NOT NULL REFERENCES core_mdm.tenants(tenant_id)      ON DELETE CASCADE,
    role          TEXT        NOT NULL DEFAULT 'viewer',
    status        TEXT        NOT NULL DEFAULT 'active',
    preferences   JSONB       NOT NULL DEFAULT '{}',
    joined_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ,
    UNIQUE(identity_id, tenant_id)
);

CREATE INDEX IF NOT EXISTS idx_tenant_memberships_tenant
    ON core_mdm.tenant_memberships (tenant_id);
CREATE INDEX IF NOT EXISTS idx_tenant_memberships_identity
    ON core_mdm.tenant_memberships (identity_id);

-- ── 4. Migrate core_mdm.users → identities (one identity per unique email) ───

INSERT INTO core_mdm.identities (
    identity_id, email, display_name, last_login_at, created_at
)
SELECT DISTINCT ON (email)
    user_id,
    email,
    COALESCE(display_name, ''),
    last_login_at,
    created_at
FROM core_mdm.users
ORDER BY email, created_at ASC
ON CONFLICT (email) DO NOTHING;

-- ── 5. Migrate core_mdm.users → tenant_memberships ────────────────────────────

INSERT INTO core_mdm.tenant_memberships (
    identity_id, tenant_id, role, status, joined_at
)
SELECT
    (SELECT i.identity_id FROM core_mdm.identities i WHERE i.email = u.email),
    u.tenant_id,
    COALESCE(u.role, 'viewer'),
    COALESCE(u.status, 'active'),
    u.created_at
FROM core_mdm.users u
WHERE u.email IS NOT NULL
ON CONFLICT (identity_id, tenant_id) DO NOTHING;

-- ── 6. Seed dev admin identity ────────────────────────────────────────────────
-- Email:    admin@nexus.ai
-- Password: Admin@123  (bcrypt via pgcrypto extension)

INSERT INTO core_mdm.identities (
    identity_id,
    email,
    password_hash,
    display_name,
    is_verified,
    verified_at
)
VALUES (
    '00000000-0000-0000-0000-000000000010',
    'admin@nexus.ai',
    crypt('Admin@123', gen_salt('bf')),
    'System Admin',
    true,
    NOW()
)
ON CONFLICT (email) DO NOTHING;

-- ── 7. Seed admin membership for the default tenant ───────────────────────────
-- The default tenant (00000000-0000-0000-0000-000000000001) was seeded in 0003.

INSERT INTO core_mdm.tenant_memberships (
    identity_id,
    tenant_id,
    role,
    status
)
VALUES (
    '00000000-0000-0000-0000-000000000010',
    '00000000-0000-0000-0000-000000000001',
    'super_admin',
    'active'
)
ON CONFLICT (identity_id, tenant_id) DO NOTHING;

-- ── 8. Create user_invitations table (needed by invite_user handler) ──────────

CREATE TABLE IF NOT EXISTS core_mdm.user_invitations (
    invitation_id UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id     UUID        NOT NULL REFERENCES core_mdm.tenants(tenant_id) ON DELETE CASCADE,
    identity_id   UUID        REFERENCES core_mdm.identities(identity_id) ON DELETE SET NULL,
    email         CITEXT      NOT NULL,
    role          TEXT        NOT NULL DEFAULT 'steward',
    token         TEXT        NOT NULL UNIQUE,
    status        TEXT        NOT NULL DEFAULT 'pending', -- pending | accepted | expired | revoked
    invited_by    UUID,
    expires_at    TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '7 days',
    accepted_at   TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_invitations_token  ON core_mdm.user_invitations (token);
CREATE INDEX IF NOT EXISTS idx_invitations_tenant  ON core_mdm.user_invitations (tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_invitations_email   ON core_mdm.user_invitations (email, tenant_id);

-- ── 9. Password resets ────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.password_resets (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    identity_id UUID        NOT NULL REFERENCES core_mdm.identities(identity_id) ON DELETE CASCADE,
    tenant_id   UUID        NOT NULL,
    token       TEXT        NOT NULL UNIQUE,
    expires_at  TIMESTAMPTZ NOT NULL,
    used_at     TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_password_resets_identity ON core_mdm.password_resets (identity_id);
CREATE INDEX IF NOT EXISTS idx_password_resets_token    ON core_mdm.password_resets (token);

-- ── 10. Tenant licenses (used by mdm-core /internal/license endpoint) ─────────

CREATE TABLE IF NOT EXISTS core_mdm.tenant_licenses (
    license_id    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id     UUID        NOT NULL REFERENCES core_mdm.tenants(tenant_id) ON DELETE CASCADE,
    tier          TEXT        NOT NULL DEFAULT 'enterprise'
                              CHECK (tier IN ('trial', 'essentials', 'professional', 'enterprise')),
    status        TEXT        NOT NULL DEFAULT 'active'
                              CHECK (status IN ('active', 'suspended', 'expired', 'trial')),
    -- Limits: -1 = unlimited (enterprise)
    max_domains   INTEGER     NOT NULL DEFAULT -1,
    max_records   BIGINT      NOT NULL DEFAULT -1,
    max_stewards  INTEGER     NOT NULL DEFAULT -1,
    -- Per-feature flags consumed by the api-gateway license_guard
    features      JSONB       NOT NULL DEFAULT '{}',
    license_key   TEXT        UNIQUE,
    starts_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at    TIMESTAMPTZ,
    trial_ends_at TIMESTAMPTZ,
    notes         TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(tenant_id)
);

CREATE INDEX IF NOT EXISTS idx_tenant_licenses_tenant ON core_mdm.tenant_licenses (tenant_id);
CREATE INDEX IF NOT EXISTS idx_tenant_licenses_status ON core_mdm.tenant_licenses (status);

-- Seed enterprise license for the default tenant so the license_guard passes
INSERT INTO core_mdm.tenant_licenses (
    tenant_id,
    tier,
    status,
    max_domains,
    max_records,
    max_stewards,
    features,
    notes
)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'enterprise',
    'active',
    -1,
    -1,
    -1,
    '{
        "matching_semantic": true,
        "ai_copilot":        true,
        "relationships":     true,
        "domain_policies":   true,
        "data_quality":      true,
        "analytics":         true,
        "governance":        true,
        "distribution":      true,
        "white_label":       true,
        "priority_support":  true
    }'::jsonb,
    'Default dev tenant — enterprise tier, all features enabled'
)
ON CONFLICT (tenant_id) DO NOTHING;
