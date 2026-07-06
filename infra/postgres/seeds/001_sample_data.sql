-- =============================================================================
-- Nexus AI MDM — Sample Data Seed  (v2)
--
-- ALL demo data lives under the "Demo Org" tenant:
--   tenant_id = 00000000-0000-0000-0000-000000000002
--
-- The System Tenant (00000000-0000-0000-0000-000000000001) is reserved for
-- platform infrastructure only — no business data belongs there.
--
-- User accounts use core_mdm.identities + core_mdm.tenant_memberships
-- (migration 002018).  core_mdm.users was dropped by that migration.
--
-- Run:
--   docker exec -i nexus-postgres psql -U postgres -d nexus_mdm < seed.sql
-- =============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- CONSTANTS
-- ─────────────────────────────────────────────────────────────────────────────

\set demo_tenant  '00000000-0000-0000-0000-000000000002'
\set sys_tenant   '00000000-0000-0000-0000-000000000001'

-- ─────────────────────────────────────────────────────────────────────────────
-- CLEANUP — Remove any previous seed data that landed under the system tenant.
-- Entities, source systems, golden records, and match candidates that carry
-- the system tenant UUID should not exist; they were erroneously seeded by v1.
-- Cascade deletes handle child rows (attributes, embeddings, etc.).
-- ─────────────────────────────────────────────────────────────────────────────

DELETE FROM core_mdm.match_candidates  WHERE tenant_id = :'sys_tenant';
DELETE FROM core_mdm.golden_records    WHERE tenant_id = :'sys_tenant';
DELETE FROM core_mdm.entity_attributes WHERE tenant_id = :'sys_tenant';
DELETE FROM core_mdm.entities          WHERE tenant_id = :'sys_tenant';
DELETE FROM core_mdm.source_systems    WHERE tenant_id = :'sys_tenant';
DELETE FROM ai.rag_documents           WHERE tenant_id = :'sys_tenant';
DELETE FROM core_mdm.entity_sequences  WHERE tenant_id = :'sys_tenant';
DELETE FROM core_mdm.entity_type_configs WHERE tenant_id = :'sys_tenant';
DELETE FROM core_mdm.tenant_memberships WHERE tenant_id = :'sys_tenant';
DELETE FROM core_mdm.identities
    WHERE email IN (
        'admin@nexus.ai','businessadmin@nexus.ai','steward@nexus.ai',
        'analyst@nexus.ai','viewer@nexus.ai'
    );

-- ─────────────────────────────────────────────────────────────────────────────
-- DEMO TENANT
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO core_mdm.tenants
    (tenant_id, tenant_code, display_name, plan, status, created_at, updated_at)
VALUES
    (:'demo_tenant', 'DEMO', 'Demo Organization', 'enterprise', 'active', NOW(), NOW())
ON CONFLICT (tenant_id) DO UPDATE
    SET display_name = EXCLUDED.display_name,
        updated_at   = NOW();

-- Enterprise license — unlocks all features for the demo tenant
INSERT INTO core_mdm.tenant_licenses
    (tenant_id, tier, status, max_domains, max_records, max_stewards, features, notes)
VALUES
    (:'demo_tenant', 'enterprise', 'active', -1, -1, -1,
     '{"analytics":true,"ai_copilot":true,"governance":true,"white_label":true,"data_quality":true,"distribution":true,"relationships":true,"domain_policies":true,"priority_support":true,"matching_semantic":true}',
     'Demo tenant — enterprise tier, all features enabled')
ON CONFLICT (tenant_id) DO UPDATE
    SET tier         = EXCLUDED.tier,
        max_domains  = EXCLUDED.max_domains,
        max_records  = EXCLUDED.max_records,
        max_stewards = EXCLUDED.max_stewards,
        features     = EXCLUDED.features,
        updated_at   = NOW();

-- ─────────────────────────────────────────────────────────────────────────────
-- IDENTITIES  (global — one row per person, no tenant_id)
-- Passwords hashed with bcrypt cost 12 via pgcrypto.
--
--   admin@nexus.ai        /  Admin@123456   (admin)
--   businessadmin@nexus.ai/  BizAdmin@123   (business_admin)
--   steward@nexus.ai      /  Steward@123    (steward)
--   analyst@nexus.ai      /  Analyst@123    (analyst)
--   viewer@nexus.ai       /  Viewer@123     (viewer)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO core_mdm.identities
    (identity_id, email, password_hash, display_name, is_verified, created_at)
