-- ============================================================
-- POLICY RULES TABLE
-- File: 000038_create_policy_rules.sql
-- Application-level governance rules (FieldMask, SurvivorshipOverride,
-- AccessControl, GdprConsent) managed via the Governance Center UI.
-- ============================================================

CREATE TABLE IF NOT EXISTS core_mdm.policy_rules (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   UUID        NOT NULL,
    name        TEXT        NOT NULL,
    rule_type   TEXT        NOT NULL,
    entity_type TEXT        NOT NULL DEFAULT 'Any',
    field_name  TEXT,
    rego_policy TEXT        NOT NULL DEFAULT '',
    priority    INTEGER     NOT NULL DEFAULT 50,
    is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_policy_rule_tenant
        FOREIGN KEY (tenant_id)
        REFERENCES core_mdm.tenants(tenant_id)
        ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_policy_rules_tenant
    ON core_mdm.policy_rules(tenant_id);

CREATE INDEX IF NOT EXISTS idx_policy_rules_is_active
    ON core_mdm.policy_rules(tenant_id, is_active);

CREATE OR REPLACE FUNCTION core_mdm.set_policy_rules_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_policy_rules_updated_at ON core_mdm.policy_rules;
CREATE TRIGGER trg_policy_rules_updated_at
    BEFORE UPDATE ON core_mdm.policy_rules
    FOR EACH ROW EXECUTE FUNCTION core_mdm.set_policy_rules_updated_at();

ALTER TABLE core_mdm.policy_rules ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_policy_rules ON core_mdm.policy_rules
    USING (tenant_id = app_context.current_tenant());

CREATE POLICY tenant_insert_policy_rules ON core_mdm.policy_rules
    FOR INSERT WITH CHECK (tenant_id = app_context.current_tenant());

CREATE POLICY tenant_update_policy_rules ON core_mdm.policy_rules
    FOR UPDATE USING (tenant_id = app_context.current_tenant());

CREATE POLICY tenant_delete_policy_rules ON core_mdm.policy_rules
    FOR DELETE USING (tenant_id = app_context.current_tenant());
