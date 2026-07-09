-- ============================================================================
-- Azile MDM â€” pg_cron Scheduled Retention Jobs
-- Migration: 000036
-- ============================================================================
-- Requires: pg_cron extension; must run as superuser or pg_cron owner.
-- The retention functions (platform.run_retention_policies, etc.) are defined
-- in 000035_create_retention_function.sql and 0005_data_retention.sql.
--
-- To verify jobs after migration:
--   SELECT * FROM cron.job;
--   SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 20;
-- ============================================================================

-- Enable pg_cron (idempotent; safe to run on existing installations)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Grant usage to migration role so this script can proceed
GRANT USAGE ON SCHEMA cron TO azile_app;

-- â”€â”€ Remove stale jobs (allows re-running this migration safely) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname IN (
    'nexus-retention-daily',
    'nexus-audit-cleanup',
    'nexus-revoked-tokens-cleanup',
    'nexus-notifications-cleanup'
);

-- â”€â”€ Master retention policy: runs ALL sub-policies in sequence â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Runs at 02:00 UTC daily.  Calls platform.run_retention_policies() which
-- internally invokes:
--   event_store.cleanup_old_events(24)          â†’ keep 24 months
--   event_store.purge_old_outbox_events(90)     â†’ keep 90 days
--   event_store.purge_old_dlq_events(180)       â†’ keep 180 days
--   ai.purge_old_steward_feedback(365)          â†’ keep 1 year
--   platform.purge_expired_revoked_tokens()     â†’ clear tokens > 8 days
--   platform.purge_old_notifications(30)        â†’ keep 30 days
SELECT cron.schedule(
    'nexus-retention-daily',
    '0 2 * * *',
    $$SELECT platform.run_retention_policies()$$
);

-- â”€â”€ Audit log pruning: separate job so a slow retention run doesn't block it â”€
-- Keeps the last 90 days of audit logs.
-- Runs at 03:00 UTC daily (1 hour after master policy to stagger DB load).
SELECT cron.schedule(
    'nexus-audit-cleanup',
    '0 3 * * *',
    $$
    DELETE FROM audit.audit_logs
    WHERE created_at < NOW() - INTERVAL '90 days';

    DELETE FROM audit.audit_log
    WHERE changed_at < NOW() - INTERVAL '90 days';
    $$
);

-- â”€â”€ Revoked JWT tokens: short TTL, run more frequently â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Runs every hour at :15 past to avoid concurrent execution with the daily job.
SELECT cron.schedule(
    'nexus-revoked-tokens-cleanup',
    '15 * * * *',
    $$SELECT platform.purge_expired_revoked_tokens()$$
);

-- â”€â”€ Notification pruning: run nightly â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Keeps the last 30 days; runs at 04:00 UTC.
SELECT cron.schedule(
    'nexus-notifications-cleanup',
    '0 4 * * *',
    $$SELECT platform.purge_old_notifications(30)$$
);

-- â”€â”€ Verify scheduled jobs â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
DO $$
DECLARE
    job_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO job_count
    FROM cron.job
    WHERE jobname IN (
        'nexus-retention-daily',
        'nexus-audit-cleanup',
        'nexus-revoked-tokens-cleanup',
        'nexus-notifications-cleanup'
    );

    IF job_count < 4 THEN
        RAISE EXCEPTION
            'pg_cron schedule failed: expected 4 jobs, found %', job_count;
    END IF;

    RAISE NOTICE 'pg_cron: % retention jobs scheduled successfully.', job_count;
END
$$;
