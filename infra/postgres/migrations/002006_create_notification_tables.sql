-- ============================================================
-- Notification service persistence
-- ============================================================

CREATE SCHEMA IF NOT EXISTS notifications;

-- Webhook endpoints registered by tenants for push delivery.
CREATE TABLE IF NOT EXISTS notifications.webhook_subscriptions (
    subscription_id UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL REFERENCES core_mdm.tenants(tenant_id) ON DELETE CASCADE,
    url             TEXT        NOT NULL,
    event_types     TEXT[]      NOT NULL DEFAULT '{}',  -- empty = all events
    secret          TEXT,                               -- HMAC-SHA256 signing secret
    enabled         BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_webhook_subs_tenant
    ON notifications.webhook_subscriptions (tenant_id)
    WHERE enabled = TRUE;

-- Delivery log: one row per notification × channel attempt.
CREATE TABLE IF NOT EXISTS notifications.delivery_log (
    log_id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL,
    notification_id UUID,
    channel         TEXT        NOT NULL CHECK (channel IN ('websocket','email','webhook')),
    event_type      TEXT        NOT NULL,
    recipient       TEXT,                               -- email address or webhook URL
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

COMMENT ON TABLE notifications.webhook_subscriptions IS
    'Tenant-registered webhook endpoints for push notification delivery.';
COMMENT ON TABLE notifications.delivery_log IS
    'Audit trail of every notification delivery attempt across all channels.';
