--
-- ============================================================
-- SEED ENTITY MODELS
-- FILE: 000020_seed_entity_models.sql
-- ============================================================
--
-- Seeds enterprise-grade default MDM entity models.
--
-- Includes:
--
-- 1. Customer
-- 2. Organization
-- 3. Product
-- 4. Supplier
-- 5. Employee
-- 6. Location
-- 7. Asset
-- 8. Financial Account
--
-- Also seeds:
--
-- - Attribute definitions
-- - Searchable fields
-- - Matching hints
-- - Survivorship hints
-- - AI/vector metadata
--
-- ============================================================
--

BEGIN;

--
-- ============================================================
-- SYSTEM TENANT
-- ============================================================
--

DO
$$
BEGIN

    IF NOT EXISTS
    (
        SELECT 1
        FROM core.tenants
        WHERE tenant_id =
            '00000000-0000-0000-0000-000000000001'
    )
    THEN

        RAISE EXCEPTION
        'System tenant does not exist. Run migration 000019 first.';
    END IF;

END;
$$;

--
-- ============================================================
-- CUSTOMER ENTITY TYPE
-- ============================================================
--

INSERT INTO core_mdm.entity_types
(
    entity_type_id,

    tenant_id,

    entity_type_name,

    display_name,

    description,

    category,

    version,

    is_system,

    supports_matching,

    supports_survivorship,

    supports_vectors,

    metadata,

    created_at,

    updated_at
)
VALUES
(
    '10000000-0000-0000-0000-000000000001',

    '00000000-0000-0000-0000-000000000001',

    'customer',

    'Customer',

    'Master customer profile',

    'Party',

    1,

    TRUE,

    TRUE,

    TRUE,

    TRUE,

    jsonb_build_object(

        'icon', 'user',

        'searchable', true,

        'vector_enabled', true,

        'matching_strategy', 'Hybrid',

        'survivorship_enabled', true
    ),

    NOW(),

    NOW()
)

ON CONFLICT (entity_type_id)
DO NOTHING;

--
-- ============================================================
-- ORGANIZATION ENTITY TYPE
-- ============================================================
--

INSERT INTO core_mdm.entity_types
(
    entity_type_id,
    tenant_id,
    entity_type_name,
    display_name,
    description,
    category,
    version,
    is_system,
    supports_matching,
    supports_survivorship,
    supports_vectors,
    metadata,
    created_at,
    updated_at
)
VALUES
(
    '10000000-0000-0000-0000-000000000002',

    '00000000-0000-0000-0000-000000000001',

    'organization',

    'Organization',

    'Organization master data',

    'Business',

    1,

    TRUE,

    TRUE,

    TRUE,

    TRUE,

    jsonb_build_object(

        'icon', 'building',

        'searchable', true,

        'vector_enabled', true
    ),

    NOW(),

    NOW()
)

ON CONFLICT (entity_type_id)
DO NOTHING;

--
-- ============================================================
-- PRODUCT ENTITY TYPE
-- ============================================================
--

INSERT INTO core_mdm.entity_types
(
    entity_type_id,
    tenant_id,
    entity_type_name,
    display_name,
    description,
    category,
    version,
    is_system,
    supports_matching,
    supports_survivorship,
    supports_vectors,
    metadata,
    created_at,
    updated_at
)
VALUES
(
    '10000000-0000-0000-0000-000000000003',

    '00000000-0000-0000-0000-000000000001',

    'product',

    'Product',

    'Product master data',

    'Catalog',

    1,

    TRUE,

    TRUE,

    TRUE,

    TRUE,

    jsonb_build_object(

        'icon', 'package',

        'searchable', true,

        'vector_enabled', true
    ),

    NOW(),

    NOW()
)

ON CONFLICT (entity_type_id)
DO NOTHING;

--
-- ============================================================
-- SUPPLIER ENTITY TYPE
-- ============================================================
--

INSERT INTO core_mdm.entity_types
(
    entity_type_id,
    tenant_id,
    entity_type_name,
    display_name,
    description,
    category,
    version,
    is_system,
    supports_matching,
    supports_survivorship,
    supports_vectors,
    metadata,
    created_at,
    updated_at
)
VALUES
(
    '10000000-0000-0000-0000-000000000004',

    '00000000-0000-0000-0000-000000000001',

    'supplier',

    'Supplier',

    'Supplier master data',

    'Procurement',

    1,

    TRUE,

    TRUE,

    TRUE,

    TRUE,

    jsonb_build_object(

        'icon', 'truck',

        'searchable', true,

        'vector_enabled', true
    ),

    NOW(),

    NOW()
)

