ALTER TABLE core_mdm.survivorship_rules
ENABLE ROW LEVEL SECURITY;

ALTER TABLE core_mdm.survivorship_field_decisions
ENABLE ROW LEVEL SECURITY;

ALTER TABLE event_store.outbox_events
ENABLE ROW LEVEL SECURITY;

ALTER TABLE event_store.dead_letter_events
ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tenant_isolation_policy
ON event_store.outbox_events;

CREATE POLICY tenant_isolation_policy
ON event_store.outbox_events
USING (
    tenant_id =
    current_setting(
        'app.current_tenant',
        true
    )::uuid
);

CREATE POLICY survivorship_rules_tenant_policy
ON core_mdm.survivorship_rules
USING (
    tenant_id =
    current_setting(
        'app.current_tenant',
        true
    )::uuid
);

CREATE POLICY survivorship_field_decisions_policy
ON core_mdm.survivorship_field_decisions
USING (
    tenant_id =
    current_setting(
        'app.current_tenant',
        true
    )::uuid
);