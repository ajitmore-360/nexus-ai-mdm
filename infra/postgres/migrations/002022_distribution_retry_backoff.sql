-- Distribution jobs: add next_attempt_at column for exponential backoff scheduling.
--
-- Without this column the worker retried failed jobs immediately on every 5-second
-- poll cycle with no backoff, and the CASE expression in mark_failed() set status
-- to 'failed' regardless of whether MAX_ATTEMPTS was reached (both CASE branches
-- returned the same value).  This migration fixes the data model so the worker can
-- implement the 5s → 25s → 125s backoff described in its comments.

ALTER TABLE platform.distribution_jobs
    ADD COLUMN IF NOT EXISTS next_attempt_at TIMESTAMPTZ;

-- Partial index: the worker only scans pending rows, so this is narrow and fast.
CREATE INDEX IF NOT EXISTS idx_distribution_jobs_pending_retry
    ON platform.distribution_jobs (next_attempt_at)
    WHERE status = 'pending';
