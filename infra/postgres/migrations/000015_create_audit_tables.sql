CREATE TABLE audit.audit_logs (

    audit_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    tenant_id UUID NOT NULL,

    entity_type VARCHAR(255),

    entity_id UUID,

    action_type VARCHAR(255),

    actor_id UUID,

    old_values JSONB,

    new_values JSONB,

    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_tenant
ON audit.audit_logs(tenant_id);

CREATE INDEX idx_audit_entity
ON audit.audit_logs(entity_id);