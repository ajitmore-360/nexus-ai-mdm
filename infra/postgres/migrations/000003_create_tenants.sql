CREATE TABLE core_mdm.tenants (
    tenant_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    tenant_code VARCHAR(100) UNIQUE NOT NULL,

    tenant_name VARCHAR(255) NOT NULL,

    status VARCHAR(50) NOT NULL DEFAULT 'ACTIVE',

    subscription_plan VARCHAR(50),

    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_tenants_code
ON core_mdm.tenants(tenant_cod  e);