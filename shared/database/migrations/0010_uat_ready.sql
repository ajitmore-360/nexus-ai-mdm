-- =============================================================================
-- Migration 0010: UAT-ready — audit trail, missing tables, ITAdmin seed
--
-- This migration is idempotent (all statements use IF NOT EXISTS / ON CONFLICT).
-- It repairs all known missing tables and seeds the permanent IT-Admin account.
--
-- IT Admin credentials (always available, cannot be removed):
--   Email:    ITAdmin@nexus.ai
--   Password: Itadmin@123
-- =============================================================================

-- ── 1. Audit events (CRITICAL — was causing silent failures on every action) ──

CREATE TABLE IF NOT EXISTS core_mdm.audit_events (
    event_id      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id     UUID        NOT NULL,
    event_type    TEXT        NOT NULL,
    actor_id      UUID,
    resource_type TEXT        NOT NULL,
    resource_id   TEXT        NOT NULL,
    metadata      JSONB       NOT NULL DEFAULT '{}',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_tenant_type
    ON core_mdm.audit_events (tenant_id, event_type, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_resource
    ON core_mdm.audit_events (tenant_id, resource_type, resource_id);

CREATE INDEX IF NOT EXISTS idx_audit_actor
    ON core_mdm.audit_events (tenant_id, actor_id)
    WHERE actor_id IS NOT NULL;

-- Enable RLS — audit events are tenant-scoped
ALTER TABLE core_mdm.audit_events ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'core_mdm'
      AND tablename  = 'audit_events'
      AND policyname = 'audit_events_tenant_policy'
  ) THEN
    EXECUTE $pol$
      CREATE POLICY audit_events_tenant_policy ON core_mdm.audit_events
        USING (tenant_id = (current_setting('app.current_tenant', true))::uuid)
    $pol$;
  END IF;
END $$;

-- ── 2. Lineage schema + table (from migration 0007, not yet applied) ──────────

CREATE SCHEMA IF NOT EXISTS lineage;

CREATE TABLE IF NOT EXISTS lineage.entity_lineage (
    lineage_id        UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id         UUID        NOT NULL,
    source_entity_id  UUID        NOT NULL,
    target_entity_id  UUID        NOT NULL,
    lineage_type      TEXT        NOT NULL,   -- merged_into | enriched | derived | cloned | split
    metadata          JSONB       NOT NULL DEFAULT '{}',
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_lineage_source
    ON lineage.entity_lineage (tenant_id, source_entity_id);

CREATE INDEX IF NOT EXISTS idx_lineage_target
    ON lineage.entity_lineage (tenant_id, target_entity_id);

-- ── 3. Match records (from migration 0007, not yet applied) ───────────────────

CREATE TABLE IF NOT EXISTS core_mdm.match_records (
    match_id      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id     UUID        NOT NULL,
    entity_id_1   UUID        NOT NULL,
    entity_id_2   UUID        NOT NULL,
    match_score   FLOAT4      NOT NULL DEFAULT 0.0,
    status        TEXT        NOT NULL DEFAULT 'Pending',
    reviewed_by   UUID,
    review_notes  TEXT,
    metadata      JSONB       NOT NULL DEFAULT '{}',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, entity_id_1, entity_id_2)
);

CREATE INDEX IF NOT EXISTS idx_match_records_tenant_status
    ON core_mdm.match_records (tenant_id, status);

-- ── 4. Consent records (from migration 0007, not yet applied) ─────────────────

CREATE TABLE IF NOT EXISTS core_mdm.consent_records (
    consent_id    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id     UUID        NOT NULL,
    entity_id     UUID        NOT NULL,
    consent_type  TEXT        NOT NULL,
    legal_basis   TEXT        NOT NULL DEFAULT 'consent',
    consent_given BOOLEAN     NOT NULL,
    purpose       TEXT,
    source        TEXT,
    granted_at    TIMESTAMPTZ,
    withdrawn_at  TIMESTAMPTZ,
    expires_at    TIMESTAMPTZ,
    recorded_by   TEXT,
    metadata      JSONB       NOT NULL DEFAULT '{}',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_consent_entity_tenant
    ON core_mdm.consent_records (entity_id, tenant_id);

-- ── 5. Add protected flag to identities (prevents deleting system accounts) ───

ALTER TABLE core_mdm.identities
    ADD COLUMN IF NOT EXISTS is_protected BOOLEAN NOT NULL DEFAULT false;

-- ── 6. Seed the permanent IT Admin identity (ITAdmin@nexus.ai) ───────────────
-- Password: Itadmin@123
-- This account is marked protected so it cannot be deleted via the admin API.

INSERT INTO core_mdm.identities (
    identity_id, email, password_hash, display_name, is_verified, verified_at, is_protected
)
VALUES (
    '00000000-0000-0000-0000-000000000020',
    'ITAdmin@nexus.ai',
    crypt('Itadmin@123', gen_salt('bf', 12)),
    'IT Admin',
    true,
    NOW(),
    true
)
ON CONFLICT (email) DO UPDATE
    SET password_hash = crypt('Itadmin@123', gen_salt('bf', 12)),
        display_name  = 'IT Admin',
        is_verified   = true,
        is_protected  = true,
        updated_at    = NOW();

-- ── 7. Seed ITAdmin membership in both tenants as super_admin ─────────────────

-- System tenant (00...0001)
INSERT INTO core_mdm.tenant_memberships (identity_id, tenant_id, role, status)
SELECT i.identity_id, '00000000-0000-0000-0000-000000000001'::uuid, 'super_admin', 'active'
FROM   core_mdm.identities i
WHERE  i.email = 'ITAdmin@nexus.ai'
ON CONFLICT (identity_id, tenant_id) DO UPDATE
    SET role = 'super_admin', status = 'active';

-- Demo / dev tenant (00...0002)
INSERT INTO core_mdm.tenant_memberships (identity_id, tenant_id, role, status)
SELECT i.identity_id, '00000000-0000-0000-0000-000000000002'::uuid, 'super_admin', 'active'
FROM   core_mdm.identities i
WHERE  i.email = 'ITAdmin@nexus.ai'
ON CONFLICT (identity_id, tenant_id) DO UPDATE
    SET role = 'super_admin', status = 'active';

-- ── 8. Retire the old dev admin (keep row, just mark non-protected) ───────────
-- ITAdmin@nexus.ai is now the canonical admin; admin@nexus.ai remains readable
-- for backward-compat audit trails but is no longer the primary login.

UPDATE core_mdm.identities
SET is_protected = false
WHERE email = 'admin@nexus.ai';

-- ── 9. Ensure both tenants have enterprise licenses ───────────────────────────

INSERT INTO core_mdm.tenant_licenses (
    tenant_id, tier, status, max_domains, max_records, max_stewards,
    features, notes
)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'enterprise', 'active', -1, -1, -1,
    '{"matching_semantic":true,"ai_copilot":true,"relationships":true,
      "domain_policies":true,"data_quality":true,"analytics":true,
      "governance":true,"distribution":true,"white_label":true}'::jsonb,
    'System tenant — enterprise, unlimited'
),
(
    '00000000-0000-0000-0000-000000000002',
    'enterprise', 'active', -1, -1, -1,
    '{"matching_semantic":true,"ai_copilot":true,"relationships":true,
      "domain_policies":true,"data_quality":true,"analytics":true,
      "governance":true,"distribution":true,"white_label":true}'::jsonb,
    'Demo tenant — enterprise, unlimited'
)
ON CONFLICT (tenant_id) DO UPDATE
    SET tier     = 'enterprise',
        status   = 'active',
        features = EXCLUDED.features;