VALUES
    ('10000000-0000-0000-0000-000000000001', 'admin@nexus.ai',
     crypt('Admin@123456', gen_salt('bf', 12)),
     'Platform Admin', TRUE, NOW()),

    ('10000000-0000-0000-0000-000000000002', 'businessadmin@nexus.ai',
     crypt('BizAdmin@123', gen_salt('bf', 12)),
     'Victoria Chang', TRUE, NOW()),

    ('10000000-0000-0000-0000-000000000003', 'steward@nexus.ai',
     crypt('Steward@123', gen_salt('bf', 12)),
     'Sarah Chen', TRUE, NOW()),

    ('10000000-0000-0000-0000-000000000004', 'analyst@nexus.ai',
     crypt('Analyst@123', gen_salt('bf', 12)),
     'James Taylor', TRUE, NOW()),

    ('10000000-0000-0000-0000-000000000005', 'viewer@nexus.ai',
     crypt('Viewer@123', gen_salt('bf', 12)),
     'Ana Kovacs', TRUE, NOW())
ON CONFLICT (email) DO UPDATE
    SET display_name  = EXCLUDED.display_name,
        password_hash = EXCLUDED.password_hash;

-- ─────────────────────────────────────────────────────────────────────────────
-- TENANT MEMBERSHIPS  (links identities to demo tenant with their roles)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO core_mdm.tenant_memberships
    (identity_id, tenant_id, role, status, joined_at)
VALUES
    ('10000000-0000-0000-0000-000000000001', :'demo_tenant', 'admin',          'active', NOW()),
    ('10000000-0000-0000-0000-000000000002', :'demo_tenant', 'business_admin', 'active', NOW()),
    ('10000000-0000-0000-0000-000000000003', :'demo_tenant', 'steward',        'active', NOW()),
    ('10000000-0000-0000-0000-000000000004', :'demo_tenant', 'analyst',        'active', NOW()),
    ('10000000-0000-0000-0000-000000000005', :'demo_tenant', 'viewer',         'active', NOW())
ON CONFLICT (identity_id, tenant_id) DO UPDATE
    SET role   = EXCLUDED.role,
        status = EXCLUDED.status;

-- ─────────────────────────────────────────────────────────────────────────────
-- ENTITY TYPE CONFIGS  (codes must match entity_type field values used in UI)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO core_mdm.entity_type_configs
    (tenant_id, code, name, seq_prefix, icon)
VALUES
    (:'demo_tenant', 'Customer',     'Customer',     'CUST', '👤'),
    (:'demo_tenant', 'Vendor',       'Vendor',       'VND',  '🏭'),
    (:'demo_tenant', 'Product',      'Product',      'PROD', '📦'),
    (:'demo_tenant', 'Material',     'Material',     'MAT',  '🔩'),
    (:'demo_tenant', 'Account',      'Account',      'ACC',  '🏢'),
    (:'demo_tenant', 'Employee',     'Employee',     'EMP',  '👷'),
    (:'demo_tenant', 'Location',     'Location',     'LOC',  '📍'),
    (:'demo_tenant', 'Organization', 'Organization', 'ORG',  '🌐'),
    (:'demo_tenant', 'Asset',        'Asset',        'AST',  '🏗️')
ON CONFLICT (tenant_id, code) DO UPDATE
    SET name       = EXCLUDED.name,
        seq_prefix = EXCLUDED.seq_prefix,
        icon       = EXCLUDED.icon;

-- ─────────────────────────────────────────────────────────────────────────────
-- SOURCE SYSTEMS
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO core_mdm.source_systems
    (source_id, tenant_id, name, system_type, trust_score, status)
VALUES
    ('20000000-0000-0000-0000-000000000001', :'demo_tenant', 'Salesforce CRM', 'crm',  0.94, 'active'),
    ('20000000-0000-0000-0000-000000000002', :'demo_tenant', 'SAP ERP',        'erp',  0.88, 'active'),
    ('20000000-0000-0000-0000-000000000003', :'demo_tenant', 'Oracle CRM',     'crm',  0.71, 'active'),
    ('20000000-0000-0000-0000-000000000004', :'demo_tenant', 'CSV Import',     'file', 0.60, 'active'),
    ('20000000-0000-0000-0000-000000000005', :'demo_tenant', 'HubSpot',        'crm',  0.82, 'active')
