-- =============================================================================
-- Migration 0035: Final handler-required tables and functions
--
-- After auditing all backend handler SQL references against migrations 0001-0034,
-- three items are still missing that cause runtime errors when specific handlers
-- are called:
--
--   1. core_mdm.audit_event_log      — policy.rs list_gdpr_requests
--   2. core_mdm.survivorship_field_decisions — policy.rs get_survivorship_suggestions
--   3. core_mdm.gdpr_erase_entity()  — entities.rs gdpr_erase_entity endpoint
--
-- NOTE: core_mdm.audit_events (created in 0010) is the operational audit table
-- used for all non-GDPR events.  audit_event_log is a separate append-only log
-- used by the policy handler to surface GDPR request history.
-- =============================================================================

-- ── 1. GDPR audit event log ───────────────────────────────────────────────────
-- Used by policy.rs list_gdpr_requests to return the history of erasure /
-- access / portability requests made by data subjects.

CREATE TABLE IF NOT EXISTS core_mdm.audit_event_log (
    log_id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL REFERENCES core_mdm.tenants(tenant_id),
    event_type      TEXT        NOT NULL
                                CHECK (event_type IN (
                                    'gdpr_erase',
                                    'gdpr_access',
                                    'gdpr_portability',
                                    'gdpr_rectification',
                                    'gdpr_objection'
                                )),
    subject_id      UUID        NOT NULL,   -- data subject (entity_id or identity_id)
    subject_type    TEXT        NOT NULL DEFAULT 'entity',
    requested_by    UUID,                   -- identity that submitted the request
    requested_by_email TEXT,
    -- Outcome
    status          TEXT        NOT NULL DEFAULT 'completed'
                                CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
    records_affected BIGINT     NOT NULL DEFAULT 0,
    fields_affected  TEXT[]     NOT NULL DEFAULT '{}',
    notes           TEXT,
    -- Timestamps
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at    TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_audit_event_log_tenant
    ON core_mdm.audit_event_log (tenant_id, event_type, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_event_log_subject
    ON core_mdm.audit_event_log (tenant_id, subject_id);

ALTER TABLE core_mdm.audit_event_log ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'core_mdm'
          AND tablename  = 'audit_event_log'
          AND policyname = 'audit_event_log_tenant_rls'
    ) THEN
        CREATE POLICY audit_event_log_tenant_rls ON core_mdm.audit_event_log
            USING (tenant_id = current_setting('app.current_tenant', true)::uuid);
    END IF;
END $$;

-- ── 2. Survivorship field decisions ──────────────────────────────────────────
-- Used by policy.rs get_survivorship_suggestions to show per-field decisions
-- made by the survivorship engine when writing a golden record.
-- One row per (golden_record, field) at the time of survivorship execution.

CREATE TABLE IF NOT EXISTS core_mdm.survivorship_field_decisions (
    decision_id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID        NOT NULL,
    golden_record_id    UUID        NOT NULL REFERENCES core_mdm.golden_records(golden_record_id) ON DELETE CASCADE,
    entity_type         TEXT        NOT NULL,
    field_name          TEXT        NOT NULL,
    -- Winning value (JSONB so it can store any type)
    winning_value       JSONB,
    winning_source      TEXT,                   -- source_system of the winning value
    winning_entity_id   UUID,                   -- entity that provided the winning value
    -- Rule that determined the winner
    rule_id             UUID        REFERENCES core_mdm.survivorship_rules(rule_id) ON DELETE SET NULL,
    rule_name           TEXT,
    strategy            TEXT        NOT NULL DEFAULT 'TrustedSource',
    confidence          FLOAT4,
    -- Was a human override applied instead of the rule outcome?
    human_override      BOOLEAN     NOT NULL DEFAULT FALSE,
    overridden_by       UUID,
    -- Snapshot of all candidate values considered (for audit / UI comparison)
    candidates          JSONB       NOT NULL DEFAULT '[]',
    decided_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sfd_golden_record
    ON core_mdm.survivorship_field_decisions (tenant_id, golden_record_id, field_name);

CREATE INDEX IF NOT EXISTS idx_sfd_entity_type
    ON core_mdm.survivorship_field_decisions (tenant_id, entity_type, field_name);

ALTER TABLE core_mdm.survivorship_field_decisions ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'core_mdm'
          AND tablename  = 'survivorship_field_decisions'
          AND policyname = 'sfd_tenant_rls'
    ) THEN
        CREATE POLICY sfd_tenant_rls ON core_mdm.survivorship_field_decisions
            USING (tenant_id = current_setting('app.current_tenant', true)::uuid);
    END IF;
END $$;

-- ── 3. GDPR entity erasure function ──────────────────────────────────────────
-- Called by entities.rs gdpr_erase_entity endpoint.
-- Implements GDPR Article 17 "right to be forgotten":
--   a) Overwrites PII attribute values with a canonical erasure marker
--   b) Sets entity status to 'Erased'
--   c) Records the erasure in both audit.gdpr_requests and core_mdm.audit_event_log
--
-- The function runs as SECURITY DEFINER so the caller does not need direct
-- write access to attribute tables (which have strict RLS).