ON CONFLICT (entity_type_id)
DO NOTHING;

--
-- ============================================================
-- EMPLOYEE ENTITY TYPE
-- ============================================================
--

INSERT INTO core_mdm.entity_types
(
    entity_type_id,
    tenant_id,
    entity_type_name,
    display_name,
    description,
    category,
    version,
    is_system,
    supports_matching,
    supports_survivorship,
    supports_vectors,
    metadata,
    created_at,
    updated_at
)
VALUES
(
    '10000000-0000-0000-0000-000000000005',

    '00000000-0000-0000-0000-000000000001',

    'employee',

    'Employee',

    'Employee master data',

    'HR',

    1,

    TRUE,

    TRUE,

    TRUE,

    TRUE,

    jsonb_build_object(

        'icon', 'users',

        'searchable', true,

        'vector_enabled', true
    ),

    NOW(),

    NOW()
)

ON CONFLICT (entity_type_id)
DO NOTHING;

--
-- ============================================================
-- LOCATION ENTITY TYPE
-- ============================================================
--

INSERT INTO core_mdm.entity_types
(
    entity_type_id,
    tenant_id,
    entity_type_name,
    display_name,
    description,
    category,
    version,
    is_system,
    supports_matching,
    supports_survivorship,
    supports_vectors,
    metadata,
    created_at,
    updated_at
)
VALUES
(
    '10000000-0000-0000-0000-000000000006',

    '00000000-0000-0000-0000-000000000001',

    'location',

    'Location',

    'Physical locations and addresses',

    'Geography',

    1,

    TRUE,

    TRUE,

    TRUE,

    TRUE,

    jsonb_build_object(

        'icon', 'map-pin',

        'searchable', true,

        'vector_enabled', true
    ),

    NOW(),

    NOW()
)

ON CONFLICT (entity_type_id)
DO NOTHING;

--
-- ============================================================
-- ATTRIBUTE DEFINITIONS
-- ============================================================
--
-- CUSTOMER ATTRIBUTES
-- ============================================================
--

INSERT INTO core_mdm.attribute_definitions
(
    attribute_definition_id,

    tenant_id,

    entity_type_id,

    attribute_name,

    display_name,

    data_type,

    required,

    searchable,

    filterable,

    sortable,

    vector_enabled,

    pii,

    metadata,

    created_at,

    updated_at
)
VALUES

--
-- CUSTOMER NAME
--

(
    '20000000-0000-0000-0000-000000000001',

    '00000000-0000-0000-0000-000000000001',

    '10000000-0000-0000-0000-000000000001',

    'full_name',

    'Full Name',

    'string',

    TRUE,

    TRUE,

    TRUE,

    TRUE,

    TRUE,

    TRUE,

    jsonb_build_object(

        'matching_weight', 0.95,

        'survivorship_priority', 100,

        'embedding_enabled', true
    ),

    NOW(),

    NOW()
),

--
-- EMAIL
--

(
    '20000000-0000-0000-0000-000000000002',

    '00000000-0000-0000-0000-000000000001',

    '10000000-0000-0000-0000-000000000001',

    'email',

    'Email Address',

    'string',

    FALSE,

    TRUE,

    TRUE,

    FALSE,

    TRUE,

    TRUE,

    jsonb_build_object(

        'matching_weight', 0.99,

        'unique_candidate', true,

        'validation', 'email'
    ),

    NOW(),

    NOW()
),

--
-- PHONE
--

(
    '20000000-0000-0000-0000-000000000003',

    '00000000-0000-0000-0000-000000000001',

    '10000000-0000-0000-0000-000000000001',

    'phone_number',

    'Phone Number',

    'string',

    FALSE,

    TRUE,

    TRUE,

    FALSE,

    FALSE,

    TRUE,

    jsonb_build_object(

        'matching_weight', 0.90,

        'validation', 'phone'
    ),

    NOW(),

    NOW()
),

--
-- DATE OF BIRTH
--

(
    '20000000-0000-0000-0000-000000000004',

    '00000000-0000-0000-0000-000000000001',

    '10000000-0000-0000-0000-000000000001',

    'date_of_birth',

    'Date Of Birth',

    'date',

    FALSE,

    FALSE,

    TRUE,

    TRUE,

    FALSE,

    TRUE,

    jsonb_build_object(

        'matching_weight', 0.85
    ),

    NOW(),

    NOW()
),

