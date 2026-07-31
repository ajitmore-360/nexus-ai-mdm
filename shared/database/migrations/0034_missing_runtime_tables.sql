-- =============================================================================
-- Migration 0034: Missing runtime tables required by handler code
--
-- The shared migration sequence (0001-0033) was written as a re-implementation
-- of the infra migrations and omitted several tables that handler code queries.
-- This migration fills those gaps so a fresh Docker build produces a fully
-- functional schema.
--
-- Tables added:
--   core_mdm.match_requests          — match engine execution log (review.rs)
--   core_mdm.match_review_queue      — human review workflow (review.rs, dashboard.rs)
--   core_mdm.entity_type_configs     — tenant entity type definitions (entity_types.rs)
--   core_mdm.number_sequences        — per-tenant per-type ID sequences
--   core_mdm.next_sequence_value()   — atomic sequence function (entity_types.rs)
--   core_mdm.entity_type_assignments — data ownership (data_governance.rs, users.rs)
--   core_mdm.entity_approval_requests— approval workflow (data_governance.rs, dashboard.rs)
--   notifications schema             — required by delivery log retention function (0030)
--   notifications.webhook_subscriptions
--   notifications.delivery_log       — delivery audit trail (retention 0030)
--   platform.distribution_jobs.next_attempt_at — exponential backoff column
-- =============================================================================

-- ── 1. Match requests ─────────────────────────────────────────────────────────
-- Parent table for the matching engine; match_candidates and field_match_results
-- (already created in 0003) have a request_id column referencing this table.

CREATE TABLE IF NOT EXISTS core_mdm.match_requests (
    request_id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               UUID        NOT NULL,
    correlation_id          UUID,
    entity_type             TEXT        NOT NULL,
    source_entity_id        UUID,
    canonical_entity_id     UUID,
    strategy                TEXT        NOT NULL DEFAULT 'Hybrid',
    threshold               FLOAT8,
    ai_assisted             BOOLEAN     NOT NULL DEFAULT FALSE,
    semantic_matching       BOOLEAN     NOT NULL DEFAULT FALSE,
    graph_matching          BOOLEAN     NOT NULL DEFAULT FALSE,
    explainability_enabled  BOOLEAN     NOT NULL DEFAULT TRUE,
    max_candidates          INTEGER     NOT NULL DEFAULT 25,
    blocking_rules          JSONB       NOT NULL DEFAULT '[]',
    status                  TEXT        NOT NULL DEFAULT 'Pending',
    execution_started_at    TIMESTAMPTZ,
    execution_completed_at  TIMESTAMPTZ,
    execution_time_ms       BIGINT,
    candidates_evaluated    INTEGER,
    blocking_reduction      FLOAT8,
    warnings                JSONB       NOT NULL DEFAULT '[]',
    errors                  JSONB       NOT NULL DEFAULT '[]',
    engine_version          TEXT,
    created_by              UUID,
    metadata                JSONB       NOT NULL DEFAULT '{}',
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_match_requests_tenant
    ON core_mdm.match_requests (tenant_id);
CREATE INDEX IF NOT EXISTS idx_match_requests_entity_type
    ON core_mdm.match_requests (entity_type);
CREATE INDEX IF NOT EXISTS idx_match_requests_status
    ON core_mdm.match_requests (status);
CREATE INDEX IF NOT EXISTS idx_match_requests_created
    ON core_mdm.match_requests (created_at DESC);

-- Retry index added by migration 0030 retention function — create it now.
CREATE INDEX IF NOT EXISTS idx_match_requests_cleanup
    ON core_mdm.match_requests (status, created_at)
    WHERE status IN (
        'completed', 'reviewed', 'merged', 'rejected', 'auto_merged',
        'AutoMerged', 'Merged', 'Reviewed', 'Rejected'
    );

-- ── 2. Match review queue ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS core_mdm.match_review_queue (
    review_id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID        NOT NULL,
    request_id          UUID        NOT NULL,
    match_candidate_id  UUID        NOT NULL,
    assigned_to         UUID,
    review_status       TEXT        NOT NULL DEFAULT 'Pending',
    review_notes        TEXT,
    reviewed_by         UUID,
    reviewed_at         TIMESTAMPTZ,
    priority            INTEGER     NOT NULL DEFAULT 5,
    metadata            JSONB       NOT NULL DEFAULT '{}',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_match_review_tenant
    ON core_mdm.match_review_queue (tenant_id, review_status);
CREATE INDEX IF NOT EXISTS idx_match_review_request
    ON core_mdm.match_review_queue (request_id);
CREATE INDEX IF NOT EXISTS idx_match_review_candidate
    ON core_mdm.match_review_queue (match_candidate_id);
CREATE INDEX IF NOT EXISTS idx_match_review_priority
    ON core_mdm.match_review_queue (priority DESC, created_at);
CREATE INDEX IF NOT EXISTS idx_match_review_assigned
    ON core_mdm.match_review_queue (assigned_to)
    WHERE assigned_to IS NOT NULL;

-- ── 3. Entity type configuration ──────────────────────────────────────────────
-- The entity_types.rs handler manages tenant entity type definitions through
-- this table (not the old infra entity_types table).

CREATE TABLE IF NOT EXISTS core_mdm.entity_type_configs (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               UUID        NOT NULL,
    name                    TEXT        NOT NULL,
    code                    TEXT        NOT NULL,
    description             TEXT,
    icon                    TEXT        DEFAULT '🏢',
    color                   TEXT        DEFAULT '#7C3AED',
    seq_prefix              TEXT        NOT NULL DEFAULT '',
    seq_format              TEXT        NOT NULL DEFAULT '{PREFIX}-{YYYY}-{SEQ5}',
    seq_current             BIGINT      NOT NULL DEFAULT 0,
    seq_reset_period        TEXT        NOT NULL DEFAULT 'never',
    seq_last_reset          TIMESTAMPTZ,
    default_match_threshold NUMERIC(4,3) DEFAULT 0.85,
    is_active               BOOLEAN     NOT NULL DEFAULT TRUE,
    is_system               BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, code)
);

ALTER TABLE core_mdm.entity_type_configs ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'entity_type_configs' AND schemaname = 'core_mdm'
          AND policyname = 'entity_type_configs_tenant'
    ) THEN
        CREATE POLICY entity_type_configs_tenant ON core_mdm.entity_type_configs
            USING (tenant_id = current_setting('app.current_tenant', TRUE)::UUID);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_entity_type_configs_tenant
    ON core_mdm.entity_type_configs (tenant_id);
