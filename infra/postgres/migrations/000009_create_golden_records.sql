CREATE TABLE core_mdm.golden_records (

    golden_record_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    tenant_id UUID NOT NULL
        REFERENCES core_mdm.tenants(tenant_id),

    entity_type_id UUID NOT NULL
        REFERENCES core_mdm.entity_types(entity_type_id),

    status VARCHAR(50) NOT NULL,

    survivorship_score NUMERIC(5,4),

    ai_validated BOOLEAN NOT NULL DEFAULT FALSE,

    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_golden_records_tenant
ON core_mdm.golden_records(tenant_id);