ON CONFLICT (tenant_id, name) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- CUSTOMERS (10 sample records)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO core_mdm.entities
    (entity_id, tenant_id, entity_type, status, external_ids, metadata, trust_score, source_system, valid_from, valid_to, created_at, updated_at)
VALUES
    ('30000000-0000-0000-0000-000000000001', :'demo_tenant',
     'Customer', 'Active',
     '{"salesforce":"SF-001234","sap":"K-9021"}',
     '{"legal_name":"Acme Corporation","email":"info@acme.com","phone":"+14085550100","country":"US","tax_id":"55-1234567","payment_terms":"Net30","industry":"Technology","annual_revenue":42000000}',
     0.96, 'Salesforce CRM', NOW(), 'infinity', NOW(), NOW()),

    ('30000000-0000-0000-0000-000000000002', :'demo_tenant',
     'Customer', 'Active',
     '{"salesforce":"SF-001235"}',
     '{"legal_name":"Global Tech Ltd","email":"contact@globaltech.com","phone":"+14089990200","country":"US","tax_id":"55-9876543","payment_terms":"Net60","industry":"Technology","annual_revenue":28000000}',
     0.91, 'Salesforce CRM', NOW(), 'infinity', NOW(), NOW()),

    ('30000000-0000-0000-0000-000000000003', :'demo_tenant',
     'Customer', 'Active',
     '{"sap":"K-9045","oracle":"ORA-778"}',
     '{"legal_name":"Techno Systems Inc","email":"sales@technosystems.com","phone":"+12125550300","country":"US","tax_id":"77-3456789","payment_terms":"Net45","industry":"Manufacturing","annual_revenue":85000000}',
     0.88, 'SAP ERP', NOW(), 'infinity', NOW(), NOW()),

    ('30000000-0000-0000-0000-000000000004', :'demo_tenant',
     'Customer', 'PendingReview',
     '{"hubspot":"HS-4421"}',
     '{"legal_name":"Sunrise Innovations LLC","email":"hello@sunriseinnovations.com","phone":"+13105550101","country":"US","tax_id":"88-1122334","payment_terms":"Net30","industry":"Technology"}',
     0.72, 'HubSpot', NOW(), 'infinity', NOW(), NOW()),

    ('30000000-0000-0000-0000-000000000005', :'demo_tenant',
     'Customer', 'Active',
     '{"salesforce":"SF-002100"}',
     '{"legal_name":"Pacific Retail Group","email":"procurement@pacificretail.com","phone":"+13235550500","country":"US","tax_id":"66-5544332","payment_terms":"Net30","industry":"Retail","annual_revenue":120000000}',
     0.93, 'Salesforce CRM', NOW(), 'infinity', NOW(), NOW()),

    ('30000000-0000-0000-0000-000000000006', :'demo_tenant',
     'Customer', 'Active',
     '{"sap":"K-3301"}',
     '{"legal_name":"Meridian Healthcare Systems","email":"billing@meridianhc.com","phone":"+16175550600","country":"US","tax_id":"44-7788990","payment_terms":"Net60","industry":"Healthcare","annual_revenue":310000000}',
     0.94, 'SAP ERP', NOW(), 'infinity', NOW(), NOW()),

    ('30000000-0000-0000-0000-000000000007', :'demo_tenant',
     'Customer', 'Active',
     '{"oracle":"ORA-991","salesforce":"SF-003300"}',
     '{"legal_name":"Blue Star Financial Services","email":"accounts@bluestarfinancial.com","phone":"+12125550700","country":"US","tax_id":"33-2211009","payment_terms":"Net90","industry":"Financial Services","annual_revenue":560000000}',
     0.95, 'Oracle CRM', NOW(), 'infinity', NOW(), NOW()),

    ('30000000-0000-0000-0000-000000000008', :'demo_tenant',
     'Customer', 'Inactive',
     '{"sap":"K-0088"}',
     '{"legal_name":"Vertex Energy Corporation","email":"info@vertexenergy.com","phone":"+17135550800","country":"US","tax_id":"22-8877665","payment_terms":"Net30","industry":"Energy"}',
     0.65, 'SAP ERP', NOW(), 'infinity', NOW(), NOW()),

    ('30000000-0000-0000-0000-000000000009', :'demo_tenant',
     'Customer', 'Draft',
     '{"csv":"ROW-0042"}',
     '{"legal_name":"CloudFirst Inc","email":"hello@cloudfirst.io","phone":"+14155550900","country":"US","industry":"SaaS"}',
     0.58, 'CSV Import', NOW(), 'infinity', NOW(), NOW()),

    ('30000000-0000-0000-0000-000000000010', :'demo_tenant',
     'Customer', 'Active',
     '{"salesforce":"SF-DEMO-01"}',
     '{"legal_name":"Nexus Demo Corporation","email":"demo@nexusdemo.com","phone":"+18005551234","country":"US","tax_id":"99-1234567","payment_terms":"Net30","industry":"Technology","annual_revenue":5000000}',
     0.97, 'Salesforce CRM', NOW(), 'infinity', NOW(), NOW())
