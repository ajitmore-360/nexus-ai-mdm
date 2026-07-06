-- ============================================================
-- In-app notification inbox for the UI bell / toast system.
-- Delivery channels (webhooks, email) live in notifications.delivery_log (002006).
-- ============================================================

CREATE TABLE IF NOT EXISTS notifications.inbox (
    notification_id UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL REFERENCES core_mdm.tenants(tenant_id) ON DELETE CASCADE,
    user_id         UUID,                               -- NULL = broadcast to all tenant admins
    event_type      TEXT        NOT NULL,               -- e.g. 'quota.records.warning_80pct'
    title           TEXT        NOT NULL,
    body            TEXT        NOT NULL,
    severity        TEXT        NOT NULL DEFAULT 'info'
                                CHECK (severity IN ('info','warning','error','critical')),
    is_read         BOOLEAN     NOT NULL DEFAULT FALSE,
    metadata        JSONB       NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    read_at         TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_notifications_inbox_tenant_unread
    ON notifications.inbox (tenant_id, created_at DESC)
    WHERE is_read = FALSE;

CREATE INDEX IF NOT EXISTS idx_notifications_inbox_type
    ON notifications.inbox (tenant_id, event_type, created_at DESC);

COMMENT ON TABLE notifications.inbox IS
    'In-app notifications shown in the UI bell / toast system.  '
    'One row per notification event per tenant.';
