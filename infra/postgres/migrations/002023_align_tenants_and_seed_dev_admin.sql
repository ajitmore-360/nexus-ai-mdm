-- ============================================================================
-- Migration 002023: Align core_mdm.tenants schema + seed dev tenant + admin
--
-- Problems fixed:
--   1. core_mdm.tenants was created (000003) with tenant_name / subscription_plan
--      but all application code references display_name / plan / features / settings.
--      The missing columns are added and populated from the legacy columns.
--   2. A fresh database has no user to log in with — this migration seeds a
--      development tenant and admin account so the app works out of the box.
--
-- Dev credentials:
--   Email:    admin@nexus.ai
--   Password: Admin@123
--   Tenant:   Nexus Dev Tenant (tenant_id = 00000000-0000-0000-0000-000000000002)
--
-- All inserts use ON CONFLICT so the migration is safe to re-run.
-- ============================================================================

-- ── 1. Add missing columns to core_mdm.tenants ───────────────────────────────

ALTER TABLE core_mdm.tenants
    ADD COLUMN IF NOT EXISTS display_name TEXT,
    ADD COLUMN IF NOT EXISTS plan         TEXT,
    ADD COLUMN IF NOT EXISTS features     JSONB NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS settings     JSONB NOT NULL DEFAULT '{}';

-- Back-fill display_name and plan from legacy columns for existing rows.
UPDATE core_mdm.tenants SET display_name = tenant_name      WHERE display_name IS NULL;
UPDATE core_mdm.tenants SET plan         = subscription_plan WHERE plan IS NULL;

-- ── 2. Seed the system tenant into core_mdm.tenants (idempotent) ─────────────
-- Migration 000019 inserted this into core.tenants (wrong schema).
-- 002009 references it via FK — so it must exist here for a clean DB init.

INSERT INTO core_mdm.tenants (
    tenant_id,
    tenant_code,
    tenant_name,
    display_name,
    plan,
    status,
    features,
    settings,
    metadata
)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'SYSTEM',
    'Nexus Platform',
    'Nexus Platform',
    'enterprise',
    'ACTIVE',
    '{"ai_matching":true,"rag_copilot":true,"vector_blocking":true,"distribution":true,"white_label":true}',
    '{}',
    '{"seeded_by":"migration_002023","is_system":true}'
)
ON CONFLICT (tenant_id) DO UPDATE
    SET display_name = EXCLUDED.display_name,
        plan         = EXCLUDED.plan,
        features     = EXCLUDED.features,
        updated_at   = NOW();

-- ── 3. Seed development tenant ────────────────────────────────────────────────

INSERT INTO core_mdm.tenants (
    tenant_id,
    tenant_code,
    tenant_name,
    display_name,
    plan,
    status,
    features,
    settings,
    metadata
)
VALUES (
    '00000000-0000-0000-0000-000000000002',
    'NEXUS-DEV',
    'Nexus Dev Tenant',
    'Nexus Dev Tenant',
    'enterprise',
    'ACTIVE',
    '{"ai_matching":true,"rag_copilot":true,"vector_blocking":true,"distribution":true,"governance":true}',
    '{}',
    '{"seeded_by":"migration_002023","note":"development tenant — safe to delete in production"}'
)
ON CONFLICT (tenant_id) DO UPDATE
    SET display_name = EXCLUDED.display_name,
        plan         = EXCLUDED.plan,
        features     = EXCLUDED.features,
        updated_at   = NOW();

-- ── 4. Seed dev tenant license ────────────────────────────────────────────────

INSERT INTO core_mdm.tenant_licenses (
    tenant_id,
    tier,
    status,
    max_domains,
    max_records,
    max_stewards,
    features,
    starts_at,
    notes
)
VALUES (
    '00000000-0000-0000-0000-000000000002',
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
    NOW(),
    'Dev tenant — enterprise tier, all features enabled'
)
ON CONFLICT (tenant_id) DO NOTHING;

-- ── 5. Seed dev admin identity ────────────────────────────────────────────────
-- Email:    admin@nexus.ai
-- Password: Admin@123  (bcrypt via pgcrypto, hashed at migration run time)

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

-- ── 6. Seed admin membership in the dev tenant ────────────────────────────────

INSERT INTO core_mdm.tenant_memberships (
    identity_id,
    tenant_id,
    role,
    status
)
VALUES (
    '00000000-0000-0000-0000-000000000010',
    '00000000-0000-0000-0000-000000000002',
    'super_admin',
    'active'
)
ON CONFLICT (identity_id, tenant_id) DO NOTHING;
