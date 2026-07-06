-- ============================================================
-- Distribution jobs: async export / push of MDM golden records
-- to downstream systems (Salesforce, SAP, S3, etc.)
-- ============================================================

CREATE TABLE IF NOT EXISTS core_mdm.distribution_jobs (
    job_id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL REFERENCES core_mdm.tenants(tenant_id) ON DELETE CASCADE,
    name            TEXT        NOT NULL,
    target_system   TEXT        NOT NULL,               -- e.g. 'Salesforce', 'SAP ERP', 'S3'
    filter_config   JSONB       NOT NULL DEFAULT '{}',  -- entity_type, status, date range, etc.
    status          TEXT        NOT NULL DEFAULT 'draft'
                                CHECK (status IN ('draft','queued','running','completed','failed','cancelled')),
    record_count    INTEGER,                            -- filled when job completes
    error_message   TEXT,                               -- set on failure
    created_by      UUID,                               -- user_id of initiator
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    started_at      TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_distribution_jobs_tenant
    ON core_mdm.distribution_jobs (tenant_id, status, created_at DESC);

-- Auto-update updated_at on every row change.
CREATE OR REPLACE FUNCTION core_mdm.set_distribution_job_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_distribution_jobs_updated_at ON core_mdm.distribution_jobs;
CREATE TRIGGER trg_distribution_jobs_updated_at
    BEFORE UPDATE ON core_mdm.distribution_jobs
    FOR EACH ROW EXECUTE FUNCTION core_mdm.set_distribution_job_updated_at();

COMMENT ON TABLE core_mdm.distribution_jobs IS
    'Tracks async export jobs that push MDM golden records to downstream systems.';