CREATE INDEX IF NOT EXISTS idx_entity_type_configs_active
    ON core_mdm.entity_type_configs (tenant_id, is_active)
    WHERE is_active = TRUE;

-- ── 4. Number sequences + atomic next-value function ─────────────────────────
CREATE TABLE IF NOT EXISTS core_mdm.number_sequences (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID        NOT NULL,
    entity_type_code    TEXT        NOT NULL,
    period_key          TEXT        NOT NULL DEFAULT 'global',
    current_value       BIGINT      NOT NULL DEFAULT 0,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, entity_type_code, period_key)
);

ALTER TABLE core_mdm.number_sequences ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'number_sequences' AND schemaname = 'core_mdm'
          AND policyname = 'number_sequences_tenant'
    ) THEN
        CREATE POLICY number_sequences_tenant ON core_mdm.number_sequences
            USING (tenant_id = current_setting('app.current_tenant', TRUE)::UUID);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_number_sequences_lookup
    ON core_mdm.number_sequences (tenant_id, entity_type_code, period_key);

CREATE OR REPLACE FUNCTION core_mdm.next_sequence_value(
    p_tenant_id         UUID,
    p_entity_type_code  TEXT,
    p_period_key        TEXT DEFAULT 'global'
) RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE
    v_next BIGINT;
BEGIN
    INSERT INTO core_mdm.number_sequences (tenant_id, entity_type_code, period_key, current_value)
    VALUES (p_tenant_id, p_entity_type_code, p_period_key, 1)
    ON CONFLICT (tenant_id, entity_type_code, period_key)
    DO UPDATE SET
        current_value = core_mdm.number_sequences.current_value + 1,
        updated_at    = NOW()
    RETURNING current_value INTO v_next;
    RETURN v_next;
END;
$$;

