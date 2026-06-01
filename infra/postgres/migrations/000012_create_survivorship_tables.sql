--
-- ============================================================
-- SURVIVORSHIP TABLES
-- File: 000012_create_survivorship_tables.sql
-- ============================================================
--

CREATE SCHEMA IF NOT EXISTS core_mdm;

--
-- ============================================================
-- SURVIVORSHIP EXECUTIONS
-- ============================================================
--

CREATE TABLE IF NOT EXISTS core_mdm.survivorship_executions (

    execution_id UUID PRIMARY KEY,

    tenant_id UUID NOT NULL,

    golden_record_id UUID,

    success BOOLEAN NOT NULL DEFAULT TRUE,

    overall_confidence DOUBLE PRECISION,

    execution_time_ms BIGINT NOT NULL DEFAULT 0,

    summary TEXT,

    ai_assisted BOOLEAN NOT NULL DEFAULT FALSE,

    explainability_enabled BOOLEAN NOT NULL DEFAULT FALSE,

    engine_version VARCHAR(255) NOT NULL DEFAULT 'v1',

    warnings JSONB NOT NULL DEFAULT '[]'::JSONB,

    errors JSONB NOT NULL DEFAULT '[]'::JSONB,

    metadata JSONB NOT NULL DEFAULT '{}'::JSONB,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    deleted_at TIMESTAMPTZ,

    deleted_by UUID,

    CONSTRAINT fk_survivorship_execution_tenant
        FOREIGN KEY (tenant_id)
        REFERENCES core_mdm.tenants(tenant_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_survivorship_execution_golden_record
        FOREIGN KEY (golden_record_id)
        REFERENCES core_mdm.golden_records(golden_record_id)
        ON DELETE SET NULL
);

--
-- ============================================================
-- SURVIVORSHIP EVALUATIONS
-- ============================================================
--

CREATE TABLE IF NOT EXISTS core_mdm.survivorship_evaluations (

    evaluation_id UUID PRIMARY KEY,

    tenant_id UUID NOT NULL,

    execution_id UUID NOT NULL,

    rule_id UUID,

    attribute_name VARCHAR(255) NOT NULL,

    selected_value JSONB NOT NULL,

    selected_source VARCHAR(255),

    confidence_score DOUBLE PRECISION,

    survivorship_score DOUBLE PRECISION,

    ai_score DOUBLE PRECISION,

    reasoning TEXT,

    policy_decisions JSONB NOT NULL DEFAULT '[]'::JSONB,

    warnings JSONB NOT NULL DEFAULT '[]'::JSONB,

    manually_overridden BOOLEAN NOT NULL DEFAULT FALSE,

    overridden_by UUID,

    overridden_at TIMESTAMPTZ,

    evaluated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    metadata JSONB NOT NULL DEFAULT '{}'::JSONB,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    deleted_at TIMESTAMPTZ,

    deleted_by UUID,

    CONSTRAINT fk_survivorship_evaluation_tenant
        FOREIGN KEY (tenant_id)
        REFERENCES core_mdm.tenants(tenant_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_survivorship_evaluation_execution
        FOREIGN KEY (execution_id)
        REFERENCES core_mdm.survivorship_executions(execution_id)
        ON DELETE CASCADE
);

--
-- ============================================================
-- SURVIVORSHIP RULES
-- ============================================================
--

CREATE TABLE IF NOT EXISTS core_mdm.survivorship_rules (

    rule_id UUID PRIMARY KEY,

    tenant_id UUID NOT NULL,

    rule_name VARCHAR(255) NOT NULL,

    description TEXT,

    attribute_name VARCHAR(255) NOT NULL,

    strategy VARCHAR(100) NOT NULL,

    scope VARCHAR(100) NOT NULL,

    source_priority JSONB NOT NULL DEFAULT '[]'::JSONB,

    source_weights JSONB NOT NULL DEFAULT '{}'::JSONB,

    minimum_confidence DOUBLE PRECISION,

    ai_assisted BOOLEAN NOT NULL DEFAULT FALSE,

    explainability_enabled BOOLEAN NOT NULL DEFAULT FALSE,

    allow_manual_override BOOLEAN NOT NULL DEFAULT TRUE,

    status VARCHAR(100) NOT NULL,

    priority INTEGER NOT NULL DEFAULT 0,

    effective_from TIMESTAMPTZ,

    effective_to TIMESTAMPTZ,

    created_by UUID,

    audit JSONB NOT NULL DEFAULT '{}'::JSONB,

    metadata JSONB NOT NULL DEFAULT '{}'::JSONB,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    deleted_at TIMESTAMPTZ,

    deleted_by UUID,

    CONSTRAINT fk_survivorship_rule_tenant
        FOREIGN KEY (tenant_id)
        REFERENCES core_mdm.tenants(tenant_id)
        ON DELETE CASCADE
);

--
-- ============================================================
-- SURVIVORSHIP RULE AUDIT
-- ============================================================
--

CREATE TABLE IF NOT EXISTS core_mdm.survivorship_rules_audit (

    audit_id UUID PRIMARY KEY,

    tenant_id UUID NOT NULL,

    execution_id UUID NOT NULL,

    rule_id UUID NOT NULL,

    rule_name VARCHAR(255) NOT NULL,

    strategy VARCHAR(100) NOT NULL,

    priority INTEGER NOT NULL DEFAULT 0,

    enabled BOOLEAN NOT NULL DEFAULT TRUE,

    metadata JSONB NOT NULL DEFAULT '{}'::JSONB,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_survivorship_rule_audit_tenant
        FOREIGN KEY (tenant_id)
        REFERENCES core_mdm.tenants(tenant_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_survivorship_rule_audit_execution
        FOREIGN KEY (execution_id)
        REFERENCES core_mdm.survivorship_executions(execution_id)
        ON DELETE CASCADE
);

--
-- ============================================================
-- SURVIVORSHIP FIELD DECISIONS
-- ============================================================
--

CREATE TABLE IF NOT EXISTS core_mdm.survivorship_field_decisions (

    decision_id UUID PRIMARY KEY,

    tenant_id UUID NOT NULL,

    execution_id UUID NOT NULL,

    field_name VARCHAR(255) NOT NULL,

    selected_entity_id UUID,

    selected_value JSONB NOT NULL,

    strategy VARCHAR(100) NOT NULL,

    confidence_score DOUBLE PRECISION,

    explanation TEXT,

    metadata JSONB NOT NULL DEFAULT '{}'::JSONB,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_survivorship_field_decision_tenant
        FOREIGN KEY (tenant_id)
        REFERENCES core_mdm.tenants(tenant_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_survivorship_field_decision_execution
        FOREIGN KEY (execution_id)
        REFERENCES core_mdm.survivorship_executions(execution_id)
        ON DELETE CASCADE
);

--
-- ============================================================
-- INDEXES
-- ============================================================
--

CREATE INDEX IF NOT EXISTS idx_survivorship_executions_tenant
ON core_mdm.survivorship_executions(tenant_id);

CREATE INDEX IF NOT EXISTS idx_survivorship_executions_golden_record
ON core_mdm.survivorship_executions(golden_record_id);

CREATE INDEX IF NOT EXISTS idx_survivorship_executions_created_at
ON core_mdm.survivorship_executions(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_survivorship_executions_success
ON core_mdm.survivorship_executions(success);

CREATE INDEX IF NOT EXISTS idx_survivorship_evaluations_execution
ON core_mdm.survivorship_evaluations(execution_id);

CREATE INDEX IF NOT EXISTS idx_survivorship_evaluations_tenant
ON core_mdm.survivorship_evaluations(tenant_id);

CREATE INDEX IF NOT EXISTS idx_survivorship_evaluations_attribute
ON core_mdm.survivorship_evaluations(attribute_name);

CREATE INDEX IF NOT EXISTS idx_survivorship_rules_tenant
ON core_mdm.survivorship_rules(tenant_id);

CREATE INDEX IF NOT EXISTS idx_survivorship_rules_attribute
ON core_mdm.survivorship_rules(attribute_name);

CREATE INDEX IF NOT EXISTS idx_survivorship_rules_strategy
ON core_mdm.survivorship_rules(strategy);

CREATE INDEX IF NOT EXISTS idx_survivorship_rules_status
ON core_mdm.survivorship_rules(status);

CREATE INDEX IF NOT EXISTS idx_survivorship_rules_priority
ON core_mdm.survivorship_rules(priority DESC);

CREATE INDEX IF NOT EXISTS idx_survivorship_rules_audit_execution
ON core_mdm.survivorship_rules_audit(execution_id);

CREATE INDEX IF NOT EXISTS idx_survivorship_field_decisions_execution
ON core_mdm.survivorship_field_decisions(execution_id);

CREATE INDEX IF NOT EXISTS idx_survivorship_field_decisions_field
ON core_mdm.survivorship_field_decisions(field_name);

--
-- ============================================================
-- JSONB GIN INDEXES
-- ============================================================
--

CREATE INDEX IF NOT EXISTS idx_survivorship_execution_metadata_gin
ON core_mdm.survivorship_executions
USING GIN(metadata);

CREATE INDEX IF NOT EXISTS idx_survivorship_evaluation_metadata_gin
ON core_mdm.survivorship_evaluations
USING GIN(metadata);

CREATE INDEX IF NOT EXISTS idx_survivorship_rules_metadata_gin
ON core_mdm.survivorship_rules
USING GIN(metadata);

CREATE INDEX IF NOT EXISTS idx_survivorship_rules_source_priority_gin
ON core_mdm.survivorship_rules
USING GIN(source_priority);

CREATE INDEX IF NOT EXISTS idx_survivorship_rules_source_weights_gin
ON core_mdm.survivorship_rules
USING GIN(source_weights);

CREATE INDEX IF NOT EXISTS idx_survivorship_field_decisions_metadata_gin
ON core_mdm.survivorship_field_decisions
USING GIN(metadata);

--
-- ============================================================
-- UPDATED_AT TRIGGER
-- ============================================================
--

CREATE OR REPLACE FUNCTION core_mdm.update_updated_at_column()
RETURNS TRIGGER AS
$$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_survivorship_executions_updated_at
ON core_mdm.survivorship_executions;

CREATE TRIGGER trg_survivorship_executions_updated_at
BEFORE UPDATE
ON core_mdm.survivorship_executions
FOR EACH ROW
EXECUTE FUNCTION core_mdm.update_updated_at_column();

DROP TRIGGER IF EXISTS trg_survivorship_rules_updated_at
ON core_mdm.survivorship_rules;

CREATE TRIGGER trg_survivorship_rules_updated_at
BEFORE UPDATE
ON core_mdm.survivorship_rules
FOR EACH ROW
EXECUTE FUNCTION core_mdm.update_updated_at_column();

--
-- ============================================================
-- COMMENTS
-- ============================================================
--

COMMENT ON TABLE core_mdm.survivorship_executions
IS 'Stores survivorship execution runs';

COMMENT ON TABLE core_mdm.survivorship_evaluations
IS 'Detailed survivorship evaluation decisions';

COMMENT ON TABLE core_mdm.survivorship_rules
IS 'Configured survivorship business rules';

COMMENT ON TABLE core_mdm.survivorship_rules_audit
IS 'Audit trail of rules applied during executions';

COMMENT ON TABLE core_mdm.survivorship_field_decisions
IS 'Field-level survivorship decisions';

--
-- ============================================================
-- ENABLE RLS
-- ============================================================
--
ALTER TABLE core_mdm.survivorship_executions
ENABLE ROW LEVEL SECURITY;

ALTER TABLE core_mdm.survivorship_evaluations
ENABLE ROW LEVEL SECURITY;

ALTER TABLE core_mdm.survivorship_rules_audit
ENABLE ROW LEVEL SECURITY;


--
-- ============================================================
-- POLICY
-- ============================================================
--
CREATE POLICY tenant_isolation_policy
ON core_mdm.survivorship_executions
USING (
    tenant_id =
    current_setting('app.current_tenant')::uuid
);

CREATE POLICY tenant_isolation_policy
ON core_mdm.survivorship_evaluations
USING (
    tenant_id =
    current_setting('app.current_tenant')::uuid
);

CREATE POLICY tenant_isolation_policy
ON core_mdm.survivorship_rules_audit
USING (
    tenant_id =
    current_setting('app.current_tenant')::uuid
);

ALTER TABLE core_mdm.survivorship_executions
ADD CONSTRAINT chk_execution_time
CHECK (execution_time_ms >= 0);
