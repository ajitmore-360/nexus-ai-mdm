-- =============================================================================
-- Migration: 0005_data_retention
-- GDPR Art.5(1)(e): Data minimisation / storage limitation.
-- Implements automated data retention policies using pg_cron or a scheduled
-- application job.  Tables accumulate indefinitely without these policies.
-- =============================================================================

-- ── Retention constants (adjust per tenant policy / regulatory requirements) ─

-- Outbox events: keep 90 days of published events for debugging / audit
-- Unpublished (pending) events must never be purged automatically.
CREATE OR REPLACE FUNCTION event_store.purge_old_outbox_events(retention_days INT DEFAULT 90)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    deleted_count BIGINT;
BEGIN
    DELETE FROM event_store.outbox_events
    WHERE published    = TRUE
      AND published_at < NOW() - (retention_days || ' days')::INTERVAL;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

-- DLQ events: keep 180 days (longer — need time to investigate failures)
CREATE OR REPLACE FUNCTION event_store.purge_old_dlq_events(retention_days INT DEFAULT 180)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    deleted_count BIGINT;
BEGIN
    -- Only purge DLQ events that were replayed (resolved)
    DELETE FROM event_store.outbox_dlq
    WHERE replayed_at IS NOT NULL
      AND replayed_at < NOW() - (retention_days || ' days')::INTERVAL;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

-- AI steward feedback: keep 365 days for model training purposes
-- GDPR: steward feedback is business-operational data, not personal data
-- unless it links back to a specific data subject.
CREATE OR REPLACE FUNCTION ai.purge_old_steward_feedback(retention_days INT DEFAULT 365)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    deleted_count BIGINT;
BEGIN
    DELETE FROM ai.steward_feedback
    WHERE used_in_training = TRUE
      AND created_at < NOW() - (retention_days || ' days')::INTERVAL;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

-- Revoked JWT tokens: safe to purge after token max lifetime (7 days)
CREATE OR REPLACE FUNCTION platform.purge_expired_revoked_tokens()
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    deleted_count BIGINT;
BEGIN
    -- Refresh tokens max TTL is 7 days; revoked tokens older than 8 days
    -- can never be presented as valid, so safe to remove.
    DELETE FROM platform.revoked_tokens
    WHERE revoked_at < NOW() - INTERVAL '8 days';
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

-- Notification history: 30 days (UI only shows recent notifications)
CREATE OR REPLACE FUNCTION platform.purge_old_notifications(retention_days INT DEFAULT 30)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    deleted_count BIGINT;
BEGIN
    DELETE FROM platform.notifications
    WHERE read      = TRUE
      AND read_at  < NOW() - (retention_days || ' days')::INTERVAL;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

-- ── Master retention job — call this from pg_cron or application scheduler ──

CREATE OR REPLACE FUNCTION platform.run_retention_policies()
RETURNS TABLE(policy TEXT, deleted_count BIGINT)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY SELECT 'outbox_events_90d'::TEXT,
                        event_store.purge_old_outbox_events(90);
    RETURN QUERY SELECT 'dlq_events_180d'::TEXT,
                        event_store.purge_old_dlq_events(180);
    RETURN QUERY SELECT 'steward_feedback_365d'::TEXT,
                        ai.purge_old_steward_feedback(365);
    RETURN QUERY SELECT 'revoked_tokens_8d'::TEXT,
                        platform.purge_expired_revoked_tokens();
    RETURN QUERY SELECT 'notifications_30d'::TEXT,
                        platform.purge_old_notifications(30);
END;
$$;

COMMENT ON FUNCTION platform.run_retention_policies IS
    'GDPR Art.5(1)(e) — Storage limitation. Run daily via pg_cron: '
    'SELECT cron.schedule(''retention-daily'', ''0 2 * * *'', ''SELECT * FROM platform.run_retention_policies()'')';

-- ── Indices to make retention queries efficient ───────────────────────────────

CREATE INDEX IF NOT EXISTS idx_outbox_events_published_at
    ON event_store.outbox_events (published_at)
    WHERE published = TRUE;

CREATE INDEX IF NOT EXISTS idx_steward_feedback_retention
    ON ai.steward_feedback (created_at, used_in_training)
    WHERE used_in_training = TRUE;

CREATE INDEX IF NOT EXISTS idx_revoked_tokens_cleanup
    ON platform.revoked_tokens (revoked_at);

CREATE INDEX IF NOT EXISTS idx_notifications_cleanup
    ON platform.notifications (read_at)
    WHERE read = TRUE;
