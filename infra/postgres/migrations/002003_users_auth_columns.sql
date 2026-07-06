-- ============================================================================
-- Migration 002003: Add authentication columns to core_mdm.users
--
-- The application code (handlers/users.rs) already references password_hash,
-- display_name, role, and last_login_at — but the original migration 000004
-- used full_name / role_name and had no password column.  This migration adds
-- the missing columns and seeds display_name from full_name for existing rows.
-- ============================================================================

ALTER TABLE core_mdm.users
    ADD COLUMN IF NOT EXISTS password_hash  TEXT,
    ADD COLUMN IF NOT EXISTS display_name   VARCHAR(255),
    ADD COLUMN IF NOT EXISTS role           VARCHAR(100) NOT NULL DEFAULT 'viewer',
    ADD COLUMN IF NOT EXISTS last_login_at  TIMESTAMPTZ;

-- Seed display_name from the legacy full_name column for existing rows.
UPDATE core_mdm.users
   SET display_name = full_name
 WHERE display_name IS NULL
   AND full_name IS NOT NULL;

-- Index for fast invite-token lookups (used by POST /auth/accept-invite).
CREATE INDEX IF NOT EXISTS idx_users_email_status
    ON core_mdm.users (email, status);

-- ── User invitations ─────────────────────────────────────────────────────────
-- Stores single-use invite tokens generated when an Admin invites a new user.
-- The accept-invite endpoint validates this token and sets the user's password.

CREATE TABLE IF NOT EXISTS core_mdm.user_invitations (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID        NOT NULL REFERENCES core_mdm.users(user_id) ON DELETE CASCADE,
    tenant_id       UUID        NOT NULL,
    token           TEXT        NOT NULL UNIQUE,
    expires_at      TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '7 days'),
    accepted_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_invitations_token
    ON core_mdm.user_invitations (token)
    WHERE accepted_at IS NULL;
