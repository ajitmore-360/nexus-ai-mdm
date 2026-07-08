-- Migration 0018: Quality Scorecards & Trend Analytics
-- Weekly/monthly snapshots of quality scores per tenant/entity-type/dimension.
-- Powers trend charts: "completeness improved from 62% → 89% in Q2".
-- The unique constraint prevents duplicate snapshots for the same day.
-- NULL entity_type = aggregate across all types for that tenant.
-- NULL source_system = aggregate across all sources.

CREATE TABLE IF NOT EXISTS core_mdm.quality_snapshots (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID         NOT NULL REFERENCES core_mdm.tenants(tenant_id),
    entity_type     VARCHAR(100),
    source_system   VARCHAR(100),
    dimension       VARCHAR(50)  NOT NULL
        CHECK (dimension IN ('completeness','accuracy','uniqueness','validity','consistency','timeliness')),
    score           DECIMAL(5,2) NOT NULL CHECK (score BETWEEN 0 AND 100),
    total_entities  INTEGER      NOT NULL DEFAULT 0,
    violation_count INTEGER      NOT NULL DEFAULT 0,
    snapshot_date   DATE         NOT NULL DEFAULT CURRENT_DATE,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_snapshot UNIQUE (tenant_id, entity_type, source_system, dimension, snapshot_date)
);

CREATE INDEX IF NOT EXISTS idx_quality_snapshots_tenant_date ON core_mdm.quality_snapshots (tenant_id, snapshot_date DESC);
CREATE INDEX IF NOT EXISTS idx_quality_snapshots_type_dim    ON core_mdm.quality_snapshots (tenant_id, entity_type, dimension);

ALTER TABLE core_mdm.quality_snapshots ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON core_mdm.quality_snapshots
    USING (tenant_id = current_setting('app.current_tenant', true)::uuid);
