-- ============================================================================
-- 002024 — Submaster (Reference Data) Tables
--
-- Submasters are tenant-scoped controlled-value lists (customer_group,
-- currency, unit_of_measure, etc.) managed by Business Admin / Admin and
-- referenced by attribute_schemas entries so the entity form renders a
-- dropdown instead of a free-text field.
-- ============================================================================

-- ── Submaster type catalog ───────────────────────────────────────────────────
CREATE TABLE core_mdm.submaster_types (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   UUID        NOT NULL REFERENCES core_mdm.tenants(tenant_id),
    code        TEXT        NOT NULL,
    name        TEXT        NOT NULL,
    description TEXT,
    is_active   BOOLEAN     NOT NULL DEFAULT true,
    is_system   BOOLEAN     NOT NULL DEFAULT false,  -- system types cannot be deleted
    created_by  UUID,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, code)
);

-- ── Submaster values ─────────────────────────────────────────────────────────
CREATE TABLE core_mdm.submaster_values (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id         UUID        NOT NULL REFERENCES core_mdm.tenants(tenant_id),
    submaster_type_id UUID        NOT NULL REFERENCES core_mdm.submaster_types(id) ON DELETE CASCADE,
    code              TEXT        NOT NULL,
    label             TEXT        NOT NULL,
    description       TEXT,
    sort_order        INT         NOT NULL DEFAULT 0,
    is_active         BOOLEAN     NOT NULL DEFAULT true,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (submaster_type_id, code)
);

-- ── Link attribute_schemas → submaster ──────────────────────────────────────
ALTER TABLE core_mdm.attribute_schemas
    ADD COLUMN IF NOT EXISTS submaster_code TEXT;

-- ── Indexes ──────────────────────────────────────────────────────────────────
CREATE INDEX idx_submaster_types_tenant  ON core_mdm.submaster_types(tenant_id);
CREATE INDEX idx_submaster_values_type   ON core_mdm.submaster_values(submaster_type_id, is_active);
CREATE INDEX idx_attribute_schemas_smc   ON core_mdm.attribute_schemas(tenant_id, submaster_code)
    WHERE submaster_code IS NOT NULL;

-- ── RLS ──────────────────────────────────────────────────────────────────────
ALTER TABLE core_mdm.submaster_types  ENABLE ROW LEVEL SECURITY;
ALTER TABLE core_mdm.submaster_values ENABLE ROW LEVEL SECURITY;

CREATE POLICY submaster_types_tenant_rls ON core_mdm.submaster_types
    USING (tenant_id = current_setting('app.current_tenant')::uuid);

CREATE POLICY submaster_values_tenant_rls ON core_mdm.submaster_values
    USING (tenant_id = current_setting('app.current_tenant')::uuid);

-- ── Seed: common submasters for the demo tenant ──────────────────────────────
DO $$
DECLARE
    demo_tid UUID := '00000000-0000-0000-0000-000000000002';
    t_id     UUID;
BEGIN

-- TITLE / SALUTATION
INSERT INTO core_mdm.submaster_types (tenant_id, code, name, description, is_system)
VALUES (demo_tid, 'title', 'Title / Salutation', 'Personal and business titles', true)
RETURNING id INTO t_id;
INSERT INTO core_mdm.submaster_values (tenant_id, submaster_type_id, code, label, sort_order) VALUES
(demo_tid, t_id, 'MR',   'Mr.',   1),
(demo_tid, t_id, 'MRS',  'Mrs.',  2),
(demo_tid, t_id, 'MS',   'Ms.',   3),
(demo_tid, t_id, 'DR',   'Dr.',   4),
(demo_tid, t_id, 'PROF', 'Prof.', 5);

-- CUSTOMER GROUP
INSERT INTO core_mdm.submaster_types (tenant_id, code, name, description, is_system)
VALUES (demo_tid, 'customer_group', 'Customer Group', 'Customer classification by size / relationship type', true)
RETURNING id INTO t_id;
INSERT INTO core_mdm.submaster_values (tenant_id, submaster_type_id, code, label, sort_order) VALUES
(demo_tid, t_id, 'ENT',  'Enterprise',      1),
(demo_tid, t_id, 'SMB',  'Small Business',  2),
(demo_tid, t_id, 'GOV',  'Government',      3),
(demo_tid, t_id, 'NPO',  'Non-Profit',      4),
(demo_tid, t_id, 'RES',  'Retail/Consumer', 5);

