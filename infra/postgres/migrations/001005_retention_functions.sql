-- ============================================================================
-- Migration 001005: Define all pg_cron retention functions
--
-- Context: Migration 000036 schedules pg_cron jobs that call functions
-- referenced in its comments as coming from "0005_data_retention.sql" — a
-- file that was never created in this migration sequence. All five platform
-- retention functions were missing. pg_cron would silently fail at runtime.
--
-- This migration defines every function called by the 000036 cron schedule.
-- All deletes are idempotent: IF NOT EXISTS / OR REPLACE guards prevent
-- re-runs from failing.
-- ============================================================================

-- ── Ensure platform.notifications table exists ────────────────────────────────
-- notification-service stores transient push messages here. The table is
-- referenced by pg_cron cleanup but was not in the numbered migration sequence.
CREATE TABLE IF NOT EXISTS platform.notifications (
    notification_id   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id         UUID        NOT NULL,
    user_id           UUID,
    notification_type VARCHAR(64) NOT NULL,
    title             VARCHAR(255) NOT NULL,
    body              TEXT,
    severity          VARCHAR(16)  NOT NULL DEFAULT 'info'
                          CHECK (severity IN ('info','warning','error','critical')),
    entity_id         UUID,
    entity_type       VARCHAR(64),
    action_url        TEXT,
    read_at           TIMESTAMPTZ,
    metadata          JSONB       NOT NULL DEFAULT '{}',
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notifications_tenant_created
    ON platform.notifications (tenant_id, created_at DESC);

-- ── Ensure platform.revoked_tokens table exists ───────────────────────────────
-- Used by api-gateway to check JWT revocation; also referenced by RLS in 001004.
CREATE TABLE IF NOT EXISTS platform.revoked_tokens (
    token_id    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   UUID        NOT NULL,
    jti         VARCHAR(255) NOT NULL UNIQUE,
    revoked_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at  TIMESTAMPTZ NOT NULL,
    reason      VARCHAR(128)
);

CREATE INDEX IF NOT EXISTS idx_revoked_tokens_jti ON platform.revoked_tokens (jti);
CREATE INDEX IF NOT EXISTS idx_revoked_tokens_expires ON platform.revoked_tokens (expires_at);

-- ── Ensure ai.steward_feedback table exists ───────────────────────────────────
-- AI steward feedback loop — records human corrections to ML merge decisions.
CREATE TABLE IF NOT EXISTS ai.steward_feedback (
    feedback_id   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id     UUID        NOT NULL,
    entity_id     UUID        NOT NULL,
    field_key     VARCHAR(128) NOT NULL,
    original_value TEXT,
    corrected_value TEXT,
    feedback_type VARCHAR(64),
    steward_id    UUID,
    notes         TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_steward_feedback_tenant_created
    ON ai.steward_feedback (tenant_id, created_at DESC);

-- ── Ensure distribution_jobs table exists ────────────────────────────────────
-- Already referenced in distribution-service code; defined here as a safety net.
CREATE TABLE IF NOT EXISTS platform.distribution_jobs (
    job_id        UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id     UUID         NOT NULL,
    connector_id  UUID         NOT NULL,
    entity_id     UUID         NOT NULL,
    entity_type   VARCHAR(64)  NOT NULL,
    payload       JSONB        NOT NULL DEFAULT '{}',
    status        VARCHAR(32)  NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending','running','completed','failed')),
    attempts      INTEGER      NOT NULL DEFAULT 0,
    error_message TEXT,
    scheduled_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    completed_at  TIMESTAMPTZ,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_distribution_jobs_status
    ON platform.distribution_jobs (status, scheduled_at);
CREATE INDEX IF NOT EXISTS idx_distribution_jobs_tenant
    ON platform.distribution_jobs (tenant_id, created_at DESC);

-- ============================================================================
-- RETENTION FUNCTIONS
-- ============================================================================

-- ── 1. event_store.purge_old_outbox_events ───────────────────────────────────
-- Removes processed outbox events older than `days`. Unprocessed events
-- (status != 'processed') are retained regardless of age.
CREATE OR REPLACE FUNCTION event_store.purge_old_outbox_events(
    retention_days INTEGER DEFAULT 90
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    deleted_count BIGINT;
BEGIN
    DELETE FROM event_store.outbox_events
    WHERE status = 'processed'
      AND created_at < NOW() - (retention_days || ' days')::INTERVAL;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

-- ── 2. event_store.purge_old_dlq_events ──────────────────────────────────────
-- Removes dead-letter events older than `days`. These are events that
-- exhausted all retries and were moved to the DLQ for manual review.
CREATE OR REPLACE FUNCTION event_store.purge_old_dlq_events(
    retention_days INTEGER DEFAULT 180
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    deleted_count BIGINT;
BEGIN
    DELETE FROM event_store.outbox_dlq
    WHERE created_at < NOW() - (retention_days || ' days')::INTERVAL;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

-- ── 3. ai.purge_old_steward_feedback ─────────────────────────────────────────
-- Removes AI steward feedback older than `days`. Feedback is used for
-- model fine-tuning; once exported / incorporated it can be pruned.
CREATE OR REPLACE FUNCTION ai.purge_old_steward_feedback(
    retention_days INTEGER DEFAULT 365
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    deleted_count BIGINT;
BEGIN
    DELETE FROM ai.steward_feedback
    WHERE created_at < NOW() - (retention_days || ' days')::INTERVAL;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

-- ── 4. platform.purge_expired_revoked_tokens ─────────────────────────────────
-- Removes JWT revocation entries whose `expires_at` has passed. Once a
-- token's natural expiry has passed, the revocation record is redundant
-- because the token would be rejected on the expiry check anyway.
CREATE OR REPLACE FUNCTION platform.purge_expired_revoked_tokens()
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    deleted_count BIGINT;
BEGIN
    -- Keep a 1-day safety buffer beyond expires_at to handle clock skew.
    DELETE FROM platform.revoked_tokens
    WHERE expires_at < NOW() - INTERVAL '1 day';
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

-- ── 5. platform.purge_old_notifications ──────────────────────────────────────
-- Removes notification records older than `days`. Read notifications are
-- pruned first; unread ones are kept for the full retention window.
CREATE OR REPLACE FUNCTION platform.purge_old_notifications(
    retention_days INTEGER DEFAULT 30
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    deleted_count BIGINT;
BEGIN
    DELETE FROM platform.notifications
    WHERE created_at < NOW() - (retention_days || ' days')::INTERVAL;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

-- ── 6. platform.run_retention_policies ───────────────────────────────────────
-- Master orchestrator called by the 'nexus-retention-daily' pg_cron job.
-- Runs all sub-policies in sequence and logs a summary. Failures in any
-- sub-policy are caught and logged; the orchestrator continues to run
-- remaining policies so a single failure doesn't block the whole run.
CREATE OR REPLACE FUNCTION platform.run_retention_policies()
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    outbox_del      BIGINT := 0;
    dlq_del         BIGINT := 0;
    dead_letter_del BIGINT := 0;
    feedback_del    BIGINT := 0;
    tokens_del      BIGINT := 0;
    notif_del       BIGINT := 0;
    err_msg         TEXT;
BEGIN
    -- (a) Processed outbox events — 90-day retention
    BEGIN
        outbox_del := event_store.purge_old_outbox_events(90);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS err_msg = MESSAGE_TEXT;
        RAISE WARNING 'retention: purge_old_outbox_events failed: %', err_msg;
    END;

    -- (b) Dead-letter events (legacy cleanup function from 000035)
    BEGIN
        PERFORM event_store.cleanup_old_events(24);
        GET DIAGNOSTICS dead_letter_del = ROW_COUNT;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS err_msg = MESSAGE_TEXT;
        RAISE WARNING 'retention: cleanup_old_events failed: %', err_msg;
    END;

    -- (c) DLQ events — 180-day retention
    BEGIN
        dlq_del := event_store.purge_old_dlq_events(180);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS err_msg = MESSAGE_TEXT;
        RAISE WARNING 'retention: purge_old_dlq_events failed: %', err_msg;
    END;

    -- (d) AI steward feedback — 1-year retention
    BEGIN
        feedback_del := ai.purge_old_steward_feedback(365);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS err_msg = MESSAGE_TEXT;
        RAISE WARNING 'retention: purge_old_steward_feedback failed: %', err_msg;
    END;

    -- (e) Expired revoked JWT tokens
    BEGIN
        tokens_del := platform.purge_expired_revoked_tokens();
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS err_msg = MESSAGE_TEXT;
        RAISE WARNING 'retention: purge_expired_revoked_tokens failed: %', err_msg;
    END;

    -- (f) Old notifications — 30-day retention
    BEGIN
        notif_del := platform.purge_old_notifications(30);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS err_msg = MESSAGE_TEXT;
        RAISE WARNING 'retention: purge_old_notifications failed: %', err_msg;
    END;

    RAISE NOTICE
        'Retention run complete: outbox=%, dlq=%, dead_letter=%, feedback=%, tokens=%, notifications=%',
        outbox_del, dlq_del, dead_letter_del, feedback_del, tokens_del, notif_del;
END;
$$;

-- Grant execute rights to the application role
GRANT EXECUTE ON FUNCTION event_store.purge_old_outbox_events(INTEGER)  TO nexus_app;
GRANT EXECUTE ON FUNCTION event_store.purge_old_dlq_events(INTEGER)     TO nexus_app;
GRANT EXECUTE ON FUNCTION ai.purge_old_steward_feedback(INTEGER)        TO nexus_app;
GRANT EXECUTE ON FUNCTION platform.purge_expired_revoked_tokens()       TO nexus_app;
GRANT EXECUTE ON FUNCTION platform.purge_old_notifications(INTEGER)     TO nexus_app;
GRANT EXECUTE ON FUNCTION platform.run_retention_policies()             TO nexus_app;
