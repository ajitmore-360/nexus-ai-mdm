-- ============================================================================
-- Migration 002018: Split core_mdm.users → identities + tenant_memberships
--
-- Rationale: this is a true multi-tenant SaaS. One person (one email) must be
-- able to belong to multiple tenants with different roles in each, without
-- having multiple accounts.  The old per-tenant users table made that impossible.
--
-- New model:
--   core_mdm.identities         — who you are (global, email UNIQUE)
--   core_mdm.tenant_memberships — what you can do, in which tenant
-- ============================================================================

-- ── 1. Create identities ──────────────────────────────────────────────────────

CREATE TABLE core_mdm.identities (
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

CREATE INDEX idx_identities_email ON core_mdm.identities (email);

-- ── 2. Create tenant_memberships ──────────────────────────────────────────────

CREATE TABLE core_mdm.tenant_memberships (
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

CREATE INDEX idx_tenant_memberships_tenant   ON core_mdm.tenant_memberships (tenant_id);
CREATE INDEX idx_tenant_memberships_identity ON core_mdm.tenant_memberships (identity_id);

-- ── 3. Migrate users → identities (one row per unique email) ─────────────────
-- DISTINCT ON (email) keeps the earliest-created row's user_id as identity_id,
-- preserving the UUID so all downstream FK lookups still work.

INSERT INTO core_mdm.identities (
    identity_id, email, password_hash, display_name,
    avatar_url, is_verified, verified_at, last_login_at,
    created_at, updated_at
)
SELECT DISTINCT ON (email)
    user_id,
    email,
    password_hash,
    COALESCE(display_name, ''),
    avatar_url,
    COALESCE(is_verified, false),
    verified_at,
    last_login_at,
    created_at,
    updated_at
FROM core_mdm.users
ORDER BY email, created_at ASC
ON CONFLICT (email) DO NOTHING;

-- ── 4. Migrate users → tenant_memberships ────────────────────────────────────

INSERT INTO core_mdm.tenant_memberships (
    identity_id, tenant_id, role, status, preferences, joined_at
)
SELECT
    (SELECT i.identity_id FROM core_mdm.identities i WHERE i.email = u.email),
    u.tenant_id,
    u.role,
    u.status,
    COALESCE(u.preferences, '{}'),
    u.created_at
FROM core_mdm.users u
ON CONFLICT (identity_id, tenant_id) DO NOTHING;

-- ── 5. Update user_invitations → reference identity_id ───────────────────────

ALTER TABLE core_mdm.user_invitations
    DROP CONSTRAINT IF EXISTS user_invitations_user_id_fkey;

ALTER TABLE core_mdm.user_invitations
    ADD COLUMN IF NOT EXISTS identity_id UUID;

-- Map via email: invite's user_id → user's email → canonical identity_id
UPDATE core_mdm.user_invitations inv
   SET identity_id = (
       SELECT i.identity_id
         FROM core_mdm.identities i
         JOIN core_mdm.users u ON u.email = i.email
        WHERE u.user_id = inv.user_id
        LIMIT 1
   );

DELETE FROM core_mdm.user_invitations WHERE identity_id IS NULL;

ALTER TABLE core_mdm.user_invitations
    ALTER COLUMN identity_id SET NOT NULL;

ALTER TABLE core_mdm.user_invitations
    ADD CONSTRAINT user_invitations_identity_id_fkey
    FOREIGN KEY (identity_id) REFERENCES core_mdm.identities(identity_id) ON DELETE CASCADE;

ALTER TABLE core_mdm.user_invitations DROP COLUMN user_id;

-- ── 6. Create password_resets with identity_id ────────────────────────────────
-- The table may not exist on some environments (it was optional in early DDL).
-- We create it fresh with the correct schema; if it already existed with a
-- user_id column we migrate it; if it's already been migrated we do nothing.

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

-- If the table was previously created with user_id, migrate it now.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'core_mdm'
           AND table_name   = 'password_resets'
           AND column_name  = 'user_id'
    ) THEN
        ALTER TABLE core_mdm.password_resets
            DROP CONSTRAINT IF EXISTS password_resets_user_id_fkey;

        ALTER TABLE core_mdm.password_resets
            ADD COLUMN IF NOT EXISTS identity_id UUID;

        UPDATE core_mdm.password_resets pr
           SET identity_id = (
               SELECT i.identity_id
                 FROM core_mdm.identities i
                 JOIN core_mdm.users u ON u.email = i.email
                WHERE u.user_id = pr.user_id
                LIMIT 1
           );

        DELETE FROM core_mdm.password_resets WHERE identity_id IS NULL;

        ALTER TABLE core_mdm.password_resets
            ALTER COLUMN identity_id SET NOT NULL;

        ALTER TABLE core_mdm.password_resets
            ADD CONSTRAINT IF NOT EXISTS password_resets_identity_id_fkey
            FOREIGN KEY (identity_id) REFERENCES core_mdm.identities(identity_id) ON DELETE CASCADE;

        ALTER TABLE core_mdm.password_resets DROP COLUMN user_id;
    END IF;
END $$;

-- ── 7. Drop the old users table ───────────────────────────────────────────────

DROP TABLE core_mdm.users;
