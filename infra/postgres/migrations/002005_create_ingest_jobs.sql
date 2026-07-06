-- ============================================================
-- Ingest job tracking
--
-- Records every batch submitted to the ingest-service so
-- operators can query job status after submission.
-- ============================================================

CREATE SCHEMA IF NOT EXISTS ingest;

CREATE TABLE IF NOT EXISTS ingest.ingest_jobs (
    job_id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id       UUID        NOT NULL,
    tenant_id      UUID        NOT NULL REFERENCES core_mdm.tenants(tenant_id) ON DELETE CASCADE,
    source_system  TEXT        NOT NULL,
    status         TEXT        NOT NULL DEFAULT 'pending'
                               CHECK (status IN ('pending','processing','completed','partial_success','failed')),
    total_records  INTEGER     NOT NULL DEFAULT 0,
    processed      INTEGER     NOT NULL DEFAULT 0,
    failed         INTEGER     NOT NULL DEFAULT 0,
    skipped        INTEGER     NOT NULL DEFAULT 0,
    entity_ids     UUID[]      NOT NULL DEFAULT '{}',
    errors         TEXT[]      NOT NULL DEFAULT '{}',
    duration_ms    BIGINT      NOT NULL DEFAULT 0,
    file_name      TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at   TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_ingest_jobs_tenant_created
    ON ingest.ingest_jobs (tenant_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ingest_jobs_batch
    ON ingest.ingest_jobs (batch_id);

CREATE INDEX IF NOT EXISTS idx_ingest_jobs_tenant_status
    ON ingest.ingest_jobs (tenant_id, status);

COMMENT ON TABLE ingest.ingest_jobs IS
    'One row per ingest batch. Persisted synchronously after processing completes.';
