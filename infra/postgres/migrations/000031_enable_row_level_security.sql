ALTER TABLE core_mdm.entities ENABLE ROW LEVEL SECURITY;

ALTER TABLE core_mdm.entity_attributes ENABLE ROW LEVEL SECURITY;

ALTER TABLE core_mdm.golden_records ENABLE ROW LEVEL SECURITY;

ALTER TABLE core_mdm.survivorship_executions
ENABLE ROW LEVEL SECURITY;

ALTER TABLE core_mdm.survivorship_evaluations
ENABLE ROW LEVEL SECURITY;

ALTER TABLE core_mdm.survivorship_rules_audit
ENABLE ROW LEVEL SECURITY;

ALTER TABLE event_store.outbox_events
ENABLE ROW LEVEL SECURITY;