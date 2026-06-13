-- =============================================================================
-- Migration: 0004_outbox_dlq_and_compat
-- Adds published/retry_count columns to outbox_events for kafka-event-service
-- compatibility, and creates the dead-letter queue table.
-- =============================================================================

-- ── Add backward-compat columns to outbox_events ──────────────────────────

ALTER TABLE event_store.outbox_events
    ADD COLUMN IF NOT EXISTS published    BOOLEAN     NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS retry_count  INT         NOT NULL DEFAULT 0;

-- Sync the published flag from the status column for existing rows
UPDATE event_store.outbox_events
SET published = TRUE
WHERE status = 'published'
  AND published = FALSE;

-- Index for the polling query used by kafka-event-service
CREATE INDEX IF NOT EXISTS idx_outbox_unpublished
    ON event_store.outbox_events (created_at ASC)
    WHERE published = FALSE;

-- ── Dead-Letter Queue ────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS event_store.outbox_dlq (
    dlq_id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id        UUID        NOT NULL UNIQUE,
    tenant_id       UUID        NOT NULL,
    aggregate_type  TEXT        NOT NULL,
    aggregate_id    UUID        NOT NULL,
    event_type      TEXT        NOT NULL,
    event_payload   JSONB       NOT NULL,
    topic_name      TEXT        NOT NULL,
    retry_count     INT         NOT NULL DEFAULT 0,
    failure_reason  TEXT,
    moved_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    replayed_at     TIMESTAMPTZ,
    replayed_by     UUID
);

CREATE INDEX IF NOT EXISTS idx_outbox_dlq_tenant
    ON event_store.outbox_dlq (tenant_id, moved_at DESC);

COMMENT ON TABLE event_store.outbox_dlq
    IS 'Dead-letter queue for outbox events that exceeded max publish retries';

-- ── JWT secret table (for token revocation list) ──────────────────────────

CREATE TABLE IF NOT EXISTS platform.revoked_tokens (
    jti         UUID        PRIMARY KEY,
    user_id     UUID        NOT NULL,
    tenant_id   UUID        NOT NULL,
    revoked_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reason      TEXT
);

CREATE INDEX IF NOT EXISTS idx_revoked_tokens_user
    ON platform.revoked_tokens (user_id, revoked_at DESC);

-- Automatically purge tokens older than 30 days (cron or pg_cron can run this)
COMMENT ON TABLE platform.revoked_tokens
    IS 'Revoked JWT token JTIs — checked on every authenticated request';

-- ── User password hashes ────────────────────────────────────────────────────

ALTER TABLE core_mdm.users
    ADD COLUMN IF NOT EXISTS password_hash TEXT,
    ADD COLUMN IF NOT EXISTS is_verified   BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS verified_at   TIMESTAMPTZ;

COMMENT ON COLUMN core_mdm.users.password_hash
    IS 'bcrypt hash of the user password (cost 12). Never store plaintext.';
