-- ─────────────────────────────────────────────────────────────────────────────
-- 0022: Task Assignment & SLA Engine + Reference Data Management
-- ─────────────────────────────────────────────────────────────────────────────

-- ── TASK ASSIGNMENT ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS core_mdm.tasks (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id        UUID        NOT NULL REFERENCES core_mdm.tenants(tenant_id),
    title            TEXT        NOT NULL,
    description      TEXT,
    task_type        VARCHAR(50) NOT NULL DEFAULT 'Manual'
                                 CHECK (task_type IN ('Review','Stewardship','Enrichment','Deduplication','Approval','Manual')),
    status           VARCHAR(20) NOT NULL DEFAULT 'Open'
                                 CHECK (status IN ('Open','InProgress','Completed','Cancelled','Escalated')),
    priority         SMALLINT    NOT NULL DEFAULT 2 CHECK (priority BETWEEN 1 AND 5),
    -- Related entity/entity_type context
    entity_id        UUID        REFERENCES core_mdm.entities(entity_id) ON DELETE SET NULL,
    entity_type      VARCHAR(100),
    -- Assignment
    assignee_id      UUID,
    assignee_name    VARCHAR(255),
    assigned_by      UUID,
    assigned_at      TIMESTAMPTZ,
    -- SLA tracking
    due_at           TIMESTAMPTZ,
    sla_breached     BOOLEAN     NOT NULL DEFAULT FALSE,
    escalation_at    TIMESTAMPTZ,
    escalated_to     UUID,
    -- Outcome
    completed_by     UUID,
    completed_at     TIMESTAMPTZ,
    resolution_note  TEXT,
    -- Metadata
    metadata         JSONB       NOT NULL DEFAULT '{}',
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tasks_assignee
    ON core_mdm.tasks (tenant_id, assignee_id, status);

CREATE INDEX IF NOT EXISTS idx_tasks_entity
    ON core_mdm.tasks (tenant_id, entity_id)
    WHERE entity_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_tasks_due
    ON core_mdm.tasks (tenant_id, due_at, status)
    WHERE status NOT IN ('Completed','Cancelled');

ALTER TABLE core_mdm.tasks ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON core_mdm.tasks
    USING (tenant_id = current_setting('app.current_tenant', true)::uuid);

-- ── REFERENCE DATA MANAGEMENT ────────────────────────────────────────────────
-- Code lists: e.g., Country codes, Currency codes, Industry codes, Status values
CREATE TABLE IF NOT EXISTS core_mdm.reference_lists (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id        UUID        NOT NULL REFERENCES core_mdm.tenants(tenant_id),
    list_code        VARCHAR(100) NOT NULL,       -- e.g., 'ISO_COUNTRY', 'CURRENCY_CODE'
    list_name        VARCHAR(255) NOT NULL,
    description      TEXT,
    version          VARCHAR(20) NOT NULL DEFAULT '1.0',
    is_system        BOOLEAN     NOT NULL DEFAULT FALSE, -- system-managed vs tenant-custom
    is_active        BOOLEAN     NOT NULL DEFAULT TRUE,
    metadata         JSONB       NOT NULL DEFAULT '{}',
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_ref_list UNIQUE (tenant_id, list_code)
);

CREATE TABLE IF NOT EXISTS core_mdm.reference_values (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id        UUID        NOT NULL REFERENCES core_mdm.tenants(tenant_id),
    list_id          UUID        NOT NULL REFERENCES core_mdm.reference_lists(id) ON DELETE CASCADE,
    code             VARCHAR(100) NOT NULL,        -- e.g., 'US', 'USD', 'TECH'
    label            VARCHAR(500) NOT NULL,         -- e.g., 'United States'
    description      TEXT,
    parent_code      VARCHAR(100),                  -- for hierarchical code lists
    sort_order       INTEGER     NOT NULL DEFAULT 0,
    is_active        BOOLEAN     NOT NULL DEFAULT TRUE,
    extra            JSONB       NOT NULL DEFAULT '{}', -- additional locale/region data
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_ref_value UNIQUE (tenant_id, list_id, code)
);

CREATE INDEX IF NOT EXISTS idx_ref_values_list
    ON core_mdm.reference_values (tenant_id, list_id, is_active, sort_order);

CREATE INDEX IF NOT EXISTS idx_ref_values_code
    ON core_mdm.reference_values (tenant_id, list_id, code);

ALTER TABLE core_mdm.reference_lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE core_mdm.reference_values ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON core_mdm.reference_lists
    USING (tenant_id = current_setting('app.current_tenant', true)::uuid);

CREATE POLICY tenant_isolation ON core_mdm.reference_values
    USING (tenant_id = current_setting('app.current_tenant', true)::uuid);

-- ── NOTIFICATION SUBSCRIPTIONS ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS core_mdm.notification_subscriptions (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id        UUID        NOT NULL REFERENCES core_mdm.tenants(tenant_id),
    subscriber_id    UUID        NOT NULL,           -- user or system
    subscriber_type  VARCHAR(20) NOT NULL DEFAULT 'User' CHECK (subscriber_type IN ('User','Webhook','Email')),
    -- What to watch
    event_types      TEXT[]      NOT NULL DEFAULT '{}',   -- ['EntityCreated','EntityMerged', ...]
    entity_type      VARCHAR(100),                          -- NULL = all types
    entity_id        UUID,                                  -- NULL = all entities
    -- Delivery
    delivery_channel VARCHAR(20) NOT NULL DEFAULT 'InApp' CHECK (delivery_channel IN ('InApp','Email','Webhook','Slack')),
    delivery_target  TEXT,                                  -- email addr, webhook URL, Slack channel
    is_active        BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_notif_subscriptions_unique
    ON core_mdm.notification_subscriptions (tenant_id, subscriber_id, event_types, entity_type, delivery_channel)
    WHERE entity_id IS NULL;

ALTER TABLE core_mdm.notification_subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON core_mdm.notification_subscriptions
    USING (tenant_id = current_setting('app.current_tenant', true)::uuid);
