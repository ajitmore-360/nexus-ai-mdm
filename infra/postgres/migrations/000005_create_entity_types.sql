CREATE TABLE core_mdm.entity_types (

    entity_type_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    tenant_id UUID NOT NULL
        REFERENCES core_mdm.tenants(tenant_id),

    entity_name VARCHAR(255) NOT NULL,

    display_name VARCHAR(255),

    description TEXT,

    ai_enabled BOOLEAN NOT NULL DEFAULT TRUE,

    rag_enabled BOOLEAN NOT NULL DEFAULT TRUE,

    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(tenant_id, entity_name)
);

CREATE INDEX idx_entity_types_tenant
ON core_mdm.entity_types(tenant_id);