-- ── 5. Entity type assignments (data governance — data ownership) ─────────────
CREATE TABLE IF NOT EXISTS core_mdm.entity_type_assignments (
    assignment_id    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id        UUID        NOT NULL,
    identity_id      UUID        NOT NULL REFERENCES core_mdm.identities(identity_id) ON DELETE CASCADE,
    entity_type_code TEXT        NOT NULL,
    assignment_type  TEXT        NOT NULL CHECK (assignment_type IN ('owner', 'steward')),
    assigned_by      UUID        REFERENCES core_mdm.identities(identity_id),
    assigned_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, identity_id, entity_type_code)
);

CREATE UNIQUE INDEX IF NOT EXISTS entity_type_assignments_one_owner_idx
    ON core_mdm.entity_type_assignments (tenant_id, entity_type_code)
    WHERE assignment_type = 'owner';

CREATE INDEX IF NOT EXISTS idx_eta_tenant_type
    ON core_mdm.entity_type_assignments (tenant_id, entity_type_code);
CREATE INDEX IF NOT EXISTS idx_eta_identity
    ON core_mdm.entity_type_assignments (identity_id);

-- ── 6. Entity approval requests (data governance — steward→owner workflow) ────
CREATE TABLE IF NOT EXISTS core_mdm.entity_approval_requests (
    request_id       UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id        UUID        NOT NULL,
    entity_id        UUID        NOT NULL,
    entity_type_code TEXT        NOT NULL,
    submitted_by     UUID        NOT NULL REFERENCES core_mdm.identities(identity_id),
    submitted_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_by      UUID        REFERENCES core_mdm.identities(identity_id),
    reviewed_at      TIMESTAMPTZ,
    status           TEXT        NOT NULL DEFAULT 'pending'
                                 CHECK (status IN ('pending', 'approved', 'rejected')),
    reviewer_notes   TEXT,
    change_summary   TEXT
);

CREATE UNIQUE INDEX IF NOT EXISTS entity_approval_requests_pending_idx
    ON core_mdm.entity_approval_requests (entity_id)
    WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_ear_tenant_status
    ON core_mdm.entity_approval_requests (tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_ear_submitted_by
    ON core_mdm.entity_approval_requests (submitted_by);

-- ── 7. Notifications schema and tables ───────────────────────────────────────
-- The retention function in migration 0030 creates functions in the notifications
-- schema; this provides the schema and delivery_log table for full functionality.

CREATE SCHEMA IF NOT EXISTS notifications;

CREATE TABLE IF NOT EXISTS notifications.webhook_subscriptions (
    subscription_id UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL REFERENCES core_mdm.tenants(tenant_id) ON DELETE CASCADE,
    url             TEXT        NOT NULL,
    event_types     TEXT[]      NOT NULL DEFAULT '{}',
    secret          TEXT,
    enabled         BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_webhook_subs_tenant
    ON notifications.webhook_subscriptions (tenant_id)
    WHERE enabled = TRUE;

CREATE TABLE IF NOT EXISTS notifications.delivery_log (
    log_id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL,
    notification_id UUID,
    channel         TEXT        NOT NULL CHECK (channel IN ('websocket','email','webhook')),
    event_type      TEXT        NOT NULL,
    recipient       TEXT,
    status          TEXT        NOT NULL DEFAULT 'pending'
                                CHECK (status IN ('pending','delivered','failed','retrying')),
    attempts        INTEGER     NOT NULL DEFAULT 0,
    last_error      TEXT,
    payload         JSONB       NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    delivered_at    TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_delivery_log_tenant_channel
    ON notifications.delivery_log (tenant_id, channel, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_delivery_log_status
    ON notifications.delivery_log (status)
    WHERE status IN ('pending', 'retrying');
-- Retention index (would have been created by 0030 if the table existed then)
CREATE INDEX IF NOT EXISTS idx_delivery_log_cleanup
    ON notifications.delivery_log (status, created_at)
    WHERE status IN ('delivered', 'failed');

-- ── 8. Distribution jobs exponential backoff column ──────────────────────────
ALTER TABLE platform.distribution_jobs
    ADD COLUMN IF NOT EXISTS next_attempt_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_distribution_jobs_pending_retry
    ON platform.distribution_jobs (next_attempt_at)
    WHERE status = 'pending';
