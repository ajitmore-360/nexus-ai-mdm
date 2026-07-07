-- ============================================================================
-- 0013 — Data Quality Rules & Violations
--
-- Stores tenant-authored quality rules (completeness, format, range checks
-- etc.) and the violations they produce when run against entity data.
-- The rule engine inside mdm-core evaluates these on entity create/update
-- (blocking reject/quarantine) and on manual batch runs (flag/enrich).
-- ============================================================================

-- ── Quality rules ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS core_mdm.quality_rules (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   UUID        NOT NULL REFERENCES core_mdm.tenants(tenant_id),
    name        TEXT        NOT NULL,
    entity_type TEXT        NOT NULL DEFAULT 'all',
    dimension   TEXT        NOT NULL DEFAULT 'validity',
    conditions  JSONB       NOT NULL DEFAULT '[]'::jsonb,
    logical_op  TEXT        NOT NULL DEFAULT 'AND'
                            CHECK (logical_op IN ('AND','OR')),
    action      TEXT        NOT NULL DEFAULT 'flag'
                            CHECK (action IN ('flag','reject','quarantine','enrich')),
    severity    TEXT        NOT NULL DEFAULT 'medium'
                            CHECK (severity IN ('critical','high','medium','low')),
    priority    INT         NOT NULL DEFAULT 100,
    is_active   BOOLEAN     NOT NULL DEFAULT true,
    created_by  UUID,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── Quality violations ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS core_mdm.quality_violations (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL REFERENCES core_mdm.tenants(tenant_id),
    -- rule_id is nullable so violations survive rule deletion
    rule_id         UUID        REFERENCES core_mdm.quality_rules(id)
                                ON DELETE SET NULL,
    -- Full rule snapshot at detection time for audit trail
    rule_snapshot   JSONB       NOT NULL,
    entity_id       UUID        REFERENCES core_mdm.entities(id)
                                ON DELETE CASCADE,
    entity_type     TEXT        NOT NULL,
    violated_fields JSONB       NOT NULL DEFAULT '[]'::jsonb,
    action_taken    TEXT        NOT NULL,
    severity        TEXT        NOT NULL,
    is_resolved     BOOLEAN     NOT NULL DEFAULT false,
    resolved_by     UUID,
    resolved_at     TIMESTAMPTZ,
    detected_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── Indexes ───────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_quality_rules_tenant_active
    ON core_mdm.quality_rules(tenant_id, is_active);
CREATE INDEX IF NOT EXISTS idx_quality_rules_entity_type
    ON core_mdm.quality_rules(tenant_id, entity_type);
CREATE INDEX IF NOT EXISTS idx_quality_violations_tenant
    ON core_mdm.quality_violations(tenant_id, is_resolved, detected_at DESC);
CREATE INDEX IF NOT EXISTS idx_quality_violations_entity
    ON core_mdm.quality_violations(entity_id);
CREATE INDEX IF NOT EXISTS idx_quality_violations_rule
    ON core_mdm.quality_violations(rule_id);

-- ── Row Level Security ────────────────────────────────────────────────────────
ALTER TABLE core_mdm.quality_rules      ENABLE ROW LEVEL SECURITY;
ALTER TABLE core_mdm.quality_violations ENABLE ROW LEVEL SECURITY;

CREATE POLICY quality_rules_tenant_rls ON core_mdm.quality_rules
    USING (tenant_id = current_setting('app.current_tenant', true)::uuid);

CREATE POLICY quality_violations_tenant_rls ON core_mdm.quality_violations
    USING (tenant_id = current_setting('app.current_tenant', true)::uuid);
