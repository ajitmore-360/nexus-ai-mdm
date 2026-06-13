-- =============================================================================
-- Migration: 0006_entity_schemas_and_licensing
-- Entity type attribute schemas, auto-numbering sequences, tenant onboarding,
-- and license management tables.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- ATTRIBUTE SCHEMA REGISTRY
-- Defines standard and custom attributes per entity type per tenant.
-- NULL tenant_id = global default (applies to all tenants unless overridden).
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.attribute_schemas (
    schema_id       UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID,                              -- NULL = global default
    entity_type     TEXT        NOT NULL,              -- 'Customer','Vendor',...
    attribute_key   TEXT        NOT NULL,              -- machine name: 'legal_name'
    display_name    TEXT        NOT NULL,              -- 'Legal Company Name'
    group_name      TEXT        NOT NULL DEFAULT 'General', -- 'Contact','Financial'
    data_type       TEXT        NOT NULL DEFAULT 'string',  -- string/number/date/boolean/enum/address/phone/email/url
    is_required     BOOLEAN     NOT NULL DEFAULT FALSE,
    is_searchable   BOOLEAN     NOT NULL DEFAULT TRUE,
    is_filterable   BOOLEAN     NOT NULL DEFAULT TRUE,
    is_pii          BOOLEAN     NOT NULL DEFAULT FALSE,  -- GDPR flag
    is_system       BOOLEAN     NOT NULL DEFAULT FALSE,  -- cannot be deleted
    enum_values     JSONB,                               -- ["Active","Inactive"]
    default_value   TEXT,
    validation      JSONB,                               -- {min,max,regex,maxLength}
    display_order   INT         NOT NULL DEFAULT 100,
    placeholder     TEXT,
    help_text       TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, entity_type, attribute_key)
);

CREATE INDEX IF NOT EXISTS idx_attr_schemas_entity
    ON core_mdm.attribute_schemas (tenant_id, entity_type, display_order);

-- ─────────────────────────────────────────────────────────────────────────────
-- AUTO-NUMBERING SEQUENCES
-- Provides CUST-000001, VEND-000001, PROD-000001 style business numbers.
-- Each tenant can override the prefix, separator, and digit width.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.entity_sequences (
    tenant_id       UUID        NOT NULL,
    entity_type     TEXT        NOT NULL,
    prefix          TEXT        NOT NULL DEFAULT '',     -- 'CUST'
    separator       TEXT        NOT NULL DEFAULT '-',    -- '-' or '_' or ''
    min_digits      INT         NOT NULL DEFAULT 6,      -- 6 → 000001
    current_value   BIGINT      NOT NULL DEFAULT 0,
    step            INT         NOT NULL DEFAULT 1,
    reset_yearly    BOOLEAN     NOT NULL DEFAULT FALSE,
    last_reset_year INT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (tenant_id, entity_type)
);

-- Atomic sequence increment — safe under concurrent entity creation
CREATE OR REPLACE FUNCTION core_mdm.next_entity_number(
    p_tenant_id   UUID,
    p_entity_type TEXT
) RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_prefix    TEXT;
    v_separator TEXT;
    v_digits    INT;
    v_next      BIGINT;
    v_year      INT := EXTRACT(YEAR FROM NOW())::INT;
BEGIN
    -- Lock the row and increment atomically
    UPDATE core_mdm.entity_sequences
    SET current_value = CASE
            WHEN reset_yearly AND last_reset_year < v_year THEN 1
            ELSE current_value + step
          END,
        last_reset_year = v_year,
        updated_at = NOW()
    WHERE tenant_id   = p_tenant_id
      AND entity_type = p_entity_type
    RETURNING prefix, separator, min_digits, current_value
    INTO v_prefix, v_separator, v_digits, v_next;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No sequence configured for tenant % entity_type %',
                        p_tenant_id, p_entity_type;
    END IF;

    RETURN v_prefix || v_separator || LPAD(v_next::TEXT, v_digits, '0');
END;
$$;

