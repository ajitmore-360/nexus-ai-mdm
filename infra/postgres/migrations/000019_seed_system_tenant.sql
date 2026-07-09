--
-- ============================================================
-- SEED SYSTEM TENANT
-- FILE: 000019_seed_system_tenant.sql
-- ============================================================
--

BEGIN;

--
-- ============================================================
-- EXTENSIONS
-- ============================================================
--

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

--
-- ============================================================
-- SYSTEM TENANT
-- ============================================================
--
-- This creates the platform/system tenant used for:
--
-- 1. Global configurations
-- 2. Reference data
-- 3. AI/ML models
-- 4. Shared survivorship rules
-- 5. System workflows
-- 6. Internal orchestration
-- 7. Bootstrap entities
--
-- IMPORTANT:
-- Keep this UUID constant across all environments.
-- Never regenerate it after production deployment.
--

INSERT INTO core.tenants
(
    tenant_id,

    tenant_code,

    tenant_name,

    status,

    subscription_plan,

    is_system_tenant,

    settings,

    metadata,

    created_at,

    updated_at
)
VALUES
(
    '00000000-0000-0000-0000-000000000001',

    'SYSTEM',

    'Nexus Platform System Tenant',

    'Active',

    'Enterprise',

    TRUE,

    jsonb_build_object(

        --
        -- Feature Flags
        --

        'features',
        jsonb_build_object(

            'ai_matching', true,

            'semantic_search', true,

            'graph_matching', true,

            'survivorship', true,

            'vector_embeddings', true,

            'golden_records', true,

            'lineage_tracking', true,

            'event_sourcing', true,

            'audit_logging', true
        ),

        --
        -- Security
        --

        'security',
        jsonb_build_object(

            'mfa_required', true,

            'session_timeout_minutes', 60,

            'password_rotation_days', 90
        ),

        --
        -- AI Settings
        --

        'ai',
        jsonb_build_object(

            'embedding_provider', 'openai',

            'default_model', 'text-embedding-3-large',

            'matching_model', 'gpt-4.1',

            'semantic_threshold', 0.85
        ),

        --
        -- Data Governance
        --

        'governance',
        jsonb_build_object(

            'retain_audit_days', 3650,

            'retain_events_days', 3650,

            'pii_encryption', true
        )
    ),

    jsonb_build_object(

        'seeded_by', 'migration_000019',

        'environment', 'system',

        'owner', 'platform',

        'description',
        'Default system tenant for Azile MDM platform'
    ),

    NOW(),

    NOW()
)

--
-- ============================================================
-- IDEMPOTENCY
-- ============================================================
--
-- Prevent duplicate insertion if migration
-- accidentally reruns.
--

ON CONFLICT (tenant_id)

DO UPDATE SET

    tenant_name =
        EXCLUDED.tenant_name,

    tenant_code =
        EXCLUDED.tenant_code,

    status =
        EXCLUDED.status,

    subscription_plan =
        EXCLUDED.subscription_plan,

    is_system_tenant =
        EXCLUDED.is_system_tenant,

    settings =
        EXCLUDED.settings,

    metadata =
        EXCLUDED.metadata,

    updated_at =
        NOW();

--
-- ============================================================
-- OPTIONAL VALIDATION
-- ============================================================
--

DO
$$
BEGIN

    IF NOT EXISTS
    (
        SELECT 1
        FROM core.tenants
        WHERE tenant_id =
            '00000000-0000-0000-0000-000000000001'
    )
    THEN

        RAISE EXCEPTION
        'System tenant seeding failed';

    END IF;

END;
$$;

COMMIT;

--
-- ============================================================
-- COMMENTS
-- ============================================================
--

COMMENT ON COLUMN core.tenants.is_system_tenant
IS 'Indicates whether the tenant is the internal platform tenant';