-- VENDOR GROUP
INSERT INTO core_mdm.submaster_types (tenant_id, code, name, description, is_system)
VALUES (demo_tid, 'vendor_group', 'Vendor Group', 'Vendor classification by supply type', true)
RETURNING id INTO t_id;
INSERT INTO core_mdm.submaster_values (tenant_id, submaster_type_id, code, label, sort_order) VALUES
(demo_tid, t_id, 'RAW',  'Raw Material',     1),
(demo_tid, t_id, 'SVC',  'Services',         2),
(demo_tid, t_id, 'MFG',  'Manufacturing',    3),
(demo_tid, t_id, 'DIST', 'Distribution',     4),
(demo_tid, t_id, 'IT',   'IT & Technology',  5);

-- CURRENCY
INSERT INTO core_mdm.submaster_types (tenant_id, code, name, description, is_system)
VALUES (demo_tid, 'currency', 'Currency', 'ISO 4217 currency codes', true)
RETURNING id INTO t_id;
INSERT INTO core_mdm.submaster_values (tenant_id, submaster_type_id, code, label, sort_order) VALUES
(demo_tid, t_id, 'USD', 'US Dollar',         1),
(demo_tid, t_id, 'EUR', 'Euro',              2),
(demo_tid, t_id, 'GBP', 'British Pound',     3),
(demo_tid, t_id, 'INR', 'Indian Rupee',      4),
(demo_tid, t_id, 'AUD', 'Australian Dollar', 5),
(demo_tid, t_id, 'CAD', 'Canadian Dollar',   6),
(demo_tid, t_id, 'JPY', 'Japanese Yen',      7),
(demo_tid, t_id, 'SGD', 'Singapore Dollar',  8);

-- UNIT OF MEASURE
INSERT INTO core_mdm.submaster_types (tenant_id, code, name, description, is_system)
VALUES (demo_tid, 'uom', 'Unit of Measure', 'Standard units of measure', true)
RETURNING id INTO t_id;
INSERT INTO core_mdm.submaster_values (tenant_id, submaster_type_id, code, label, sort_order) VALUES
(demo_tid, t_id, 'EACH', 'Each',        1),
(demo_tid, t_id, 'KG',   'Kilogram',    2),
(demo_tid, t_id, 'LB',   'Pound',       3),
(demo_tid, t_id, 'MT',   'Metric Ton',  4),
(demo_tid, t_id, 'LT',   'Litre',       5),
(demo_tid, t_id, 'M',    'Metre',       6),
(demo_tid, t_id, 'BOX',  'Box',         7),
(demo_tid, t_id, 'PAL',  'Pallet',      8);

-- PAYMENT TERMS
INSERT INTO core_mdm.submaster_types (tenant_id, code, name, description, is_system)
VALUES (demo_tid, 'payment_terms', 'Payment Terms', 'Standard payment term codes', true)
RETURNING id INTO t_id;
INSERT INTO core_mdm.submaster_values (tenant_id, submaster_type_id, code, label, sort_order) VALUES
(demo_tid, t_id, 'NET15',  'Net 15 Days',       1),
(demo_tid, t_id, 'NET30',  'Net 30 Days',       2),
(demo_tid, t_id, 'NET45',  'Net 45 Days',       3),
(demo_tid, t_id, 'NET60',  'Net 60 Days',       4),
(demo_tid, t_id, 'PREPAY', 'Prepayment',        5),
(demo_tid, t_id, 'COD',    'Cash on Delivery',  6);

-- REGION
INSERT INTO core_mdm.submaster_types (tenant_id, code, name, description, is_system)
VALUES (demo_tid, 'region', 'Region', 'Geographic sales / operating region', true)
RETURNING id INTO t_id;
INSERT INTO core_mdm.submaster_values (tenant_id, submaster_type_id, code, label, sort_order) VALUES
(demo_tid, t_id, 'NA',    'North America',        1),
(demo_tid, t_id, 'EU',    'Europe',               2),
(demo_tid, t_id, 'APAC',  'Asia Pacific',         3),
(demo_tid, t_id, 'MEA',   'Middle East & Africa', 4),
(demo_tid, t_id, 'LATAM', 'Latin America',        5),
(demo_tid, t_id, 'SAR',   'South Asia',           6);

-- INDUSTRY
INSERT INTO core_mdm.submaster_types (tenant_id, code, name, description, is_system)
VALUES (demo_tid, 'industry', 'Industry', 'Business industry / sector (GICS-aligned)', true)
RETURNING id INTO t_id;
INSERT INTO core_mdm.submaster_values (tenant_id, submaster_type_id, code, label, sort_order) VALUES
(demo_tid, t_id, 'AUTO',  'Automotive',               1),
(demo_tid, t_id, 'BFSI',  'Banking & Finance',        2),
(demo_tid, t_id, 'CONS',  'Construction',             3),
(demo_tid, t_id, 'ENER',  'Energy & Utilities',       4),
(demo_tid, t_id, 'HEAL',  'Healthcare',               5),
(demo_tid, t_id, 'IT',    'Information Technology',   6),
(demo_tid, t_id, 'MANU',  'Manufacturing',            7),
(demo_tid, t_id, 'RETL',  'Retail',                   8),
(demo_tid, t_id, 'TELE',  'Telecommunications',       9),
(demo_tid, t_id, 'TRAN',  'Transportation & Logistics', 10);

