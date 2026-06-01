CREATE TABLE core_mdm.users (

    user_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    tenant_id UUID NOT NULL
        REFERENCES core_mdm.tenants(tenant_id),

    email VARCHAR(320) NOT NULL,

    full_name VARCHAR(255),

    role_name VARCHAR(100),

    status VARCHAR(50) NOT NULL DEFAULT 'ACTIVE',

    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(tenant_id, email)
);

CREATE INDEX idx_users_tenant
ON core_mdm.users(tenant_id);