ON CONFLICT (entity_id) DO UPDATE SET tenant_id = EXCLUDED.tenant_id, status = EXCLUDED.status, metadata = EXCLUDED.metadata, updated_at = NOW();

-- ─────────────────────────────────────────────────────────────────────────────
-- ENTITY ATTRIBUTES
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO core_mdm.entity_attributes
    (attribute_id, tenant_id, entity_id, attribute_key, attribute_value, data_type, confidence, source_system)
SELECT
    gen_random_uuid(),
    :'demo_tenant'::uuid,
    entity_id::uuid,
    key,
    value::jsonb,
    'string',
    0.9,
    source_system
FROM (
    VALUES
    ('30000000-0000-0000-0000-000000000001', 'customer_number', '"CUST-000001"', 'Salesforce CRM'),
    ('30000000-0000-0000-0000-000000000001', 'legal_name',      '"Acme Corporation"', 'Salesforce CRM'),
    ('30000000-0000-0000-0000-000000000001', 'email',           '"info@acme.com"', 'Salesforce CRM'),
    ('30000000-0000-0000-0000-000000000001', 'phone',           '"+14085550100"', 'Salesforce CRM'),
    ('30000000-0000-0000-0000-000000000001', 'tax_id',          '"55-1234567"', 'SAP ERP'),
    ('30000000-0000-0000-0000-000000000001', 'country',         '"US"', 'Salesforce CRM'),
    ('30000000-0000-0000-0000-000000000001', 'industry',        '"Technology"', 'Salesforce CRM'),
    ('30000000-0000-0000-0000-000000000001', 'payment_terms',   '"Net30"', 'Salesforce CRM'),
    ('30000000-0000-0000-0000-000000000002', 'customer_number', '"CUST-000002"', 'Salesforce CRM'),
    ('30000000-0000-0000-0000-000000000002', 'legal_name',      '"Global Tech Ltd"', 'Salesforce CRM'),
    ('30000000-0000-0000-0000-000000000002', 'email',           '"contact@globaltech.com"', 'Salesforce CRM'),
    ('30000000-0000-0000-0000-000000000002', 'phone',           '"+14089990200"', 'Salesforce CRM'),
    ('30000000-0000-0000-0000-000000000002', 'tax_id',          '"55-9876543"', 'Salesforce CRM'),
    ('30000000-0000-0000-0000-000000000005', 'customer_number', '"CUST-000005"', 'Salesforce CRM'),
    ('30000000-0000-0000-0000-000000000005', 'legal_name',      '"Pacific Retail Group"', 'Salesforce CRM'),
    ('30000000-0000-0000-0000-000000000005', 'email',           '"procurement@pacificretail.com"', 'Salesforce CRM'),
    ('30000000-0000-0000-0000-000000000005', 'annual_revenue',  '"120000000"', 'Salesforce CRM'),
    ('30000000-0000-0000-0000-000000000007', 'customer_number', '"CUST-000007"', 'Oracle CRM'),
    ('30000000-0000-0000-0000-000000000007', 'legal_name',      '"Blue Star Financial Services"', 'Oracle CRM'),
    ('30000000-0000-0000-0000-000000000007', 'email',           '"accounts@bluestarfinancial.com"', 'Oracle CRM'),
    ('30000000-0000-0000-0000-000000000007', 'tax_id',          '"33-2211009"', 'Oracle CRM')
) AS t(entity_id, key, value, source_system)
ON CONFLICT DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- VENDORS (5 sample records)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO core_mdm.entities
    (entity_id, tenant_id, entity_type, status, external_ids, metadata, trust_score, source_system, valid_from, valid_to, created_at, updated_at)
