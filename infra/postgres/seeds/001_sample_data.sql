-- =============================================================================
-- Nexus AI MDM — Sample Data Seed
-- Provides demo users, entities, and match candidates for development/demo.
-- =============================================================================
-- Run with:
--   docker exec -i nexus-postgres psql -U postgres -d nexus_mdm < seeds/001_sample_data.sql
-- =============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- CONSTANTS
-- ─────────────────────────────────────────────────────────────────────────────
-- Default tenant (seeded by migration 0006)
\set tenant_id '00000000-0000-0000-0000-000000000001'

-- ─────────────────────────────────────────────────────────────────────────────
-- USERS
-- Passwords are hashed with bcrypt cost 12 via pgcrypto.
-- Compatible with the Rust bcrypt crate used in mdm-core.
--
--   admin@nexus.ai    /  Admin@123456
--   steward@nexus.ai  /  Steward@123
--   analyst@nexus.ai  /  Analyst@123
--   viewer@nexus.ai   /  Viewer@123
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO core_mdm.users
    (user_id, tenant_id, email, display_name, role, password_hash, status, is_verified, created_at)
VALUES
    -- Admin — full platform access
    (
        '10000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000001',
        'admin@nexus.ai',
        'Platform Admin',
        'admin',
        crypt('Admin@123456', gen_salt('bf', 12)),
        'active', TRUE, NOW()
    ),
    -- Data Steward — review and approve merges
    (
        '10000000-0000-0000-0000-000000000002',
        '00000000-0000-0000-0000-000000000001',
        'steward@nexus.ai',
        'Sarah Chen',
        'steward',
        crypt('Steward@123', gen_salt('bf', 12)),
        'active', TRUE, NOW()
    ),
    -- Data Analyst — run searches and reports
    (
        '10000000-0000-0000-0000-000000000003',
        '00000000-0000-0000-0000-000000000001',
        'analyst@nexus.ai',
        'James Taylor',
        'analyst',
        crypt('Analyst@123', gen_salt('bf', 12)),
        'active', TRUE, NOW()
    ),
    -- Read-only viewer
    (
        '10000000-0000-0000-0000-000000000004',
        '00000000-0000-0000-0000-000000000001',
        'viewer@nexus.ai',
        'Ana Kovacs',
        'viewer',
        crypt('Viewer@123', gen_salt('bf', 12)),
        'active', TRUE, NOW()
    )
ON CONFLICT (tenant_id, email) DO UPDATE
    SET display_name  = EXCLUDED.display_name,
        password_hash = EXCLUDED.password_hash;

-- ─────────────────────────────────────────────────────────────────────────────
-- SOURCE SYSTEMS
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO core_mdm.source_systems
    (source_id, tenant_id, name, system_type, trust_score, status)
VALUES
    ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
     'Salesforce CRM',  'crm',       0.94, 'active'),
    ('20000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001',
     'SAP ERP',         'erp',       0.88, 'active'),
    ('20000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001',
     'Oracle CRM',      'crm',       0.71, 'active'),
    ('20000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000001',
     'CSV Import',      'file',      0.60, 'active'),
    ('20000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000001',
     'HubSpot',         'crm',       0.82, 'active')
ON CONFLICT (tenant_id, name) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- CUSTOMERS (10 sample records)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO core_mdm.entities
    (entity_id, tenant_id, entity_type, status, external_ids, metadata, trust_score, source_system, valid_from, valid_to, created_at, updated_at)
