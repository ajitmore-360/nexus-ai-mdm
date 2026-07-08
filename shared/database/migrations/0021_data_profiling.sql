-- ─────────────────────────────────────────────────────────────────────────────
-- 0021: Data Profiling
-- Stores per-attribute profiling results: null rates, value distributions,
-- format patterns, outlier flags, and min/max/mean/stddev for numeric fields.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.data_profiles (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id        UUID        NOT NULL REFERENCES core_mdm.tenants(tenant_id),
    entity_type      VARCHAR(100) NOT NULL,
    attribute_name   VARCHAR(255) NOT NULL,
    -- Counts
    total_records    BIGINT      NOT NULL DEFAULT 0,
    null_count       BIGINT      NOT NULL DEFAULT 0,
    blank_count      BIGINT      NOT NULL DEFAULT 0,
    distinct_count   BIGINT      NOT NULL DEFAULT 0,
    -- Numeric stats (NULL for non-numeric attributes)
    min_value        DOUBLE PRECISION,
    max_value        DOUBLE PRECISION,
    mean_value       DOUBLE PRECISION,
    stddev_value     DOUBLE PRECISION,
    -- Distribution buckets: [{value, count, pct}]
    top_values       JSONB       NOT NULL DEFAULT '[]',
    -- Detected format patterns: [{pattern, count, pct}]
    format_patterns  JSONB       NOT NULL DEFAULT '[]',
    -- Outlier entity IDs (sampled, max 50)
    outlier_ids      UUID[]      NOT NULL DEFAULT '{}',
    profiled_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_profile UNIQUE (tenant_id, entity_type, attribute_name)
);

CREATE INDEX IF NOT EXISTS idx_data_profiles_type
    ON core_mdm.data_profiles (tenant_id, entity_type);

ALTER TABLE core_mdm.data_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON core_mdm.data_profiles
    USING (tenant_id = current_setting('app.current_tenant', true)::uuid);

-- ─────────────────────────────────────────────────────────────────────────────
-- Temporal / Bitemporal records
-- entity_versions stores every attribute snapshot with valid-time and
-- transaction-time so we can answer "what did we know on date X about the
-- state of entity E on date Y?"
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.entity_versions (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id        UUID        NOT NULL REFERENCES core_mdm.tenants(tenant_id),
    entity_id        UUID        NOT NULL REFERENCES core_mdm.entities(id) ON DELETE CASCADE,
    -- Transaction time: when we recorded this version
    recorded_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    recorded_by      UUID,
    -- Valid time: the real-world period this state was true
    valid_from       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    valid_to         TIMESTAMPTZ,               -- NULL = currently valid
    -- Snapshot of entity state at this version
    attributes       JSONB       NOT NULL DEFAULT '{}',
    status           VARCHAR(50) NOT NULL DEFAULT 'Active',
    change_reason    TEXT,
    source_system    VARCHAR(100)
);

CREATE INDEX IF NOT EXISTS idx_entity_versions_entity
    ON core_mdm.entity_versions (tenant_id, entity_id, recorded_at DESC);

CREATE INDEX IF NOT EXISTS idx_entity_versions_valid
    ON core_mdm.entity_versions (tenant_id, entity_id, valid_from, valid_to);

ALTER TABLE core_mdm.entity_versions ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON core_mdm.entity_versions
    USING (tenant_id = current_setting('app.current_tenant', true)::uuid);