VALUES
    ('40000000-0000-0000-0000-000000000001', :'demo_tenant',
     'Vendor', 'Active', '{"sap":"V-001"}',
     '{"vendor_number":"VEND-000001","vendor_name":"Office Depot Supply Co","email":"orders@officedepot.com","phone":"+18005553210","category":"Office Supplies","payment_terms":"Net30","tax_id":"11-4455667","preferred":true}',
     0.92, 'SAP ERP', NOW(), 'infinity', NOW(), NOW()),

    ('40000000-0000-0000-0000-000000000002', :'demo_tenant',
     'Vendor', 'Active', '{"sap":"V-002","oracle":"ORA-V-100"}',
     '{"vendor_number":"VEND-000002","vendor_name":"CloudServe Technologies","email":"billing@cloudserve.io","phone":"+14155559876","category":"IT Services","payment_terms":"Net60","tax_id":"22-3344556","certifications":"ISO 27001, SOC2"}',
     0.89, 'SAP ERP', NOW(), 'infinity', NOW(), NOW()),

    ('40000000-0000-0000-0000-000000000003', :'demo_tenant',
     'Vendor', 'Active', '{"sap":"V-003"}',
     '{"vendor_number":"VEND-000003","vendor_name":"FastShip Logistics LLC","email":"ops@fastship.com","phone":"+13125558765","category":"Logistics","payment_terms":"Net15","tax_id":"33-5566778","lead_time_days":3}',
     0.85, 'SAP ERP', NOW(), 'infinity', NOW(), NOW()),

    ('40000000-0000-0000-0000-000000000004', :'demo_tenant',
     'Vendor', 'Inactive', '{"csv":"V-OLD-007"}',
     '{"vendor_number":"VEND-000004","vendor_name":"Legacy Systems Ltd","email":"contact@legacysys.com","phone":"+17325554321","category":"Software","payment_terms":"Net90"}',
     0.55, 'CSV Import', NOW(), 'infinity', NOW(), NOW()),

    ('40000000-0000-0000-0000-000000000005', :'demo_tenant',
     'Vendor', 'Active', '{"sap":"V-005"}',
     '{"vendor_number":"VEND-000005","vendor_name":"Quantum Raw Materials","email":"sales@quantumraw.com","phone":"+12025556789","category":"Raw Materials","payment_terms":"Net30","tax_id":"55-8899001","certifications":"ISO 9001"}',
     0.91, 'SAP ERP', NOW(), 'infinity', NOW(), NOW())
ON CONFLICT (entity_id) DO UPDATE SET tenant_id = EXCLUDED.tenant_id, status = EXCLUDED.status, metadata = EXCLUDED.metadata, updated_at = NOW();

-- ─────────────────────────────────────────────────────────────────────────────
-- PRODUCTS (5 sample records)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO core_mdm.entities
    (entity_id, tenant_id, entity_type, status, external_ids, metadata, trust_score, source_system, valid_from, valid_to, created_at, updated_at)
