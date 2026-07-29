-- =============================================================================
-- Migration 002029: Retention and cleanup improvements
--
-- Adds retention functions for tables that had no cleanup at all:
--   • core_mdm.match_requests (+ cascades to candidates + field results)
--   • notifications.delivery_log
--   • ai.anomalies (resolved rows)
--   • ingest.ingest_jobs (terminal-state rows)
--
-- Fixes the outbox_events purge function (column name ambiguity between the
-- two migration streams).
--
-- Registers/updates a pg_cron daily sweep that calls all retention policies.
-- =============================================================================

-- ── 1. Matching transient cleanup ─────────────────────────────────────────────
-- CASCADE on match_requests → match_candidates → field_match_results covers
-- all three tables with a single DELETE on the parent.
CREATE OR REPLACE FUNCTION core_mdm.purge_old_match_data(retention_days INT DEFAULT 90)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    deleted BIGINT;
BEGIN
    DELETE FROM core_mdm.match_requests
    WHERE status IN (
        'completed', 'reviewed', 'merged', 'rejected', 'auto_merged',
        'AutoMerged', 'Merged', 'Reviewed', 'Rejected'
    )
    AND created_at < NOW() - (retention_days || ' days')::INTERVAL;
    GET DIAGNOSTICS deleted = ROW_COUNT;
    RETURN deleted;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_match_requests_cleanup
    ON core_mdm.match_requests (status, created_at)
    WHERE status IN (
        'completed', 'reviewed', 'merged', 'rejected', 'auto_merged',
        'AutoMerged', 'Merged', 'Reviewed', 'Rejected'
    );

-- ── 2. Delivery log retention ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION notifications.purge_old_delivery_log(retention_days INT DEFAULT 30)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    deleted BIGINT;
BEGIN
    DELETE FROM notifications.delivery_log
    WHERE status IN ('delivered', 'failed')
      AND created_at < NOW() - (retention_days || ' days')::INTERVAL;
    GET DIAGNOSTICS deleted = ROW_COUNT;
    RETURN deleted;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_delivery_log_cleanup
    ON notifications.delivery_log (status, created_at)
    WHERE status IN ('delivered', 'failed');

-- ── 3. Resolved anomaly cleanup ───────────────────────────────────────────────
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'ai' AND table_name = 'anomalies'
    ) THEN
        CREATE OR REPLACE FUNCTION ai.purge_resolved_anomalies(retention_days INT DEFAULT 90)
        RETURNS BIGINT
        LANGUAGE plpgsql
        SECURITY DEFINER
        AS $fn$
        DECLARE
            deleted BIGINT;
        BEGIN
            DELETE FROM ai.anomalies
            WHERE resolved = TRUE
              AND resolved_at < NOW() - (retention_days || ' days')::INTERVAL;
            GET DIAGNOSTICS deleted = ROW_COUNT;
            RETURN deleted;
        END;
        $fn$;
    END IF;
END $$;

-- ── 4. Fix outbox_events purge (handles both column naming conventions) ────────
CREATE OR REPLACE FUNCTION event_store.purge_old_outbox_events(retention_days INT DEFAULT 90)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    deleted BIGINT;
BEGIN
    DELETE FROM event_store.outbox_events
    WHERE (status = 'published' OR published = TRUE)
      AND published_at IS NOT NULL
      AND published_at < NOW() - (retention_days || ' days')::INTERVAL;
    GET DIAGNOSTICS deleted = ROW_COUNT;
    RETURN deleted;
END;
$$;

-- ── 5. Ingest job cleanup ─────────────────────────────────────────────────────
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'ingest' AND table_name = 'ingest_jobs'
    ) THEN
        CREATE OR REPLACE FUNCTION ingest.purge_old_ingest_jobs(retention_days INT DEFAULT 180)
        RETURNS BIGINT
        LANGUAGE plpgsql
        SECURITY DEFINER
        AS $fn$
        DECLARE
            deleted BIGINT;
        BEGIN
            DELETE FROM ingest.ingest_jobs
            WHERE status IN ('completed', 'partial_success', 'failed')
              AND created_at < NOW() - (retention_days || ' days')::INTERVAL;
            GET DIAGNOSTICS deleted = ROW_COUNT;
            RETURN deleted;
        END;
        $fn$;

        CREATE INDEX IF NOT EXISTS idx_ingest_jobs_cleanup
            ON ingest.ingest_jobs (status, created_at)
            WHERE status IN ('completed', 'partial_success', 'failed');
    END IF;
END $$;

-- ── 6. pg_cron daily sweep ────────────────────────────────────────────────────
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        -- Remove any existing schedule with this name to avoid duplicates
        PERFORM cron.unschedule('nexus-retention-daily')
        FROM cron.job WHERE jobname = 'nexus-retention-daily';

        PERFORM cron.schedule(
            'nexus-retention-daily',
            '0 2 * * *',
            $$
            SELECT event_store.purge_old_outbox_events(90);
            SELECT event_store.cleanup_old_events(720);
            SELECT core_mdm.purge_old_match_data(90);
            SELECT notifications.purge_old_delivery_log(30);
            $$
        );
    END IF;
END $$;
