-- ─────────────────────────────────────────────────────────────────────────────
-- 0025: Visual Workflow Engine · Certified Connectors · Third-Party Enrichment
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Workflow Engine ──────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.workflow_definitions (
    workflow_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES core_mdm.tenants(tenant_id) ON DELETE CASCADE,
    name                TEXT NOT NULL,
    description         TEXT,
    trigger_type        TEXT NOT NULL CHECK (trigger_type IN ('entity_created','entity_updated','entity_status_changed','match_found','approval_requested','schedule','manual','webhook')),
    trigger_config      JSONB NOT NULL DEFAULT '{}',
    steps               JSONB NOT NULL DEFAULT '[]',  -- ordered array of step objects
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    version             INTEGER NOT NULL DEFAULT 1,
    created_by          UUID REFERENCES core_mdm.identities(identity_id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ,
    UNIQUE(tenant_id, name)
);

CREATE TABLE IF NOT EXISTS core_mdm.workflow_runs (
    run_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_id         UUID NOT NULL REFERENCES core_mdm.workflow_definitions(workflow_id) ON DELETE CASCADE,
    tenant_id           UUID NOT NULL,
    trigger_event       TEXT NOT NULL,
    trigger_payload     JSONB NOT NULL DEFAULT '{}',
    status              TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','running','completed','failed','cancelled')),
    current_step        INTEGER NOT NULL DEFAULT 0,
    step_results        JSONB NOT NULL DEFAULT '[]',
    error_message       TEXT,
    started_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at        TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS core_mdm.workflow_step_types (
    step_type_code      TEXT PRIMARY KEY,
    display_name        TEXT NOT NULL,
    category            TEXT NOT NULL CHECK (category IN ('action','condition','notification','integration','ai')),
    config_schema       JSONB NOT NULL DEFAULT '{}',
    icon                TEXT,
    is_system           BOOLEAN NOT NULL DEFAULT TRUE
);

-- Seed built-in step types
INSERT INTO core_mdm.workflow_step_types (step_type_code, display_name, category, config_schema, icon) VALUES
    ('update_status',        'Update Entity Status',        'action',       '{"properties":{"status":{"type":"string"}}}',                                    'edit'),
    ('assign_steward',       'Assign to Steward',           'action',       '{"properties":{"steward_id":{"type":"string","format":"uuid"}}}',                 'person'),
    ('send_notification',    'Send Notification',           'notification', '{"properties":{"channel":{"type":"string"},"template":{"type":"string"}}}',       'notifications'),
    ('send_email',           'Send Email',                  'notification', '{"properties":{"to":{"type":"string"},"subject":{"type":"string"}}}',             'email'),
    ('create_task',          'Create Task',                 'action',       '{"properties":{"title":{"type":"string"},"priority":{"type":"string"}}}',         'task_alt'),
    ('call_webhook',         'Call Webhook',                'integration',  '{"properties":{"url":{"type":"string"},"method":{"type":"string"}}}',             'webhook'),
    ('condition_branch',     'Condition / Branch',          'condition',    '{"properties":{"field":{"type":"string"},"operator":{"type":"string"}}}',         'alt_route'),
    ('wait_approval',        'Wait for Approval',           'action',       '{"properties":{"approver_role":{"type":"string"}}}',                              'pending_actions'),
    ('run_quality_check',    'Run Quality Check',           'ai',           '{"properties":{"rule_ids":{"type":"array"}}}',                                    'verified'),
    ('enrich_entity',        'Enrich Entity',               'ai',           '{"properties":{"provider":{"type":"string"}}}',                                   'auto_fix_high'),
    ('trigger_match',        'Trigger Matching',            'action',       '{"properties":{"threshold":{"type":"number"}}}',                                  'merge'),
    ('set_attribute',        'Set Attribute Value',         'action',       '{"properties":{"attribute":{"type":"string"},"value":{}}}',                       'settings_backup_restore')
ON CONFLICT (step_type_code) DO NOTHING;

-- RLS for workflow tables
ALTER TABLE core_mdm.workflow_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE core_mdm.workflow_runs        ENABLE ROW LEVEL SECURITY;

CREATE POLICY workflow_definitions_tenant_isolation ON core_mdm.workflow_definitions
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);
CREATE POLICY workflow_runs_tenant_isolation ON core_mdm.workflow_runs
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

-- ── Certified Connectors ─────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.connector_catalog (
    connector_code      TEXT PRIMARY KEY,
    display_name        TEXT NOT NULL,
    vendor              TEXT NOT NULL,
    category            TEXT NOT NULL CHECK (category IN ('crm','erp','data_warehouse','marketing','ecommerce','file_storage','custom')),
    connector_type      TEXT NOT NULL CHECK (connector_type IN ('source','destination','bidirectional')),
    description         TEXT,
    logo_url            TEXT,
    config_schema       JSONB NOT NULL DEFAULT '{}',
    auth_type           TEXT NOT NULL CHECK (auth_type IN ('oauth2','api_key','basic','saml','none')),
    is_certified        BOOLEAN NOT NULL DEFAULT TRUE,
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    docs_url            TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS core_mdm.tenant_connectors (
    connector_instance_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id             UUID NOT NULL REFERENCES core_mdm.tenants(tenant_id) ON DELETE CASCADE,
    connector_code        TEXT NOT NULL REFERENCES core_mdm.connector_catalog(connector_code),
    instance_name         TEXT NOT NULL,
    config                JSONB NOT NULL DEFAULT '{}',
    credentials_encrypted BYTEA,
    is_active             BOOLEAN NOT NULL DEFAULT TRUE,
    last_sync_at          TIMESTAMPTZ,
    sync_status           TEXT CHECK (sync_status IN ('idle','running','success','error')),
    sync_error            TEXT,
    created_by            UUID REFERENCES core_mdm.identities(identity_id),
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ,
    UNIQUE(tenant_id, instance_name)
);

-- Seed certified connector catalog
INSERT INTO core_mdm.connector_catalog (connector_code, display_name, vendor, category, connector_type, description, auth_type, docs_url) VALUES
    ('salesforce',      'Salesforce',          'Salesforce',      'crm',            'bidirectional', 'Sync contacts, accounts and opportunities from Salesforce CRM.',                           'oauth2',  'https://developer.salesforce.com/docs'),
    ('sap_s4hana',      'SAP S/4HANA',         'SAP',             'erp',            'bidirectional', 'Connect to SAP S/4HANA business partner and material master data.',                       'basic',   'https://api.sap.com'),
    ('hubspot',         'HubSpot',             'HubSpot',         'crm',            'bidirectional', 'Sync CRM contacts, companies and deals from HubSpot.',                                    'oauth2',  'https://developers.hubspot.com'),
    ('snowflake',       'Snowflake',           'Snowflake',       'data_warehouse', 'bidirectional', 'Read from and write back to Snowflake data warehouse tables.',                            'basic',   'https://docs.snowflake.com'),
    ('databricks',      'Databricks',          'Databricks',      'data_warehouse', 'bidirectional', 'Connect to Databricks Delta Lake tables via REST or JDBC.',                               'api_key', 'https://docs.databricks.com'),
    ('microsoft_dynamics', 'Microsoft Dynamics 365', 'Microsoft', 'erp',           'bidirectional', 'Sync customer and product data from Dynamics 365.',                                       'oauth2',  'https://learn.microsoft.com/dynamics365'),
    ('oracle_erp',      'Oracle ERP Cloud',    'Oracle',          'erp',            'bidirectional', 'Connect to Oracle Fusion Cloud customer, supplier and item master.',                      'oauth2',  'https://docs.oracle.com/en/cloud/saas/financials'),
    ('servicenow',      'ServiceNow',          'ServiceNow',      'crm',            'bidirectional', 'Import and export configuration items and customer records from ServiceNow.',             'basic',   'https://developer.servicenow.com'),
    ('bigquery',        'Google BigQuery',     'Google',          'data_warehouse', 'destination',   'Write golden records to BigQuery datasets for analytics.',                                'oauth2',  'https://cloud.google.com/bigquery/docs'),
    ('redshift',        'Amazon Redshift',     'AWS',             'data_warehouse', 'destination',   'Load MDM data into Redshift for reporting and BI tools.',                                 'basic',   'https://docs.aws.amazon.com/redshift'),
    ('azure_sql',       'Azure SQL Database',  'Microsoft',       'data_warehouse', 'bidirectional', 'Sync entities to/from Azure SQL Database.',                                               'basic',   'https://learn.microsoft.com/azure/azure-sql'),
    ('s3',              'Amazon S3',           'AWS',             'file_storage',   'bidirectional', 'Import CSV/JSON files from S3 and export golden records back.',                           'api_key', 'https://docs.aws.amazon.com/s3'),
    ('azure_blob',      'Azure Blob Storage',  'Microsoft',       'file_storage',   'bidirectional', 'Import and export entity data via Azure Blob Storage.',                                   'api_key', 'https://learn.microsoft.com/azure/storage/blobs'),
    ('marketo',         'Marketo',             'Adobe',           'marketing',      'source',        'Import marketing leads and contacts from Marketo Engage.',                                'oauth2',  'https://developers.marketo.com'),
    ('shopify',         'Shopify',             'Shopify',         'ecommerce',      'source',        'Sync customer and product master data from Shopify.',                                     'oauth2',  'https://shopify.dev/docs/api')
ON CONFLICT (connector_code) DO NOTHING;

ALTER TABLE core_mdm.tenant_connectors ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_connectors_isolation ON core_mdm.tenant_connectors
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

-- ── Third-Party Enrichment ───────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.enrichment_providers (
    provider_code       TEXT PRIMARY KEY,
    display_name        TEXT NOT NULL,
    category            TEXT NOT NULL CHECK (category IN ('company','person','address','phone','email','social','financial','identity')),
    description         TEXT,
    logo_url            TEXT,
    config_schema       JSONB NOT NULL DEFAULT '{}',
    supported_entity_types JSONB NOT NULL DEFAULT '[]',
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    docs_url            TEXT
);

CREATE TABLE IF NOT EXISTS core_mdm.tenant_enrichment_configs (
    enrichment_config_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id             UUID NOT NULL REFERENCES core_mdm.tenants(tenant_id) ON DELETE CASCADE,
    provider_code         TEXT NOT NULL REFERENCES core_mdm.enrichment_providers(provider_code),
    is_enabled            BOOLEAN NOT NULL DEFAULT FALSE,
    api_key_encrypted     BYTEA,
    config                JSONB NOT NULL DEFAULT '{}',
    auto_enrich           BOOLEAN NOT NULL DEFAULT FALSE,
    entity_type_filter    JSONB NOT NULL DEFAULT '[]',  -- empty = all types
    field_mapping         JSONB NOT NULL DEFAULT '{}',
    daily_quota           INTEGER,
    quota_used_today      INTEGER NOT NULL DEFAULT 0,
    quota_reset_at        TIMESTAMPTZ,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ,
    UNIQUE(tenant_id, provider_code)
);

CREATE TABLE IF NOT EXISTS core_mdm.enrichment_requests (
    request_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL,
    entity_id           UUID NOT NULL REFERENCES core_mdm.entities(entity_id) ON DELETE CASCADE,
    provider_code       TEXT NOT NULL,
    status              TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','running','completed','failed','quota_exceeded')),
    request_payload     JSONB NOT NULL DEFAULT '{}',
    response_payload    JSONB,
    fields_enriched     JSONB NOT NULL DEFAULT '[]',
    error_message       TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at        TIMESTAMPTZ
);

-- Seed enrichment provider catalog
INSERT INTO core_mdm.enrichment_providers (provider_code, display_name, category, description, supported_entity_types, docs_url) VALUES
    ('clearbit',         'Clearbit',             'company',   'Enrich company and person records with firmographic and demographic data.',                       '["company","person","contact"]', 'https://clearbit.com/docs'),
    ('duns_bradstreet',  'Dun & Bradstreet',     'company',   'Authoritative D-U-N-S number lookup and firmographic enrichment for B2B entities.',              '["company","supplier","customer"]', 'https://developer.dnb.com'),
    ('opencorporates',   'OpenCorporates',       'company',   'Open company data from 140+ jurisdictions — legal name, registration number, status.',           '["company"]', 'https://api.opencorporates.com'),
    ('zoominfo',         'ZoomInfo',             'person',    'B2B contact enrichment — email, phone, title, LinkedIn from the ZoomInfo database.',             '["person","contact"]', 'https://api.zoominfo.com'),
    ('google_places',    'Google Places',        'address',   'Validate and normalise postal addresses against Google Maps Places data.',                        '["company","person","location"]', 'https://developers.google.com/maps/documentation/places'),
    ('melissa',          'Melissa Data',         'address',   'Global address verification, standardisation, and geocoding.',                                    '["company","person","location"]', 'https://www.melissa.com/developer'),
    ('twilio_lookup',    'Twilio Lookup',        'phone',     'Phone number validation, carrier lookup, and line-type identification.',                          '["company","person","contact"]', 'https://www.twilio.com/docs/lookup'),
    ('neverbounce',      'NeverBounce',          'email',     'Real-time email address verification and deliverability check.',                                  '["person","contact"]', 'https://neverbounce.com/product/api'),
    ('fullcontact',      'FullContact',          'person',    'Person identity resolution — merge signals from email, phone, social into unified profiles.',     '["person","contact"]', 'https://platform.fullcontact.com'),
    ('permid',           'Refinitiv PermID',     'financial', 'Persistent entity identifiers for publicly traded companies and financial instruments.',          '["company"]', 'https://permid.org')
ON CONFLICT (provider_code) DO NOTHING;

ALTER TABLE core_mdm.tenant_enrichment_configs  ENABLE ROW LEVEL SECURITY;
ALTER TABLE core_mdm.enrichment_requests        ENABLE ROW LEVEL SECURITY;

CREATE POLICY enrichment_configs_isolation ON core_mdm.tenant_enrichment_configs
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);
CREATE POLICY enrichment_requests_isolation ON core_mdm.enrichment_requests
    USING (tenant_id = current_setting('app.tenant_id', TRUE)::UUID);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_workflow_definitions_tenant ON core_mdm.workflow_definitions(tenant_id);
CREATE INDEX IF NOT EXISTS idx_workflow_runs_workflow      ON core_mdm.workflow_runs(workflow_id);
CREATE INDEX IF NOT EXISTS idx_workflow_runs_status        ON core_mdm.workflow_runs(status);
CREATE INDEX IF NOT EXISTS idx_tenant_connectors_tenant    ON core_mdm.tenant_connectors(tenant_id);
CREATE INDEX IF NOT EXISTS idx_enrichment_requests_entity  ON core_mdm.enrichment_requests(entity_id);
CREATE INDEX IF NOT EXISTS idx_enrichment_requests_tenant  ON core_mdm.enrichment_requests(tenant_id);