VALUES
    ('50000000-0000-0000-0000-000000000001', :'demo_tenant',
     'Product', 'Active', '{"sap_material":"MAT-10001"}',
     '{"product_number":"PROD-000001","product_name":"Enterprise MDM Platform License","sku":"MDM-ENT-001","product_type":"Service","category":"Software","uom":"EA","unit_price":50000,"currency":"USD","description":"Annual enterprise license for Nexus AI MDM platform"}',
     0.98, 'SAP ERP', NOW(), 'infinity', NOW(), NOW()),

    ('50000000-0000-0000-0000-000000000002', :'demo_tenant',
     'Product', 'Active', '{"sap_material":"MAT-10002"}',
     '{"product_number":"PROD-000002","product_name":"Professional Services — Implementation","sku":"PS-IMPL-001","product_type":"Service","category":"Consulting","uom":"HR","unit_price":250,"currency":"USD","description":"Data migration and implementation consulting hours"}',
     0.95, 'SAP ERP', NOW(), 'infinity', NOW(), NOW()),

    ('50000000-0000-0000-0000-000000000003', :'demo_tenant',
     'Product', 'Active', '{"barcode":"012345678901"}',
     '{"product_number":"PROD-000003","product_name":"Office Desk Ergonomic Pro","sku":"FURN-DESK-001","product_type":"Finished Goods","category":"Furniture","uom":"EA","unit_price":899,"currency":"USD","weight_kg":45,"manufacturer":"ErgoDesk Co"}',
     0.88, 'CSV Import', NOW(), 'infinity', NOW(), NOW()),

    ('50000000-0000-0000-0000-000000000004', :'demo_tenant',
     'Product', 'Discontinued', '{"sap_material":"MAT-09999"}',
     '{"product_number":"PROD-000004","product_name":"Legacy Data Connector","sku":"CONN-LEG-001","product_type":"Software","category":"Software","uom":"EA","unit_price":1200,"currency":"USD"}',
     0.72, 'SAP ERP', NOW(), 'infinity', NOW(), NOW()),

    ('50000000-0000-0000-0000-000000000005', :'demo_tenant',
     'Product', 'Active', '{"sap_material":"MAT-10005"}',
     '{"product_number":"PROD-000005","product_name":"AI Matching Module Add-on","sku":"MDM-AI-001","product_type":"Service","category":"Software","uom":"EA","unit_price":15000,"currency":"USD","description":"AI-powered entity matching and deduplication module"}',
     0.96, 'SAP ERP', NOW(), 'infinity', NOW(), NOW())
ON CONFLICT (entity_id) DO UPDATE SET tenant_id = EXCLUDED.tenant_id, status = EXCLUDED.status, metadata = EXCLUDED.metadata, updated_at = NOW();

-- ─────────────────────────────────────────────────────────────────────────────
-- GOLDEN RECORDS (2 merged master records)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO core_mdm.golden_records
    (golden_record_id, tenant_id, entity_type, status, lifecycle_stage, trust_score, quality_score, source_entities, metadata, valid_from, valid_to, created_at, updated_at)
VALUES
    ('60000000-0000-0000-0000-000000000001', :'demo_tenant',
     'Customer', 'Active', 'Published', 0.96, 0.94,
     ARRAY['30000000-0000-0000-0000-000000000001'::uuid],
     '{"legal_name":"Acme Corporation","email":"info@acme.com","phone":"+14085550100","tax_id":"55-1234567","country":"US","payment_terms":"Net30","industry":"Technology","annual_revenue":42000000,"source_count":2,"last_merged_at":"2024-06-01T10:00:00Z"}',
     NOW(), 'infinity', NOW(), NOW()),

    ('60000000-0000-0000-0000-000000000002', :'demo_tenant',
     'Customer', 'Active', 'Published', 0.95, 0.96,
     ARRAY['30000000-0000-0000-0000-000000000007'::uuid],
     '{"legal_name":"Blue Star Financial Services","email":"accounts@bluestarfinancial.com","phone":"+12125550700","tax_id":"33-2211009","country":"US","payment_terms":"Net90","industry":"Financial Services","annual_revenue":560000000,"source_count":2,"last_merged_at":"2024-06-02T14:30:00Z"}',
     NOW(), 'infinity', NOW(), NOW())
ON CONFLICT (golden_record_id) DO NOTHING;

UPDATE core_mdm.entities SET golden_record_id = '60000000-0000-0000-0000-000000000001'
WHERE entity_id = '30000000-0000-0000-0000-000000000001';

UPDATE core_mdm.entities SET golden_record_id = '60000000-0000-0000-0000-000000000002'
WHERE entity_id = '30000000-0000-0000-0000-000000000007';

-- ─────────────────────────────────────────────────────────────────────────────
-- MATCH CANDIDATES (review queue — 3 pairs for demo)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO core_mdm.match_candidates
    (match_candidate_id, tenant_id, request_id, source_entity_id, matched_entity_id,
     match_status, match_score, confidence_score, recommended_for_merge, requires_human_review,
     explanations, created_at, updated_at)