CREATE OR REPLACE FUNCTION core_mdm.gdpr_erase_entity(
    p_tenant_id   UUID,
    p_entity_id   UUID
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_erased_fields  TEXT[]  := '{}';
    v_attr_count     BIGINT  := 0;
    v_result         JSONB;
BEGIN
    -- Collect PII field names before erasure (for the audit record)
    SELECT ARRAY_AGG(DISTINCT attribute_key)
    INTO v_erased_fields
    FROM core_mdm.entity_attributes
    WHERE entity_id = p_entity_id
      AND tenant_id = p_tenant_id
      AND attribute_key IN (
          -- Standard PII fields across all entity types
          'email', 'mobile', 'phone', 'fax',
          'first_name', 'last_name', 'display_name', 'full_name',
          'date_of_birth', 'national_id', 'passport_number',
          'tax_id', 'vat_number', 'bank_account', 'bank_iban',
          'billing_address', 'shipping_address', 'street', 'address',
          'work_email', 'work_phone', 'personal_email',
          'ssn', 'sin', 'nino', 'driver_license'
      );

    -- Overwrite PII attributes with erasure marker
    UPDATE core_mdm.entity_attributes
    SET    attribute_value = '"[ERASED]"'::jsonb,
           is_masked       = TRUE
    WHERE  entity_id = p_entity_id
      AND  tenant_id = p_tenant_id
      AND  attribute_key = ANY(v_erased_fields);

    GET DIAGNOSTICS v_attr_count = ROW_COUNT;

    -- Mark the entity as Erased
    UPDATE core_mdm.entities
    SET    status     = 'Erased',
           metadata   = metadata || '{"gdpr_erased_at": "' || NOW()::TEXT || '"}'::jsonb,
           updated_at = NOW()
    WHERE  entity_id  = p_entity_id
      AND  tenant_id  = p_tenant_id;

    -- Record in legacy audit.gdpr_requests (for backward compat with policy.rs)
    INSERT INTO audit.gdpr_requests (
        tenant_id, subject_id, request_type,
        records_affected, fields_erased, completed_at
    ) VALUES (
        p_tenant_id, p_entity_id, 'erasure',
        v_attr_count,
        COALESCE(v_erased_fields, '{}'),
        NOW()
    );

    -- Record in new audit_event_log (for list_gdpr_requests handler)
    INSERT INTO core_mdm.audit_event_log (
        tenant_id, event_type, subject_id, subject_type,
        status, records_affected, fields_affected, completed_at
    ) VALUES (
        p_tenant_id, 'gdpr_erase', p_entity_id, 'entity',
        'completed', v_attr_count,
        COALESCE(v_erased_fields, '{}'),
        NOW()
    );

    v_result := jsonb_build_object(
        'erased',        TRUE,
        'entity_id',     p_entity_id,
        'fields_erased', COALESCE(v_erased_fields, '{}'),
        'count',         v_attr_count
    );

    RETURN v_result;
END;
$$;

-- ── 4. Create ingest.ingest_jobs if not yet created ───────────────────────────
-- The ingest-service creates this table at runtime via its own Rust migrations,
-- but adding it here ensures the schema is complete for a fresh SQL-only setup.

CREATE SCHEMA IF NOT EXISTS ingest;

CREATE TABLE IF NOT EXISTS ingest.ingest_jobs (
    job_id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL,
    batch_id        UUID,
    source_system   TEXT        NOT NULL DEFAULT '',
    file_name       TEXT,
    status          TEXT        NOT NULL DEFAULT 'pending'
                                CHECK (status IN ('pending','processing','completed','partial_success','failed')),
    total_records   INTEGER     NOT NULL DEFAULT 0,
    processed       INTEGER     NOT NULL DEFAULT 0,
    failed          INTEGER     NOT NULL DEFAULT 0,
    chunks_total    INTEGER     NOT NULL DEFAULT 0,
    chunks_done     INTEGER     NOT NULL DEFAULT 0,
    chunk_size      INTEGER     NOT NULL DEFAULT 500,
    duration_ms     BIGINT      NOT NULL DEFAULT 0,
    error_message   TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ingest_jobs_tenant_status
    ON ingest.ingest_jobs (tenant_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ingest_jobs_cleanup
    ON ingest.ingest_jobs (status, created_at)
    WHERE status IN ('completed', 'partial_success', 'failed');
