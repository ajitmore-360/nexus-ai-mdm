-- ─────────────────────────────────────────────────────────────────────────────
-- Password reset tokens — one-time tokens for the forgot-password flow.
-- Tokens expire after 1 hour and are single-use (used_at set on consumption).
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.password_resets (
    id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID         NOT NULL REFERENCES core_mdm.users(user_id) ON DELETE CASCADE,
    tenant_id  UUID         NOT NULL,
    token      TEXT         NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ  NOT NULL,
    used_at    TIMESTAMPTZ,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_password_resets_token
    ON core_mdm.password_resets (token);

CREATE INDEX IF NOT EXISTS idx_password_resets_user_id
    ON core_mdm.password_resets (user_id);
