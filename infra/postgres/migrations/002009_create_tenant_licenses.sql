-- ============================================================================
-- Migration 002009: Tenant Licenses
-- Per-tenant subscription tier with feature flags and hard limits.
-- Essentials: 1 domain / 500k records / 5 stewards
-- Professional: 5 domains / 5M records / 20 stewards + premium features
-- Enterprise: unlimited + white-label (future)
-- ============================================================================

CREATE TABLE IF NOT EXISTS core_mdm.tenant_licenses (
    license_id      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL REFERENCES core_mdm.tenants(tenant_id) ON DELETE CASCADE,

    -- Subscription tier
    tier            TEXT        NOT NULL DEFAULT 'essentials'
                                CHECK (tier IN ('trial', 'essentials', 'professional', 'enterprise')),

    -- Lifecycle status
    status          TEXT        NOT NULL DEFAULT 'active'
                                CHECK (status IN ('active', 'suspended', 'expired', 'trial')),

    -- Hard limits  (-1 = unlimited, Enterprise only)
    max_domains     INTEGER     NOT NULL DEFAULT 1,
    max_records     BIGINT      NOT NULL DEFAULT 500000,
    max_stewards    INTEGER     NOT NULL DEFAULT 5,

    -- Feature flags (keyed by feature slug, value = true)
    -- Essentials features are always on (not in this map).
    -- Professional / Enterprise features are gated here.
    features        JSONB       NOT NULL DEFAULT '{}',

    -- Billing / validity
    license_key     TEXT        UNIQUE,
    starts_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at      TIMESTAMPTZ,           -- NULL = perpetual
    trial_ends_at   TIMESTAMPTZ,

    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- One active license per tenant
    UNIQUE(tenant_id)
);

CREATE INDEX IF NOT EXISTS idx_tenant_licenses_tenant  ON core_mdm.tenant_licenses(tenant_id);
CREATE INDEX IF NOT EXISTS idx_tenant_licenses_status  ON core_mdm.tenant_licenses(status);
CREATE INDEX IF NOT EXISTS idx_tenant_licenses_expires ON core_mdm.tenant_licenses(expires_at)
    WHERE expires_at IS NOT NULL;

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Helper: canonical feature set per tier
-- Use these JSONB constants when creating licenses programmatically.
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- Essentials features are ALWAYS on â€” nothing gated here.
-- Professional adds all premium features.
-- Enterprise adds white-label ontop of Professional.

COMMENT ON TABLE core_mdm.tenant_licenses IS
'One row per tenant. tier controls feature access and hard limits.
 Essentials (default): 1 domain, 500k records, 5 stewards â€” basic matching only.
 Professional: 5 domains, 5M records, 20 stewards â€” semantic matching, AI copilot,
   cross-domain relationships, per-domain policies, analytics, governance, distribution.
 Enterprise: unlimited everything + white-label branding.';

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Seed: system tenant gets enterprise (internal use / demo)
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

INSERT INTO core_mdm.tenant_licenses (
    tenant_id,
    tier,
    status,
    max_domains,
    max_records,
    max_stewards,
    features,
    notes
) VALUES (
    '00000000-0000-0000-0000-000000000001',
    'enterprise',
    'active',
    -1,
    -1,
    -1,
    '{
        "matching_semantic":  true,
        "ai_copilot":         true,
        "relationships":      true,
        "domain_policies":    true,
        "data_quality":       true,
        "analytics":          true,
        "governance":         true,
        "distribution":       true,
        "white_label":        true,
        "priority_support":   true
    }'::jsonb,
    'System / demo tenant â€” enterprise tier, all features enabled'
) ON CONFLICT (tenant_id) DO NOTHING;

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Function: AZILE_license_features(tier TEXT) â†’ JSONB
-- Returns the canonical features JSONB for a given tier.
-- Called when provisioning new tenants programmatically.
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

CREATE OR REPLACE FUNCTION core_mdm.AZILE_license_features(p_tier TEXT)
RETURNS JSONB
LANGUAGE plpgsql IMMUTABLE
AS $$
BEGIN
    CASE p_tier
        WHEN 'essentials' THEN
            -- Core MDM only; premium features are locked
            RETURN '{}'::jsonb;
        WHEN 'professional' THEN
            RETURN '{
                "matching_semantic": true,
                "ai_copilot":        true,
                "relationships":     true,
                "domain_policies":   true,
                "data_quality":      true,
                "analytics":         true,
                "governance":        true,
                "distribution":      true
            }'::jsonb;
        WHEN 'enterprise' THEN
            RETURN '{
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
            }'::jsonb;
        ELSE
            -- trial: same as essentials
            RETURN '{}'::jsonb;
    END CASE;
END;
$$;

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Function: AZILE_license_limits(tier TEXT) â†’ TABLE
-- Returns (max_domains, max_records, max_stewards) for a given tier.
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

CREATE OR REPLACE FUNCTION core_mdm.AZILE_license_limits(p_tier TEXT)
RETURNS TABLE(max_domains INTEGER, max_records BIGINT, max_stewards INTEGER)
LANGUAGE plpgsql IMMUTABLE
AS $$
BEGIN
    CASE p_tier
        WHEN 'essentials' THEN
            RETURN QUERY SELECT 1::INTEGER, 500000::BIGINT, 5::INTEGER;
        WHEN 'professional' THEN
            RETURN QUERY SELECT 5::INTEGER, 5000000::BIGINT, 20::INTEGER;
        WHEN 'enterprise' THEN
            RETURN QUERY SELECT (-1)::INTEGER, (-1)::BIGINT, (-1)::INTEGER;
        ELSE
            -- trial: essentials limits
            RETURN QUERY SELECT 1::INTEGER, 100000::BIGINT, 3::INTEGER;
    END CASE;
END;
$$;