-- SALES AREA
INSERT INTO core_mdm.submaster_types (tenant_id, code, name, description, is_system)
VALUES (demo_tid, 'sales_area', 'Sales Area', 'Sales territory / division code', true)
RETURNING id INTO t_id;
INSERT INTO core_mdm.submaster_values (tenant_id, submaster_type_id, code, label, sort_order) VALUES
(demo_tid, t_id, 'NA_E',  'North America East', 1),
(demo_tid, t_id, 'NA_W',  'North America West', 2),
(demo_tid, t_id, 'EU_W',  'Europe West',        3),
(demo_tid, t_id, 'EU_E',  'Europe East',        4),
(demo_tid, t_id, 'APAC',  'Asia Pacific',       5),
(demo_tid, t_id, 'GLOB',  'Global',             6);

-- CLASSIFICATION (ABC analysis tier)
INSERT INTO core_mdm.submaster_types (tenant_id, code, name, description, is_system)
VALUES (demo_tid, 'classification', 'Classification', 'Customer / entity ABC tier', true)
RETURNING id INTO t_id;
INSERT INTO core_mdm.submaster_values (tenant_id, submaster_type_id, code, label, sort_order) VALUES
(demo_tid, t_id, 'A', 'A – Platinum', 1),
(demo_tid, t_id, 'B', 'B – Gold',     2),
(demo_tid, t_id, 'C', 'C – Silver',   3),
(demo_tid, t_id, 'D', 'D – Bronze',   4);

-- LANGUAGE
INSERT INTO core_mdm.submaster_types (tenant_id, code, name, description, is_system)
VALUES (demo_tid, 'language', 'Language', 'ISO 639-1 language codes', true)
RETURNING id INTO t_id;
INSERT INTO core_mdm.submaster_values (tenant_id, submaster_type_id, code, label, sort_order) VALUES
(demo_tid, t_id, 'EN', 'English',    1),
(demo_tid, t_id, 'DE', 'German',     2),
(demo_tid, t_id, 'FR', 'French',     3),
(demo_tid, t_id, 'ES', 'Spanish',    4),
(demo_tid, t_id, 'ZH', 'Chinese',    5),
(demo_tid, t_id, 'JA', 'Japanese',   6),
(demo_tid, t_id, 'AR', 'Arabic',     7),
(demo_tid, t_id, 'PT', 'Portuguese', 8),
(demo_tid, t_id, 'HI', 'Hindi',      9);

-- ── Link customer attribute_schemas to submasters ─────────────────────────────
UPDATE core_mdm.attribute_schemas
SET submaster_code = CASE attribute_key
    WHEN 'customer_group'    THEN 'customer_group'
    WHEN 'title'             THEN 'title'
    WHEN 'currency'          THEN 'currency'
    WHEN 'payment_terms'     THEN 'payment_terms'
    WHEN 'region'            THEN 'region'
    WHEN 'industry'          THEN 'industry'
    WHEN 'sales_district'    THEN 'sales_area'
    WHEN 'language'          THEN 'language'
    WHEN 'tax_classification' THEN 'classification'
END
WHERE tenant_id = demo_tid
  AND entity_type = 'customer'
  AND attribute_key IN (
    'customer_group','title','currency','payment_terms',
    'region','industry','sales_district','language','tax_classification'
  );

-- ── Link vendor attribute_schemas to submasters ───────────────────────────────
UPDATE core_mdm.attribute_schemas
SET submaster_code = CASE attribute_key
    WHEN 'vendor_group'  THEN 'vendor_group'
    WHEN 'currency'      THEN 'currency'
    WHEN 'payment_terms' THEN 'payment_terms'
    WHEN 'region'        THEN 'region'
    WHEN 'industry'      THEN 'industry'
END
WHERE tenant_id = demo_tid
  AND entity_type = 'vendor'
  AND attribute_key IN ('vendor_group','currency','payment_terms','region','industry');

-- ── Link product / material attribute_schemas to submasters ───────────────────
UPDATE core_mdm.attribute_schemas
SET submaster_code = CASE attribute_key
    WHEN 'base_uom'     THEN 'uom'
    WHEN 'uom'          THEN 'uom'
    WHEN 'sales_uom'    THEN 'uom'
    WHEN 'purchase_uom' THEN 'uom'
    WHEN 'currency'     THEN 'currency'
END
WHERE tenant_id = demo_tid
  AND entity_type IN ('product', 'material')
  AND attribute_key IN ('base_uom','uom','sales_uom','purchase_uom','currency');

END $$;