VALUES
    (gen_random_uuid(), :'demo_tenant',
     '70000000-0000-0000-0000-000000000001',
     '30000000-0000-0000-0000-000000000002',
     '30000000-0000-0000-0000-000000000004',
     'RequiresReview', 0.88, 0.85, FALSE, TRUE,
     '["Phone area code matches (310/408 — both Bay Area)","Industry match: Technology","Similar company size","Email domain differs","Tax ID not available for candidate"]',
     NOW() - INTERVAL '2 hours', NOW()),

    (gen_random_uuid(), :'demo_tenant',
     '70000000-0000-0000-0000-000000000002',
     '30000000-0000-0000-0000-000000000001',
     '30000000-0000-0000-0000-000000000010',
     'RequiresReview', 0.94, 0.92, TRUE, TRUE,
     '["Name similarity: Acme Corporation vs Nexus Demo Corporation (fuzzy 0.73)","Email domains differ","Both in Technology industry","Tax ID pattern similar","AI: likely different entities — Nexus Demo Corp is a test record"]',
     NOW() - INTERVAL '30 minutes', NOW()),

    (gen_random_uuid(), :'demo_tenant',
     '70000000-0000-0000-0000-000000000003',
     '30000000-0000-0000-0000-000000000009',
     '40000000-0000-0000-0000-000000000002',
     'RequiresReview', 0.79, 0.76, FALSE, TRUE,
     '["Name similarity: CloudFirst vs CloudServe (fuzzy 0.82)","Both SaaS/IT Services","Email domains differ","Phone area code matches (415 both)","Different entity types: Customer vs Vendor","AI: likely same company registered as both"]',
     NOW() - INTERVAL '4 hours', NOW())
ON CONFLICT DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- ENTITY SEQUENCES (initialise counters for demo tenant)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO core_mdm.entity_sequences
    (tenant_id, entity_type, current_value)
VALUES
    (:'demo_tenant', 'Customer', 10),
    (:'demo_tenant', 'Vendor',   5),
    (:'demo_tenant', 'Product',  5)
ON CONFLICT (tenant_id, entity_type)
DO UPDATE SET current_value = GREATEST(core_mdm.entity_sequences.current_value, EXCLUDED.current_value),
              updated_at    = NOW();

-- ─────────────────────────────────────────────────────────────────────────────
-- RAG KNOWLEDGE BASE (AI Copilot)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO ai.rag_documents
    (doc_id, tenant_id, doc_type, title, content, created_at, updated_at)
VALUES
    (gen_random_uuid(), :'demo_tenant', 'glossary', 'Golden Record',
     'A Golden Record is the authoritative master record for an entity, created by merging and deduplicating data from multiple source systems. It represents the single source of truth for that entity across the organisation.',
     NOW(), NOW()),

    (gen_random_uuid(), :'demo_tenant', 'glossary', 'Match Score',
     'A Match Score is a number between 0.0 and 1.0 representing the probability that two entity records refer to the same real-world entity. Scores above 0.95 trigger automatic merging. Scores between 0.75 and 0.95 are routed to human stewards for review. Scores below 0.75 are classified as non-matches.',
     NOW(), NOW()),

    (gen_random_uuid(), :'demo_tenant', 'glossary', 'Survivorship Rules',
     'Survivorship Rules determine which attribute value wins when the same field has different values across source systems. Common strategies include: TrustedSource (prefer a specific system), MostRecent (use the most recently updated value), LongestValue (use the longest non-empty string), and HighestConfidence (use the value with the highest quality score).',
     NOW(), NOW()),

    (gen_random_uuid(), :'demo_tenant', 'policy', 'Data Quality Thresholds',
     'Nexus AI MDM enforces minimum quality standards: Customer entities require email OR phone to be present. Tax ID must follow format XX-XXXXXXX for US entities. Vendor records require at least one contact method and a valid payment terms value. Entities with a trust score below 0.60 are flagged for data steward review.',
     NOW(), NOW()),

    (gen_random_uuid(), :'demo_tenant', 'policy', 'Customer Data Standards',
     'Customer entities in Nexus MDM include these standard attributes: legal_name (required), email (required), phone, mobile, website, tax_id, country, billing_address, shipping_address, credit_limit, payment_terms (Net30/Net60/Net90), currency, industry, annual_revenue, employee_count, customer_type (Individual/Corporation/Government).',
     NOW(), NOW())
ON CONFLICT DO NOTHING;

COMMIT;