COMMENT ON FUNCTION core_mdm.next_entity_number IS
    'Atomically increment and return the next business number for an entity type. '
    'Example: SELECT core_mdm.next_entity_number(tenant_id, ''Customer'') → CUST-000042';

-- ─────────────────────────────────────────────────────────────────────────────
-- TENANT ONBOARDING PROFILE
-- Extended tenant configuration beyond the core tenants table.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.tenant_profiles (
    tenant_id           UUID PRIMARY KEY REFERENCES core_mdm.tenants(tenant_id),
    legal_name          TEXT,
    trade_name          TEXT,
    tax_id              TEXT,
    vat_id              TEXT,
    duns_number         TEXT,
    industry            TEXT,
    company_size        TEXT,           -- '1-50','51-200','201-1000','1000+'
    country             TEXT,
    state_province      TEXT,
    city                TEXT,
    address             TEXT,
    phone               TEXT,
    website             TEXT,
    admin_email         TEXT,
    timezone            TEXT DEFAULT 'UTC',
    locale              TEXT DEFAULT 'en-US',
    date_format         TEXT DEFAULT 'YYYY-MM-DD',
    currency            TEXT DEFAULT 'USD',
    -- Branding
    logo_url            TEXT,
    primary_color       TEXT DEFAULT '#00C896',
    -- Onboarding state
    onboarding_status   TEXT NOT NULL DEFAULT 'pending',  -- pending/in_progress/completed
    onboarding_step     INT NOT NULL DEFAULT 0,
    onboarded_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- LICENSE MANAGEMENT
-- JWT-signed license files issued by the Nexus MDM vendor.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS platform.licenses (
    license_id      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    organization    TEXT        NOT NULL,   -- licensee company name
    tier            TEXT        NOT NULL,   -- Community/Professional/Enterprise/OEM
    -- Validity
    issued_at       TIMESTAMPTZ NOT NULL,
    expires_at      TIMESTAMPTZ,            -- NULL = perpetual
    is_trial        BOOLEAN     NOT NULL DEFAULT FALSE,
    -- Limits (NULL = unlimited)
    max_tenants     INT,
    max_entities_per_tenant BIGINT,
    max_users_per_tenant    INT,
    max_source_systems      INT,
    max_api_calls_per_day   BIGINT,
    -- Features (JSON array of feature keys)
    features        JSONB       NOT NULL DEFAULT '[]',
    -- Raw signed JWT token for offline validation
    license_token   TEXT        NOT NULL UNIQUE,
    -- Status
    status          TEXT        NOT NULL DEFAULT 'active',  -- active/expired/revoked/suspended
    imported_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    imported_by     UUID,       -- user who imported the license
    revoked_at      TIMESTAMPTZ,
    revoke_reason   TEXT,
    -- Fingerprint for tamper detection
    checksum        TEXT        NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_licenses_status
    ON platform.licenses (status, expires_at)
    WHERE status = 'active';

-- Active license view (application uses this)
CREATE OR REPLACE VIEW platform.active_license AS
SELECT *
FROM platform.licenses
WHERE status = 'active'
  AND (expires_at IS NULL OR expires_at > NOW())
LIMIT 1;

-- ─────────────────────────────────────────────────────────────────────────────
-- LICENSE-FEATURE ENFORCEMENT
-- Maps license features to platform capabilities.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS platform.license_feature_registry (
    feature_key     TEXT PRIMARY KEY,
    display_name    TEXT NOT NULL,
    description     TEXT,
    tier_minimum    TEXT NOT NULL DEFAULT 'Professional',  -- minimum tier required
    is_addon        BOOLEAN NOT NULL DEFAULT FALSE
);

INSERT INTO platform.license_feature_registry
    (feature_key, display_name, description, tier_minimum)
VALUES
    ('entity_management',   'Entity Management',       'Create and manage master data entities',         'Community'),
    ('basic_matching',      'Basic Matching',          'Rule-based entity deduplication',                'Community'),
    ('merge_workflow',      'Merge Workflow',          'Human review and approve/reject merges',         'Community'),
    ('golden_records',      'Golden Records',          'Survivorship and golden record creation',        'Community'),
    ('api_access',          'REST API Access',         'Full REST API for external integrations',        'Professional'),
    ('ai_matching',         'AI-Powered Matching',     'LLM-augmented semantic match resolution',        'Professional'),
    ('rag_copilot',         'AI Copilot (RAG)',        'Natural language queries over entity data',       'Professional'),
    ('data_enrichment',     'Data Enrichment',         'D&B / Experian external enrichment',             'Professional'),
    ('advanced_search',     'Hybrid Search',           'Full-text + vector semantic search',             'Professional'),
    ('bulk_ingest',         'Bulk Ingest',             'CSV/JSON batch ingestion',                       'Professional'),
    ('kafka_streaming',     'Kafka Streaming',         'Real-time entity event streaming',               'Enterprise'),
    ('multi_tenant',        'Multi-Tenancy',           'Multiple isolated tenant organisations',          'Enterprise'),
    ('adaptive_ai',         'Adaptive AI Weights',     'Self-tuning match weights from steward feedback','Enterprise'),
    ('policy_engine',       'Governance Policies',     'OPA-based field masking and access control',     'Enterprise'),
    ('gdpr_compliance',     'GDPR Compliance Engine',  'Right-to-erasure and data subject access',       'Enterprise'),
    ('webhooks',            'Distribution Webhooks',   'Push entity updates to downstream systems',      'Enterprise'),
    ('custom_attributes',   'Custom Attributes',       'Extend entity schemas with tenant-specific fields','Professional'),
    ('white_label',         'White Label',             'Custom branding and domain',                     'OEM')
ON CONFLICT (feature_key) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- SEED: Global default attribute schemas for all standard entity types
-- ─────────────────────────────────────────────────────────────────────────────

-- Helper: insert with no conflict on global defaults (tenant_id IS NULL)
DO $$
BEGIN

-- ── CUSTOMER ─────────────────────────────────────────────────────────────────
INSERT INTO core_mdm.attribute_schemas
    (tenant_id, entity_type, attribute_key, display_name, group_name, data_type,
     is_required, is_searchable, is_pii, is_system, enum_values, validation, display_order, help_text)
VALUES
-- Identity
(NULL,'Customer','customer_number',  'Customer Number',  'Identity',  'string', FALSE,TRUE, FALSE,TRUE,  NULL, '{"maxLength":20}',   1,  'Auto-generated: CUST-000001'),
(NULL,'Customer','legal_name',       'Legal Name',       'Identity',  'string', TRUE, TRUE, FALSE,FALSE, NULL, '{"maxLength":200}',  2,  'Full legal company or person name'),
(NULL,'Customer','trade_name',       'Trade Name / DBA', 'Identity',  'string', FALSE,TRUE, FALSE,FALSE, NULL, '{"maxLength":200}',  3,  'Doing Business As name'),
(NULL,'Customer','customer_type',    'Customer Type',    'Identity',  'enum',   TRUE, TRUE, FALSE,FALSE,
    '["Individual","Corporation","Partnership","Government","Non-Profit","Other"]', NULL, 4, NULL),
(NULL,'Customer','status',           'Status',           'Identity',  'enum',   TRUE, TRUE, FALSE,FALSE,
    '["Active","Inactive","Prospect","On Hold","Suspended","Closed"]', NULL, 5, NULL),
-- Contact
(NULL,'Customer','email',            'Primary Email',    'Contact',   'email',  TRUE, TRUE, TRUE, FALSE, NULL, '{"maxLength":255}',  10, NULL),
(NULL,'Customer','phone',            'Primary Phone',    'Contact',   'phone',  FALSE,TRUE, TRUE, FALSE, NULL, NULL,                 11, NULL),
(NULL,'Customer','mobile',           'Mobile Phone',     'Contact',   'phone',  FALSE,TRUE, TRUE, FALSE, NULL, NULL,                 12, NULL),
(NULL,'Customer','website',          'Website',          'Contact',   'url',    FALSE,FALSE,FALSE,FALSE, NULL, NULL,                 13, NULL),
(NULL,'Customer','fax',              'Fax',              'Contact',   'phone',  FALSE,FALSE,FALSE,FALSE, NULL, NULL,                 14, NULL),
-- Address
(NULL,'Customer','billing_address',  'Billing Address',  'Address',   'address',FALSE,FALSE,FALSE,FALSE, NULL, NULL,                 20, NULL),
(NULL,'Customer','shipping_address', 'Shipping Address', 'Address',   'address',FALSE,FALSE,FALSE,FALSE, NULL, NULL,                 21, NULL),
(NULL,'Customer','country',          'Country',          'Address',   'string', FALSE,TRUE, FALSE,FALSE, NULL, '{"maxLength":3}',   22, '2-letter ISO country code'),
-- Financial
(NULL,'Customer','tax_id',           'Tax ID / EIN',     'Financial', 'string', FALSE,TRUE, TRUE, FALSE, NULL, '{"maxLength":50}',  30, NULL),
(NULL,'Customer','vat_number',       'VAT Number',       'Financial', 'string', FALSE,TRUE, TRUE, FALSE, NULL, '{"maxLength":50}',  31, NULL),
(NULL,'Customer','credit_limit',     'Credit Limit',     'Financial', 'number', FALSE,FALSE,FALSE,FALSE, NULL, '{"min":0}',         32, NULL),
(NULL,'Customer','payment_terms',    'Payment Terms',    'Financial', 'enum',   FALSE,FALSE,FALSE,FALSE,
    '["Net7","Net15","Net30","Net45","Net60","Net90","Due on Receipt","Prepaid"]', NULL, 33, NULL),
(NULL,'Customer','currency',         'Currency',         'Financial', 'string', FALSE,FALSE,FALSE,FALSE, NULL, '{"maxLength":3}',   34, '3-letter ISO currency code'),
-- Business
(NULL,'Customer','industry',         'Industry',         'Business',  'string', FALSE,TRUE, FALSE,FALSE, NULL, NULL,                 40, NULL),
(NULL,'Customer','annual_revenue',   'Annual Revenue',   'Business',  'number', FALSE,FALSE,FALSE,FALSE, NULL, '{"min":0}',         41, NULL),
(NULL,'Customer','employee_count',   'Employee Count',   'Business',  'number', FALSE,FALSE,FALSE,FALSE, NULL, '{"min":0}',         42, NULL),
(NULL,'Customer','account_manager',  'Account Manager',  'Business',  'string', FALSE,FALSE,FALSE,FALSE, NULL, NULL,                 43, NULL),
(NULL,'Customer','parent_customer',  'Parent Customer',  'Business',  'string', FALSE,TRUE, FALSE,FALSE, NULL, NULL,                 44, 'Parent company entity ID for hierarchy')
ON CONFLICT (tenant_id, entity_type, attribute_key) DO NOTHING;

-- ── VENDOR ───────────────────────────────────────────────────────────────────
INSERT INTO core_mdm.attribute_schemas
    (tenant_id, entity_type, attribute_key, display_name, group_name, data_type,
     is_required, is_searchable, is_pii, is_system, enum_values, validation, display_order, help_text)
VALUES
(NULL,'Vendor','vendor_number',   'Vendor Number',    'Identity',  'string', FALSE,TRUE, FALSE,TRUE, NULL,'{"maxLength":20}',  1, 'Auto-generated: VEND-000001'),
(NULL,'Vendor','vendor_name',     'Vendor Name',      'Identity',  'string', TRUE, TRUE, FALSE,FALSE,NULL,'{"maxLength":200}', 2, NULL),
(NULL,'Vendor','vendor_type',     'Vendor Type',      'Identity',  'enum',   TRUE, TRUE, FALSE,FALSE,
    '["Supplier","Manufacturer","Distributor","Service Provider","Contractor","Consultant","Other"]', NULL, 3, NULL),
(NULL,'Vendor','category',        'Category',         'Identity',  'string', FALSE,TRUE, FALSE,FALSE,NULL,NULL,                4, NULL),
(NULL,'Vendor','status',          'Status',           'Identity',  'enum',   TRUE, TRUE, FALSE,FALSE,
    '["Active","Inactive","Pending Approval","Blacklisted","On Hold"]', NULL, 5, NULL),
(NULL,'Vendor','email',           'Primary Email',    'Contact',   'email',  TRUE, TRUE, TRUE, FALSE,NULL,'{"maxLength":255}',10, NULL),
(NULL,'Vendor','phone',           'Primary Phone',    'Contact',   'phone',  FALSE,TRUE, TRUE, FALSE,NULL,NULL,               11, NULL),
(NULL,'Vendor','website',         'Website',          'Contact',   'url',    FALSE,FALSE,FALSE,FALSE,NULL,NULL,               12, NULL),
(NULL,'Vendor','address',         'Business Address', 'Address',   'address',FALSE,FALSE,FALSE,FALSE,NULL,NULL,               20, NULL),
(NULL,'Vendor','country',         'Country',          'Address',   'string', FALSE,TRUE, FALSE,FALSE,NULL,'{"maxLength":3}',  21, NULL),
(NULL,'Vendor','tax_id',          'Tax ID / EIN',     'Financial', 'string', FALSE,TRUE, TRUE, FALSE,NULL,'{"maxLength":50}', 30, NULL),
(NULL,'Vendor','duns_number',     'DUNS Number',      'Financial', 'string', FALSE,TRUE, FALSE,FALSE,NULL,'{"maxLength":9}',  31, 'Dun & Bradstreet 9-digit identifier'),
(NULL,'Vendor','payment_terms',   'Payment Terms',    'Financial', 'enum',   FALSE,FALSE,FALSE,FALSE,
    '["Net30","Net45","Net60","Net90","Prepaid","COD"]', NULL, 32, NULL),
(NULL,'Vendor','currency',        'Currency',         'Financial', 'string', FALSE,FALSE,FALSE,FALSE,NULL,'{"maxLength":3}',  33, NULL),
(NULL,'Vendor','bank_name',       'Bank Name',        'Financial', 'string', FALSE,FALSE,FALSE,FALSE,NULL,NULL,               34, NULL),
(NULL,'Vendor','bank_account',    'Bank Account',     'Financial', 'string', FALSE,FALSE,TRUE, FALSE,NULL,NULL,               35, 'Stored masked for PII compliance'),
(NULL,'Vendor','certifications',  'Certifications',   'Compliance','string', FALSE,FALSE,FALSE,FALSE,NULL,NULL,               40, 'e.g. ISO 9001, SOX, GDPR'),
(NULL,'Vendor','preferred',       'Preferred Vendor', 'Business',  'boolean',FALSE,TRUE, FALSE,FALSE,NULL,NULL,               41, NULL),
(NULL,'Vendor','lead_time_days',  'Lead Time (Days)', 'Business',  'number', FALSE,FALSE,FALSE,FALSE,NULL,'{"min":0}',        42, NULL)
ON CONFLICT (tenant_id, entity_type, attribute_key) DO NOTHING;

-- ── PRODUCT ──────────────────────────────────────────────────────────────────
INSERT INTO core_mdm.attribute_schemas
    (tenant_id, entity_type, attribute_key, display_name, group_name, data_type,
     is_required, is_searchable, is_pii, is_system, enum_values, validation, display_order, help_text)
VALUES
(NULL,'Product','product_number', 'Product Number',   'Identity',  'string', FALSE,TRUE, FALSE,TRUE, NULL,'{"maxLength":20}',  1, 'Auto-generated: PROD-000001'),
(NULL,'Product','product_name',   'Product Name',     'Identity',  'string', TRUE, TRUE, FALSE,FALSE,NULL,'{"maxLength":300}', 2, NULL),
(NULL,'Product','product_type',   'Product Type',     'Identity',  'enum',   TRUE, TRUE, FALSE,FALSE,
    '["Finished Goods","Raw Material","Semi-Finished","Service","Digital","Bundle","Other"]', NULL, 3, NULL),
(NULL,'Product','sku',            'SKU',              'Identity',  'string', FALSE,TRUE, FALSE,FALSE,NULL,'{"maxLength":100}', 4, 'Stock Keeping Unit'),
(NULL,'Product','barcode',        'Barcode / EAN',    'Identity',  'string', FALSE,TRUE, FALSE,FALSE,NULL,NULL,                5, 'EAN-13, UPC-A, or custom'),
(NULL,'Product','status',         'Status',           'Identity',  'enum',   TRUE, TRUE, FALSE,FALSE,
    '["Active","Inactive","Discontinued","Draft","Pending Approval"]', NULL, 6, NULL),
(NULL,'Product','category',       'Category',         'Classification','string',FALSE,TRUE,FALSE,FALSE,NULL,NULL,              10, NULL),
(NULL,'Product','sub_category',   'Sub-Category',     'Classification','string',FALSE,TRUE,FALSE,FALSE,NULL,NULL,              11, NULL),
(NULL,'Product','description',    'Description',      'Details',   'string', FALSE,TRUE, FALSE,FALSE,NULL,'{"maxLength":2000}',12, NULL),
(NULL,'Product','uom',            'Unit of Measure',  'Details',   'enum',   TRUE, FALSE,FALSE,FALSE,
    '["EA","KG","LB","G","T","M","CM","MM","L","ML","FT","IN","SQ_FT","SQ_M","HR","DAY","MON"]', NULL, 13, NULL),
(NULL,'Product','unit_price',     'Unit Price',       'Pricing',   'number', FALSE,FALSE,FALSE,FALSE,NULL,'{"min":0}',         20, NULL),
(NULL,'Product','list_price',     'List Price',       'Pricing',   'number', FALSE,FALSE,FALSE,FALSE,NULL,'{"min":0}',         21, NULL),
(NULL,'Product','cost_price',     'Cost Price',       'Pricing',   'number', FALSE,FALSE,FALSE,FALSE,NULL,'{"min":0}',         22, NULL),
(NULL,'Product','currency',       'Currency',         'Pricing',   'string', FALSE,FALSE,FALSE,FALSE,NULL,'{"maxLength":3}',   23, NULL),
(NULL,'Product','manufacturer',   'Manufacturer',     'Supply',    'string', FALSE,TRUE, FALSE,FALSE,NULL,NULL,                30, NULL),
(NULL,'Product','manufacturer_pn','Manufacturer Part No.','Supply','string', FALSE,TRUE, FALSE,FALSE,NULL,NULL,                31, NULL),
(NULL,'Product','weight_kg',      'Weight (kg)',      'Physical',  'number', FALSE,FALSE,FALSE,FALSE,NULL,'{"min":0}',         40, NULL),
(NULL,'Product','hazardous',      'Hazardous Material','Compliance','boolean',FALSE,TRUE,FALSE,FALSE,NULL,NULL,                50, NULL)
ON CONFLICT (tenant_id, entity_type, attribute_key) DO NOTHING;

-- ── MATERIAL (extends Product defaults) ─────────────────────────────────────
INSERT INTO core_mdm.attribute_schemas
    (tenant_id, entity_type, attribute_key, display_name, group_name, data_type,
     is_required, is_searchable, is_pii, is_system, enum_values, validation, display_order, help_text)
VALUES
(NULL,'Material','material_number', 'Material Number',  'Identity',  'string', FALSE,TRUE, FALSE,TRUE, NULL,'{"maxLength":20}',  1, 'Auto-generated: MATL-000001'),
(NULL,'Material','material_name',   'Material Name',    'Identity',  'string', TRUE, TRUE, FALSE,FALSE,NULL,'{"maxLength":300}', 2, NULL),
(NULL,'Material','material_type',   'Material Type',    'Identity',  'enum',   TRUE, TRUE, FALSE,FALSE,
    '["Raw Material","Packaging","Component","Consumable","Chemical","Other"]', NULL, 3, NULL),
(NULL,'Material','status',          'Status',           'Identity',  'enum',   TRUE, TRUE, FALSE,FALSE,
    '["Active","Inactive","Discontinued"]', NULL, 4, NULL),
(NULL,'Material','uom',             'Unit of Measure',  'Details',   'enum',   TRUE, FALSE,FALSE,FALSE,
    '["EA","KG","LB","G","T","M","CM","MM","L","ML","FT","IN"]', NULL, 10, NULL),
(NULL,'Material','min_stock',       'Minimum Stock',    'Inventory', 'number', FALSE,FALSE,FALSE,FALSE,NULL,'{"min":0}',        20, NULL),
(NULL,'Material','max_stock',       'Maximum Stock',    'Inventory', 'number', FALSE,FALSE,FALSE,FALSE,NULL,'{"min":0}',        21, NULL),
(NULL,'Material','hazardous',       'Hazardous',        'Compliance','boolean',FALSE,TRUE, FALSE,FALSE,NULL,NULL,               30, NULL)
ON CONFLICT (tenant_id, entity_type, attribute_key) DO NOTHING;

-- ── EMPLOYEE ─────────────────────────────────────────────────────────────────
INSERT INTO core_mdm.attribute_schemas
    (tenant_id, entity_type, attribute_key, display_name, group_name, data_type,
     is_required, is_searchable, is_pii, is_system, enum_values, validation, display_order, help_text)
VALUES
(NULL,'Employee','employee_id',    'Employee ID',       'Identity', 'string', FALSE,TRUE, FALSE,TRUE, NULL,'{"maxLength":20}',  1,  'Auto-generated: EMP-000001'),
(NULL,'Employee','first_name',     'First Name',        'Identity', 'string', TRUE, TRUE, TRUE, FALSE,NULL,'{"maxLength":100}', 2,  NULL),
(NULL,'Employee','last_name',      'Last Name',         'Identity', 'string', TRUE, TRUE, TRUE, FALSE,NULL,'{"maxLength":100}', 3,  NULL),
(NULL,'Employee','display_name',   'Display Name',      'Identity', 'string', FALSE,TRUE, TRUE, FALSE,NULL,'{"maxLength":200}', 4,  NULL),
(NULL,'Employee','status',         'Employment Status', 'Identity', 'enum',   TRUE, TRUE, FALSE,FALSE,
    '["Active","Inactive","On Leave","Terminated","Contractor"]', NULL, 5, NULL),
(NULL,'Employee','work_email',     'Work Email',        'Contact',  'email',  TRUE, TRUE, TRUE, FALSE,NULL,'{"maxLength":255}',10, NULL),
(NULL,'Employee','work_phone',     'Work Phone',        'Contact',  'phone',  FALSE,TRUE, TRUE, FALSE,NULL,NULL,               11, NULL),
(NULL,'Employee','department',     'Department',        'HR',       'string', FALSE,TRUE, FALSE,FALSE,NULL,NULL,               20, NULL),
(NULL,'Employee','job_title',      'Job Title',         'HR',       'string', FALSE,TRUE, FALSE,FALSE,NULL,'{"maxLength":200}',21, NULL),
(NULL,'Employee','manager_id',     'Manager Employee ID','HR',      'string', FALSE,TRUE, FALSE,FALSE,NULL,NULL,               22, NULL),
(NULL,'Employee','hire_date',      'Hire Date',         'HR',       'date',   FALSE,FALSE,FALSE,FALSE,NULL,NULL,               23, NULL),
(NULL,'Employee','employment_type','Employment Type',   'HR',       'enum',   FALSE,TRUE, FALSE,FALSE,
    '["Full-Time","Part-Time","Contractor","Intern","Consultant"]', NULL, 24, NULL)
ON CONFLICT (tenant_id, entity_type, attribute_key) DO NOTHING;

-- ── LOCATION ─────────────────────────────────────────────────────────────────
INSERT INTO core_mdm.attribute_schemas
    (tenant_id, entity_type, attribute_key, display_name, group_name, data_type,
     is_required, is_searchable, is_pii, is_system, enum_values, validation, display_order, help_text)
VALUES
(NULL,'Location','location_code',  'Location Code',    'Identity', 'string', FALSE,TRUE, FALSE,TRUE, NULL,'{"maxLength":20}',  1, 'Auto-generated: LOC-000001'),
(NULL,'Location','location_name',  'Location Name',    'Identity', 'string', TRUE, TRUE, FALSE,FALSE,NULL,'{"maxLength":200}', 2, NULL),
(NULL,'Location','location_type',  'Location Type',    'Identity', 'enum',   TRUE, TRUE, FALSE,FALSE,
    '["Headquarters","Office","Warehouse","Store","Manufacturing Plant","Data Center","Distribution Center","Other"]', NULL, 3, NULL),
(NULL,'Location','status',         'Status',           'Identity', 'enum',   TRUE, TRUE, FALSE,FALSE,
    '["Active","Inactive","Closed","Under Construction"]', NULL, 4, NULL),
(NULL,'Location','street',         'Street Address',   'Address',  'string', FALSE,TRUE, FALSE,FALSE,NULL,'{"maxLength":300}',10, NULL),
(NULL,'Location','city',           'City',             'Address',  'string', FALSE,TRUE, FALSE,FALSE,NULL,'{"maxLength":100}',11, NULL),
(NULL,'Location','state',          'State / Province', 'Address',  'string', FALSE,TRUE, FALSE,FALSE,NULL,'{"maxLength":100}',12, NULL),
(NULL,'Location','zip_code',       'Zip / Postal Code','Address',  'string', FALSE,TRUE, FALSE,FALSE,NULL,'{"maxLength":20}', 13, NULL),
(NULL,'Location','country',        'Country',          'Address',  'string', FALSE,TRUE, FALSE,FALSE,NULL,'{"maxLength":3}',  14, '2-letter ISO country code'),
(NULL,'Location','phone',          'Phone',            'Contact',  'phone',  FALSE,TRUE, FALSE,FALSE,NULL,NULL,              20, NULL),
(NULL,'Location','timezone',       'Timezone',         'Operations','string',FALSE,FALSE,FALSE,FALSE,NULL,NULL,              30, 'e.g. America/New_York'),
(NULL,'Location','capacity',       'Capacity',         'Operations','number',FALSE,FALSE,FALSE,FALSE,NULL,'{"min":0}',       31, NULL)
ON CONFLICT (tenant_id, entity_type, attribute_key) DO NOTHING;

END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- SEED: Default number sequences for the default tenant
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO core_mdm.entity_sequences (tenant_id, entity_type, prefix, separator, min_digits)
SELECT '00000000-0000-0000-0000-000000000001'::UUID, entity_type, prefix, '-', 6
FROM (VALUES
    ('Customer',     'CUST'),
    ('Vendor',       'VEND'),
    ('Product',      'PROD'),
    ('Material',     'MATL'),
    ('Account',      'ACCT'),
    ('Employee',     'EMP'),
    ('Location',     'LOC'),
    ('Organization', 'ORG'),
    ('Asset',        'ASST'),
    ('Contact',      'CONT')
) AS t(entity_type, prefix)
ON CONFLICT (tenant_id, entity_type) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- COMMENTS
-- ─────────────────────────────────────────────────────────────────────────────
COMMENT ON TABLE core_mdm.attribute_schemas   IS 'Standard and custom attribute definitions per entity type';
COMMENT ON TABLE core_mdm.entity_sequences    IS 'Auto-increment sequences for business numbers (CUST-000001 etc.)';
COMMENT ON TABLE core_mdm.tenant_profiles     IS 'Extended tenant configuration for onboarding';
COMMENT ON TABLE platform.licenses            IS 'JWT-signed license tokens imported from Nexus MDM vendor';
COMMENT ON TABLE platform.license_feature_registry IS 'Master list of licensable feature keys';