VALUES
    -- 1. Acme Corporation (active, high trust)
    ('30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
     'Customer', 'Active',
     '{"salesforce": "SF-001234", "sap": "K-9021"}',
     '{"legal_name":"Acme Corporation","email":"info@acme.com","phone":"+14085550100","country":"US","tax_id":"55-1234567","payment_terms":"Net30","industry":"Technology","annual_revenue":42000000}',
     0.96, 'Salesforce CRM', NOW(), 'infinity', NOW(), NOW()),

    -- 2. Global Tech Ltd (active)
    ('30000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001',
     'Customer', 'Active',
     '{"salesforce": "SF-001235"}',
     '{"legal_name":"Global Tech Ltd","email":"contact@globaltech.com","phone":"+14089990200","country":"US","tax_id":"55-9876543","payment_terms":"Net60","industry":"Technology","annual_revenue":28000000}',
     0.91, 'Salesforce CRM', NOW(), 'infinity', NOW(), NOW()),

    -- 3. Techno Systems Inc (active)
    ('30000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001',
     'Customer', 'Active',
     '{"sap": "K-9045", "oracle": "ORA-778"}',
     '{"legal_name":"Techno Systems Inc","email":"sales@technosystems.com","phone":"+12125550300","country":"US","tax_id":"77-3456789","payment_terms":"Net45","industry":"Manufacturing","annual_revenue":85000000}',
     0.88, 'SAP ERP', NOW(), 'infinity', NOW(), NOW()),

    -- 4. Sunrise Innovations (pending review — potential duplicate of #2)
    ('30000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000001',
     'Customer', 'PendingReview',
     '{"hubspot": "HS-4421"}',
     '{"legal_name":"Sunrise Innovations LLC","email":"hello@sunriseinnovations.com","phone":"+13105550101","country":"US","tax_id":"88-1122334","payment_terms":"Net30","industry":"Technology"}',
     0.72, 'HubSpot', NOW(), 'infinity', NOW(), NOW()),

    -- 5. Pacific Retail Group (active)
    ('30000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000001',
     'Customer', 'Active',
     '{"salesforce": "SF-002100"}',
     '{"legal_name":"Pacific Retail Group","email":"procurement@pacificretail.com","phone":"+13235550500","country":"US","tax_id":"66-5544332","payment_terms":"Net30","industry":"Retail","annual_revenue":120000000}',
     0.93, 'Salesforce CRM', NOW(), 'infinity', NOW(), NOW()),

    -- 6. Meridian Healthcare (active)
    ('30000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000001',
     'Customer', 'Active',
     '{"sap": "K-3301"}',
     '{"legal_name":"Meridian Healthcare Systems","email":"billing@meridianhc.com","phone":"+16175550600","country":"US","tax_id":"44-7788990","payment_terms":"Net60","industry":"Healthcare","annual_revenue":310000000}',
     0.94, 'SAP ERP', NOW(), 'infinity', NOW(), NOW()),

    -- 7. Blue Star Financial (active)
    ('30000000-0000-0000-0000-000000000007', '00000000-0000-0000-0000-000000000001',
     'Customer', 'Active',
     '{"oracle": "ORA-991", "salesforce": "SF-003300"}',
     '{"legal_name":"Blue Star Financial Services","email":"accounts@bluestarfinancial.com","phone":"+12125550700","country":"US","tax_id":"33-2211009","payment_terms":"Net90","industry":"Financial Services","annual_revenue":560000000}',
     0.95, 'Oracle CRM', NOW(), 'infinity', NOW(), NOW()),

    -- 8. Vertex Energy Corp (inactive)
    ('30000000-0000-0000-0000-000000000008', '00000000-0000-0000-0000-000000000001',
     'Customer', 'Inactive',
     '{"sap": "K-0088"}',
     '{"legal_name":"Vertex Energy Corporation","email":"info@vertexenergy.com","phone":"+17135550800","country":"US","tax_id":"22-8877665","payment_terms":"Net30","industry":"Energy"}',
     0.65, 'SAP ERP', NOW(), 'infinity', NOW(), NOW()),

    -- 9. CloudFirst Inc (active — low trust, CSV import)
    ('30000000-0000-0000-0000-000000000009', '00000000-0000-0000-0000-000000000001',
     'Customer', 'Active',
     '{"csv": "ROW-0042"}',
     '{"legal_name":"CloudFirst Inc","email":"hello@cloudfirst.io","phone":"+14155550900","country":"US","industry":"SaaS"}',
     0.58, 'CSV Import', NOW(), 'infinity', NOW(), NOW()),

    -- 10. Nexus Demo Corp (active — for end-to-end testing)
    ('30000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000001',
     'Customer', 'Active',
     '{"salesforce": "SF-DEMO-01"}',
     '{"legal_name":"Nexus Demo Corporation","email":"demo@nexusdemo.com","phone":"+18005551234","country":"US","tax_id":"99-1234567","payment_terms":"Net30","industry":"Technology","annual_revenue":5000000}',
     0.97, 'Salesforce CRM', NOW(), 'infinity', NOW(), NOW())
ON CONFLICT (entity_id) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- ENTITY ATTRIBUTES for Customers
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO core_mdm.entity_attributes
    (attribute_id, tenant_id, entity_id, attribute_key, attribute_value, data_type, confidence, source_system)
SELECT
    gen_random_uuid(),
    '00000000-0000-0000-0000-000000000001'::uuid,
    entity_id::uuid,
    key,
    value::jsonb,
    'string',
    0.9,
    source_system
FROM (
    VALUES
    -- Acme Corporation
    ('30000000-0000-0000-0000-000000000001', 'customer_number', '"CUST-000001"', 'Salesforce CRM'),
    ('30000000-0000-0000-0000-000000000001', 'legal_name',      '"Acme Corporation"', 'Salesforce CRM'),
    ('30000000-0000-0000-0000-000000000001', 'email',           '"info@acme.com"', 'Salesforce CRM'),
    ('30000000-0000-0000-0000-000000000001', 'phone',           '"+14085550100"', 'Salesforce CRM'),
    ('30000000-0000-0000-0000-000000000001', 'tax_id',          '"55-1234567"', 'SAP ERP'),
    ('30000000-0000-0000-0000-000000000001', 'country',         '"US"', 'Salesforce CRM'),
    ('30000000-0000-0000-0000-000000000001', 'industry',        '"Technology"', 'Salesforce CRM'),
    ('30000000-0000-0000-0000-000000000001', 'payment_terms',   '"Net30"', 'Salesforce CRM'),
    ('30000000-0000-0000-0000-000000000001', 'status',          '"Active"', 'Salesforce CRM'),
    -- Global Tech Ltd
    ('30000000-0000-0000-0000-000000000002', 'customer_number', '"CUST-000002"', 'Salesforce CRM'),
    ('30000000-0000-0000-0000-000000000002', 'legal_name',      '"Global Tech Ltd"', 'Salesforce CRM'),
    ('30000000-0000-0000-0000-000000000002', 'email',           '"contact@globaltech.com"', 'Salesforce CRM'),
    ('30000000-0000-0000-0000-000000000002', 'phone',           '"+14089990200"', 'Salesforce CRM'),
    ('30000000-0000-0000-0000-000000000002', 'tax_id',          '"55-9876543"', 'Salesforce CRM'),
    -- Pacific Retail Group
    ('30000000-0000-0000-0000-000000000005', 'customer_number', '"CUST-000005"', 'Salesforce CRM'),
    ('30000000-0000-0000-0000-000000000005', 'legal_name',      '"Pacific Retail Group"', 'Salesforce CRM'),
    ('30000000-0000-0000-0000-000000000005', 'email',           '"procurement@pacificretail.com"', 'Salesforce CRM'),
    ('30000000-0000-0000-0000-000000000005', 'annual_revenue',  '"120000000"', 'Salesforce CRM'),
    -- Blue Star Financial
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
    ('40000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
     'Vendor', 'Active',
     '{"sap": "V-001"}',
     '{"vendor_number":"VEND-000001","vendor_name":"Office Depot Supply Co","email":"orders@officedepot.com","phone":"+18005553210","category":"Office Supplies","payment_terms":"Net30","tax_id":"11-4455667","preferred":true}',
     0.92, 'SAP ERP', NOW(), 'infinity', NOW(), NOW()),

    ('40000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001',
     'Vendor', 'Active',
     '{"sap": "V-002", "oracle": "ORA-V-100"}',
     '{"vendor_number":"VEND-000002","vendor_name":"CloudServe Technologies","email":"billing@cloudserve.io","phone":"+14155559876","category":"IT Services","payment_terms":"Net60","tax_id":"22-3344556","certifications":"ISO 27001, SOC2"}',
     0.89, 'SAP ERP', NOW(), 'infinity', NOW(), NOW()),

    ('40000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001',
     'Vendor', 'Active',
     '{"sap": "V-003"}',
     '{"vendor_number":"VEND-000003","vendor_name":"FastShip Logistics LLC","email":"ops@fastship.com","phone":"+13125558765","category":"Logistics","payment_terms":"Net15","tax_id":"33-5566778","lead_time_days":3}',
     0.85, 'SAP ERP', NOW(), 'infinity', NOW(), NOW()),

    ('40000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000001',
     'Vendor', 'Inactive',
     '{"csv": "V-OLD-007"}',
     '{"vendor_number":"VEND-000004","vendor_name":"Legacy Systems Ltd","email":"contact@legacysys.com","phone":"+17325554321","category":"Software","payment_terms":"Net90"}',
     0.55, 'CSV Import', NOW(), 'infinity', NOW(), NOW()),

    ('40000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000001',
     'Vendor', 'Active',
     '{"sap": "V-005"}',
     '{"vendor_number":"VEND-000005","vendor_name":"Quantum Raw Materials","email":"sales@quantumraw.com","phone":"+12025556789","category":"Raw Materials","payment_terms":"Net30","tax_id":"55-8899001","certifications":"ISO 9001"}',
     0.91, 'SAP ERP', NOW(), 'infinity', NOW(), NOW())
ON CONFLICT (entity_id) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- PRODUCTS (5 sample records)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO core_mdm.entities
    (entity_id, tenant_id, entity_type, status, external_ids, metadata, trust_score, source_system, valid_from, valid_to, created_at, updated_at)
VALUES
    ('50000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
     'Product', 'Active',
     '{"sap_material": "MAT-10001"}',
     '{"product_number":"PROD-000001","product_name":"Enterprise MDM Platform License","sku":"MDM-ENT-001","product_type":"Service","category":"Software","uom":"EA","unit_price":50000,"currency":"USD","description":"Annual enterprise license for Nexus AI MDM platform"}',
     0.98, 'SAP ERP', NOW(), 'infinity', NOW(), NOW()),

    ('50000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001',
     'Product', 'Active',
     '{"sap_material": "MAT-10002"}',
     '{"product_number":"PROD-000002","product_name":"Professional Services — Implementation","sku":"PS-IMPL-001","product_type":"Service","category":"Consulting","uom":"HR","unit_price":250,"currency":"USD","description":"Data migration and implementation consulting hours"}',
     0.95, 'SAP ERP', NOW(), 'infinity', NOW(), NOW()),

    ('50000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001',
     'Product', 'Active',
     '{"barcode": "012345678901"}',
     '{"product_number":"PROD-000003","product_name":"Office Desk Ergonomic Pro","sku":"FURN-DESK-001","product_type":"Finished Goods","category":"Furniture","uom":"EA","unit_price":899,"currency":"USD","weight_kg":45,"manufacturer":"ErgoDesk Co"}',
     0.88, 'CSV Import', NOW(), 'infinity', NOW(), NOW()),

    ('50000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000001',
     'Product', 'Discontinued',
     '{"sap_material": "MAT-09999"}',
     '{"product_number":"PROD-000004","product_name":"Legacy Data Connector","sku":"CONN-LEG-001","product_type":"Software","category":"Software","uom":"EA","unit_price":1200,"currency":"USD"}',
     0.72, 'SAP ERP', NOW(), 'infinity', NOW(), NOW()),

    ('50000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000001',
     'Product', 'Active',
     '{"sap_material": "MAT-10005"}',
     '{"product_number":"PROD-000005","product_name":"AI Matching Module Add-on","sku":"MDM-AI-001","product_type":"Service","category":"Software","uom":"EA","unit_price":15000,"currency":"USD","description":"AI-powered entity matching and deduplication module"}',
     0.96, 'SAP ERP', NOW(), 'infinity', NOW(), NOW())
ON CONFLICT (entity_id) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- GOLDEN RECORDS (2 merged records for demo)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO core_mdm.golden_records
    (golden_record_id, tenant_id, entity_type, status, lifecycle_stage, trust_score, quality_score, source_entities, metadata, valid_from, valid_to, created_at, updated_at)
VALUES
    -- Merged: Acme Corporation (master from Salesforce + SAP)
    ('60000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
     'Customer', 'Active', 'Published',
     0.96, 0.94,
     ARRAY['30000000-0000-0000-0000-000000000001'::uuid],
     '{"legal_name":"Acme Corporation","email":"info@acme.com","phone":"+14085550100","tax_id":"55-1234567","country":"US","payment_terms":"Net30","industry":"Technology","annual_revenue":42000000,"source_count":2,"last_merged_at":"2024-06-01T10:00:00Z"}',
     NOW(), 'infinity', NOW(), NOW()),
    -- Merged: Blue Star Financial (master from Oracle + Salesforce)
    ('60000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001',
     'Customer', 'Active', 'Published',
     0.95, 0.96,
     ARRAY['30000000-0000-0000-0000-000000000007'::uuid],
     '{"legal_name":"Blue Star Financial Services","email":"accounts@bluestarfinancial.com","phone":"+12125550700","tax_id":"33-2211009","country":"US","payment_terms":"Net90","industry":"Financial Services","annual_revenue":560000000,"source_count":2,"last_merged_at":"2024-06-02T14:30:00Z"}',
     NOW(), 'infinity', NOW(), NOW())
ON CONFLICT (golden_record_id) DO NOTHING;

-- Link entities to their golden records
UPDATE core_mdm.entities
SET golden_record_id = '60000000-0000-0000-0000-000000000001'
WHERE entity_id = '30000000-0000-0000-0000-000000000001';

UPDATE core_mdm.entities
SET golden_record_id = '60000000-0000-0000-0000-000000000002'
WHERE entity_id = '30000000-0000-0000-0000-000000000007';

-- ─────────────────────────────────────────────────────────────────────────────
-- MATCH CANDIDATES (review queue — 3 pairs for demo)
-- ─────────────────────────────────────────────────────────────────────────────

-- Match 1: Global Tech Ltd vs Sunrise Innovations (score 0.88 — HIGH priority)
INSERT INTO core_mdm.match_candidates
    (match_candidate_id, tenant_id, request_id, source_entity_id, matched_entity_id,
     match_status, match_score, confidence_score, recommended_for_merge, requires_human_review,
     explanations, created_at, updated_at)
VALUES
    (gen_random_uuid(),
     '00000000-0000-0000-0000-000000000001',
     '70000000-0000-0000-0000-000000000001',
     '30000000-0000-0000-0000-000000000002',
     '30000000-0000-0000-0000-000000000004',
     'RequiresReview', 0.88, 0.85,
     FALSE, TRUE,
     '["Phone area code matches (310/408 — both Bay Area)","Industry match: Technology","Similar company size","Email domain differs: globaltech.com vs sunriseinnovations.com","Tax ID not available for candidate"]',
     NOW() - INTERVAL '2 hours', NOW())
ON CONFLICT DO NOTHING;

-- Match 2: Acme Corporation vs ACME Corp (score 0.94 — CRITICAL, near auto-merge)
INSERT INTO core_mdm.match_candidates
    (match_candidate_id, tenant_id, request_id, source_entity_id, matched_entity_id,
     match_status, match_score, confidence_score, recommended_for_merge, requires_human_review,
     explanations, created_at, updated_at)
VALUES
    (gen_random_uuid(),
     '00000000-0000-0000-0000-000000000001',
     '70000000-0000-0000-0000-000000000002',
     '30000000-0000-0000-0000-000000000001',
     '30000000-0000-0000-0000-000000000010',
     'RequiresReview', 0.94, 0.92,
     TRUE, TRUE,
     '["Name match: Acme Corporation vs Nexus Demo Corporation (fuzzy 0.73)","Email domain: acme.com vs nexusdemo.com (no match)","Phone: +1-408-555-0100 vs +1-800-555-1234 (different)","Both in Technology industry","Tax ID: 55-1234567 vs 99-1234567 (similar pattern)","AI assessment: Different entities — Nexus Demo Corp is a test record"]',
     NOW() - INTERVAL '30 minutes', NOW())
ON CONFLICT DO NOTHING;

-- Match 3: CloudFirst Inc vs CloudServe Technologies (score 0.79 — MEDIUM)
INSERT INTO core_mdm.match_candidates
    (match_candidate_id, tenant_id, request_id, source_entity_id, matched_entity_id,
     match_status, match_score, confidence_score, recommended_for_merge, requires_human_review,
     explanations, created_at, updated_at)
VALUES
    (gen_random_uuid(),
     '00000000-0000-0000-0000-000000000001',
     '70000000-0000-0000-0000-000000000003',
     '30000000-0000-0000-0000-000000000009',
     '40000000-0000-0000-0000-000000000002',
     'RequiresReview', 0.79, 0.76,
     FALSE, TRUE,
     '["Name similarity: CloudFirst vs CloudServe (fuzzy 0.82)","Both SaaS/IT Services","Email domains differ: cloudfirst.io vs cloudserve.io","Phone area codes differ (415 vs 415 — same!)","Different entity types: Customer vs Vendor","AI assessment: Likely same company registered as both customer and vendor"]',
     NOW() - INTERVAL '4 hours', NOW())
ON CONFLICT DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- UPDATE NUMBER SEQUENCES (so next generated numbers continue from here)
-- ─────────────────────────────────────────────────────────────────────────────

UPDATE core_mdm.entity_sequences
SET current_value = GREATEST(current_value, 10),
    updated_at    = NOW()
WHERE tenant_id   = '00000000-0000-0000-0000-000000000001'
  AND entity_type IN ('Customer', 'Vendor', 'Product');

-- ─────────────────────────────────────────────────────────────────────────────
-- RAG KNOWLEDGE BASE (seed a few documents for the AI copilot)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO ai.rag_documents
    (doc_id, tenant_id, doc_type, title, content, created_at, updated_at)
VALUES
    (gen_random_uuid(),
     '00000000-0000-0000-0000-000000000001',
     'glossary',
     'Golden Record',
     'A Golden Record is the authoritative master record for an entity, created by merging and deduplicating data from multiple source systems. It represents the single source of truth for that entity across the organisation. Golden Records are produced by applying survivorship rules to determine the best attribute value from competing sources.',
     NOW(), NOW()),
    (gen_random_uuid(),
     '00000000-0000-0000-0000-000000000001',
     'glossary',
     'Match Score',
     'A Match Score is a number between 0.0 and 1.0 representing the probability that two entity records refer to the same real-world entity. Scores above 0.95 trigger automatic merging. Scores between 0.75 and 0.95 are routed to human stewards for review. Scores below 0.75 are classified as non-matches.',
     NOW(), NOW()),
    (gen_random_uuid(),
     '00000000-0000-0000-0000-000000000001',
     'glossary',
     'Survivorship Rules',
     'Survivorship Rules determine which attribute value wins when the same field has different values across source systems. Common strategies include: TrustedSource (prefer a specific system), MostRecent (use the most recently updated value), LongestValue (use the longest non-empty string), and HighestConfidence (use the value with the highest quality score).',
     NOW(), NOW()),
    (gen_random_uuid(),
     '00000000-0000-0000-0000-000000000001',
     'policy',
     'Data Quality Thresholds',
     'Nexus AI MDM enforces minimum quality standards: Customer entities require email OR phone to be present. Tax ID must follow format XX-XXXXXXX for US entities. Vendor records require at least one contact method and a valid payment terms value. Entities with a trust score below 0.60 are flagged for data steward review.',
     NOW(), NOW()),
    (gen_random_uuid(),
     '00000000-0000-0000-0000-000000000001',
     'entity_schema',
     'Customer Entity Schema',
     'Customer entities in Nexus MDM include these standard attributes: legal_name (required), email (required), phone, mobile, website, tax_id, vat_number, country, billing_address, shipping_address, credit_limit, payment_terms (Net30/Net60/Net90), currency, industry, annual_revenue, employee_count, account_manager, customer_type (Individual/Corporation/Government), status (Active/Inactive/Prospect/On Hold).',
     NOW(), NOW())
ON CONFLICT DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- POLICY RULES (default governance rules)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO governance.policy_rules
    (rule_id, tenant_id, name, description, rule_type, entity_type, field_name, rego_policy, priority, status, created_at, updated_at)
VALUES
    (gen_random_uuid(),
     '00000000-0000-0000-0000-000000000001',
     'Mask SSN for non-admin',
     'Mask social security numbers for all roles except admin',
     'field_mask', NULL, 'ssn',
     'package mdm.policy
default allow = true
masked_fields[field] { field := "ssn"; input.user_role != "admin" }',
     10, 'active', NOW(), NOW()),
    (gen_random_uuid(),
     '00000000-0000-0000-0000-000000000001',
     'Require email or phone for Customer',
     'Customers must have at least one contact method',
     'mandatory_field', 'Customer', NULL,
     'package mdm.policy
default allow = true
required_fields[f] {
  input.entity_type == "Customer"
  f := "email"
  not input.entity.email
  not input.entity.phone
}',
     20, 'active', NOW(), NOW())
ON CONFLICT (tenant_id, name) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- SUMMARY
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_users     INT;
    v_entities  INT;
    v_golden    INT;
    v_matches   INT;
    v_rag_docs  INT;
BEGIN
    SELECT COUNT(*) INTO v_users    FROM core_mdm.users     WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
    SELECT COUNT(*) INTO v_entities FROM core_mdm.entities  WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
    SELECT COUNT(*) INTO v_golden   FROM core_mdm.golden_records WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
    SELECT COUNT(*) INTO v_matches  FROM core_mdm.match_candidates WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
    SELECT COUNT(*) INTO v_rag_docs FROM ai.rag_documents   WHERE tenant_id = '00000000-0000-0000-0000-000000000001';

    RAISE NOTICE '════════════════════════════════════════';
    RAISE NOTICE '  Nexus MDM — Seed Complete';
    RAISE NOTICE '════════════════════════════════════════';
    RAISE NOTICE '  Users:          %', v_users;
    RAISE NOTICE '  Entities:       % (10 customers, 5 vendors, 5 products)', v_entities;
    RAISE NOTICE '  Golden Records: %', v_golden;
    RAISE NOTICE '  Match Queue:    % items pending review', v_matches;
    RAISE NOTICE '  RAG Documents:  %', v_rag_docs;
    RAISE NOTICE '════════════════════════════════════════';
    RAISE NOTICE '  Login credentials:';
    RAISE NOTICE '    admin@nexus.ai   /  Admin@123456  (admin)';
    RAISE NOTICE '    steward@nexus.ai /  Steward@123   (steward)';
    RAISE NOTICE '    analyst@nexus.ai /  Analyst@123   (analyst)';
    RAISE NOTICE '    viewer@nexus.ai  /  Viewer@123    (viewer)';
    RAISE NOTICE '════════════════════════════════════════';
END;
$$;

COMMIT;