--
-- ORGANIZATION NAME
--

(
    '20000000-0000-0000-0000-000000000005',

    '00000000-0000-0000-0000-000000000001',

    '10000000-0000-0000-0000-000000000002',

    'organization_name',

    'Organization Name',

    'string',

    TRUE,

    TRUE,

    TRUE,

    TRUE,

    TRUE,

    FALSE,

    jsonb_build_object(

        'matching_weight', 0.98,

        'embedding_enabled', true
    ),

    NOW(),

    NOW()
),

--
-- PRODUCT NAME
--

(
    '20000000-0000-0000-0000-000000000006',

    '00000000-0000-0000-0000-000000000001',

    '10000000-0000-0000-0000-000000000003',

    'product_name',

    'Product Name',

    'string',

    TRUE,

    TRUE,

    TRUE,

    TRUE,

    TRUE,

    FALSE,

    jsonb_build_object(

        'matching_weight', 0.92
    ),

    NOW(),

    NOW()
),

--
-- PRODUCT SKU
--

(
    '20000000-0000-0000-0000-000000000007',

    '00000000-0000-0000-0000-000000000001',

    '10000000-0000-0000-0000-000000000003',

    'sku',

    'SKU',

    'string',

    TRUE,

    TRUE,

    TRUE,

    TRUE,

    FALSE,

    FALSE,

    jsonb_build_object(

        'matching_weight', 1.0,

        'unique_candidate', true
    ),

    NOW(),

    NOW()
)

ON CONFLICT (attribute_definition_id)
DO NOTHING;

--
-- ============================================================
-- DEFAULT SURVIVORSHIP RULES
-- ============================================================
--

INSERT INTO core_mdm.survivorship_rules
(
    rule_id,

    tenant_id,

    rule_name,

    description,

    attribute_name,

    strategy,

    scope,

    source_priority,

    source_weights,

    minimum_confidence,

    ai_assisted,

    explainability_enabled,

    allow_manual_override,

    status,

    priority,

    metadata,

    created_at,

    updated_at
)
VALUES
(
    '30000000-0000-0000-0000-000000000001',

    '00000000-0000-0000-0000-000000000001',

    'Customer Email Survivorship',

    'Prefer highest confidence verified email',

    'email',

    'HighestConfidence',

    'Global',

    '["crm","erp","support"]'::JSONB,

    '{"crm":0.95,"erp":0.85,"support":0.70}'::JSONB,

    0.75,

    TRUE,

    TRUE,

    TRUE,

    'Active',

    100,

    jsonb_build_object(

        'system_rule', true
    ),

    NOW(),

    NOW()
),

(
    '30000000-0000-0000-0000-000000000002',

    '00000000-0000-0000-0000-000000000001',

    'Customer Name Survivorship',

    'Use AI-enhanced survivorship for names',

    'full_name',

    'AIRecommended',

    'Global',

    '["crm","marketing","support"]'::JSONB,

    '{"crm":0.9,"marketing":0.7,"support":0.5}'::JSONB,

    0.70,

    TRUE,

    TRUE,

    TRUE,

    'Active',

    90,

    jsonb_build_object(

        'system_rule', true
    ),

    NOW(),

    NOW()
)

ON CONFLICT (rule_id)
DO NOTHING;

--
-- ============================================================
-- VALIDATION
-- ============================================================
--

DO
$$
DECLARE

    v_entity_types BIGINT;

    v_attributes BIGINT;

BEGIN

    SELECT COUNT(*)
    INTO v_entity_types
    FROM core_mdm.entity_types;

    SELECT COUNT(*)
    INTO v_attributes
    FROM core_mdm.attribute_definitions;

    IF v_entity_types = 0 THEN

        RAISE EXCEPTION
        'Entity type seeding failed';

    END IF;

    IF v_attributes = 0 THEN

        RAISE EXCEPTION
        'Attribute definition seeding failed';

    END IF;

END;
$$;

COMMIT;

--
-- ============================================================
-- COMMENTS
-- ============================================================
--

COMMENT ON TABLE core_mdm.entity_types
IS 'Seeded system entity models';

COMMENT ON TABLE core_mdm.attribute_definitions
IS 'Seeded enterprise attribute definitions';

COMMENT ON TABLE core_mdm.survivorship_rules
IS 'Default survivorship rules for system entities';