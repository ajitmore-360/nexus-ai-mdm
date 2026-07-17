-- =============================================================================
-- Migration 002031: Materialized views for golden records per entity type
--
-- These views pivot the EAV golden_record_attributes rows into typed, B-tree-
-- indexed columns per entity type, making UI grid queries, reports, and exports
-- hit a narrow typed table rather than the full 113M-row EAV table.
--
-- REFRESH MATERIALIZED VIEW CONCURRENTLY is called by the survivorship engine
-- after each golden record creation/update (non-blocking, uses a unique index).
-- A nightly pg_cron full-refresh runs as a safety net against any drift.
--
-- Requires migration 002028 (golden_records.current_attributes) to have run.
-- =============================================================================

-- ── Customer golden view ──────────────────────────────────────────────────────
CREATE MATERIALIZED VIEW IF NOT EXISTS core_mdm.golden_customers AS
SELECT
    gr.golden_record_id,
    gr.tenant_id,
    gr.entity_type,
    gr.status,
    gr.trust_score,
    gr.quality_score,
    gr.completeness,
    gr.source_entities,
    gr.valid_from,
    gr.valid_to,
    gr.updated_at,
    gr.current_attributes,
    MAX(CASE WHEN ga.attribute_key = 'full_name'        THEN ga.attribute_value_text END) AS full_name,
    MAX(CASE WHEN ga.attribute_key = 'first_name'       THEN ga.attribute_value_text END) AS first_name,
    MAX(CASE WHEN ga.attribute_key = 'last_name'        THEN ga.attribute_value_text END) AS last_name,
    MAX(CASE WHEN ga.attribute_key = 'email'            THEN ga.attribute_value_text END) AS email,
    MAX(CASE WHEN ga.attribute_key = 'phone'            THEN ga.attribute_value_text END) AS phone,
    MAX(CASE WHEN ga.attribute_key = 'company'          THEN ga.attribute_value_text END) AS company,
    MAX(CASE WHEN ga.attribute_key = 'company_name'     THEN ga.attribute_value_text END) AS company_name,
    MAX(CASE WHEN ga.attribute_key = 'tax_id'           THEN ga.attribute_value_text END) AS tax_id,
    MAX(CASE WHEN ga.attribute_key = 'customer_id'      THEN ga.attribute_value_text END) AS customer_id,
    MAX(CASE WHEN ga.attribute_key = 'address'          THEN ga.attribute_value_text END) AS address,
    MAX(CASE WHEN ga.attribute_key = 'city'             THEN ga.attribute_value_text END) AS city,
    MAX(CASE WHEN ga.attribute_key = 'state'            THEN ga.attribute_value_text END) AS state,
    MAX(CASE WHEN ga.attribute_key = 'country'          THEN ga.attribute_value_text END) AS country,
    MAX(CASE WHEN ga.attribute_key = 'postal_code'      THEN ga.attribute_value_text END) AS postal_code,
    MAX(CASE WHEN ga.attribute_key = 'date_of_birth'    THEN ga.attribute_value_text END) AS date_of_birth,
    MAX(CASE WHEN ga.attribute_key = 'customer_segment' THEN ga.attribute_value_text END) AS customer_segment
FROM core_mdm.golden_records gr
LEFT JOIN core_mdm.golden_record_attributes ga
       ON ga.golden_record_id = gr.golden_record_id
      AND ga.is_current       = TRUE
WHERE gr.entity_type = 'Customer'
  AND gr.valid_to    = 'infinity'
GROUP BY gr.golden_record_id, gr.tenant_id, gr.entity_type, gr.status,
         gr.trust_score, gr.quality_score, gr.completeness, gr.source_entities,
         gr.valid_from, gr.valid_to, gr.updated_at, gr.current_attributes
WITH DATA;

CREATE UNIQUE INDEX IF NOT EXISTS idx_gc_pk
    ON core_mdm.golden_customers (golden_record_id);
CREATE INDEX IF NOT EXISTS idx_gc_tenant_score
    ON core_mdm.golden_customers (tenant_id, status, trust_score DESC);
CREATE INDEX IF NOT EXISTS idx_gc_email
    ON core_mdm.golden_customers (tenant_id, lower(email))
    WHERE email IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_gc_name_fts
    ON core_mdm.golden_customers
    USING GIN (to_tsvector('english',
        coalesce(full_name,'') || ' ' ||
        coalesce(company,'') || ' ' ||
        coalesce(email,'')));

-- ── Vendor golden view ────────────────────────────────────────────────────────
CREATE MATERIALIZED VIEW IF NOT EXISTS core_mdm.golden_vendors AS
SELECT
    gr.golden_record_id,
    gr.tenant_id,
    gr.entity_type,
    gr.status,
    gr.trust_score,
    gr.quality_score,
    gr.completeness,
    gr.source_entities,
    gr.valid_from,
    gr.valid_to,
    gr.updated_at,
    gr.current_attributes,
    MAX(CASE WHEN ga.attribute_key = 'name'           THEN ga.attribute_value_text END) AS name,
    MAX(CASE WHEN ga.attribute_key = 'legal_name'     THEN ga.attribute_value_text END) AS legal_name,
    MAX(CASE WHEN ga.attribute_key = 'vendor_id'      THEN ga.attribute_value_text END) AS vendor_id,
    MAX(CASE WHEN ga.attribute_key = 'tax_id'         THEN ga.attribute_value_text END) AS tax_id,
    MAX(CASE WHEN ga.attribute_key = 'email'          THEN ga.attribute_value_text END) AS email,
    MAX(CASE WHEN ga.attribute_key = 'phone'          THEN ga.attribute_value_text END) AS phone,
    MAX(CASE WHEN ga.attribute_key = 'website'        THEN ga.attribute_value_text END) AS website,
    MAX(CASE WHEN ga.attribute_key = 'country'        THEN ga.attribute_value_text END) AS country,
    MAX(CASE WHEN ga.attribute_key = 'city'           THEN ga.attribute_value_text END) AS city,
    MAX(CASE WHEN ga.attribute_key = 'payment_terms'  THEN ga.attribute_value_text END) AS payment_terms,
    MAX(CASE WHEN ga.attribute_key = 'category'       THEN ga.attribute_value_text END) AS category
FROM core_mdm.golden_records gr
LEFT JOIN core_mdm.golden_record_attributes ga
       ON ga.golden_record_id = gr.golden_record_id
      AND ga.is_current       = TRUE
WHERE gr.entity_type = 'Vendor'
  AND gr.valid_to    = 'infinity'
GROUP BY gr.golden_record_id, gr.tenant_id, gr.entity_type, gr.status,
         gr.trust_score, gr.quality_score, gr.completeness, gr.source_entities,
         gr.valid_from, gr.valid_to, gr.updated_at, gr.current_attributes
WITH DATA;

CREATE UNIQUE INDEX IF NOT EXISTS idx_gv_pk
    ON core_mdm.golden_vendors (golden_record_id);
CREATE INDEX IF NOT EXISTS idx_gv_tenant_score
    ON core_mdm.golden_vendors (tenant_id, status, trust_score DESC);
CREATE INDEX IF NOT EXISTS idx_gv_name_fts
    ON core_mdm.golden_vendors
    USING GIN (to_tsvector('english',
        coalesce(name,'') || ' ' || coalesce(legal_name,'')));

-- ── Material golden view ──────────────────────────────────────────────────────
CREATE MATERIALIZED VIEW IF NOT EXISTS core_mdm.golden_materials AS
SELECT
    gr.golden_record_id,
    gr.tenant_id,
    gr.entity_type,
    gr.status,
    gr.trust_score,
    gr.quality_score,
    gr.completeness,
    gr.source_entities,
    gr.valid_from,
    gr.valid_to,
    gr.updated_at,
    gr.current_attributes,
    MAX(CASE WHEN ga.attribute_key = 'material_code'        THEN ga.attribute_value_text END) AS material_code,
    MAX(CASE WHEN ga.attribute_key = 'description'          THEN ga.attribute_value_text END) AS description,
    MAX(CASE WHEN ga.attribute_key = 'short_text'           THEN ga.attribute_value_text END) AS short_text,
    MAX(CASE WHEN ga.attribute_key = 'material_group'       THEN ga.attribute_value_text END) AS material_group,
    MAX(CASE WHEN ga.attribute_key = 'unit_of_measure'      THEN ga.attribute_value_text END) AS unit_of_measure,
    MAX(CASE WHEN ga.attribute_key = 'weight'               THEN ga.attribute_value_text END) AS weight,
    MAX(CASE WHEN ga.attribute_key = 'weight_unit'          THEN ga.attribute_value_text END) AS weight_unit,
    MAX(CASE WHEN ga.attribute_key = 'length'               THEN ga.attribute_value_text END) AS length,
    MAX(CASE WHEN ga.attribute_key = 'width'                THEN ga.attribute_value_text END) AS width,
    MAX(CASE WHEN ga.attribute_key = 'height'               THEN ga.attribute_value_text END) AS height,
    MAX(CASE WHEN ga.attribute_key = 'hsn_code'             THEN ga.attribute_value_text END) AS hsn_code,
    MAX(CASE WHEN ga.attribute_key = 'gtin'                 THEN ga.attribute_value_text END) AS gtin,
    MAX(CASE WHEN ga.attribute_key = 'manufacturer'         THEN ga.attribute_value_text END) AS manufacturer,
    MAX(CASE WHEN ga.attribute_key = 'manufacturer_part_no' THEN ga.attribute_value_text END) AS manufacturer_part_no,
    MAX(CASE WHEN ga.attribute_key = 'storage_conditions'   THEN ga.attribute_value_text END) AS storage_conditions,
    MAX(CASE WHEN ga.attribute_key = 'hazard_class'         THEN ga.attribute_value_text END) AS hazard_class
FROM core_mdm.golden_records gr
LEFT JOIN core_mdm.golden_record_attributes ga
       ON ga.golden_record_id = gr.golden_record_id
      AND ga.is_current       = TRUE
WHERE gr.entity_type = 'Material'
  AND gr.valid_to    = 'infinity'
GROUP BY gr.golden_record_id, gr.tenant_id, gr.entity_type, gr.status,
         gr.trust_score, gr.quality_score, gr.completeness, gr.source_entities,
         gr.valid_from, gr.valid_to, gr.updated_at, gr.current_attributes
WITH DATA;

CREATE UNIQUE INDEX IF NOT EXISTS idx_gm_pk
    ON core_mdm.golden_materials (golden_record_id);
CREATE INDEX IF NOT EXISTS idx_gm_tenant_score
    ON core_mdm.golden_materials (tenant_id, status, trust_score DESC);
CREATE INDEX IF NOT EXISTS idx_gm_code
    ON core_mdm.golden_materials (tenant_id, material_code)
    WHERE material_code IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_gm_desc_fts
    ON core_mdm.golden_materials
    USING GIN (to_tsvector('english',
        coalesce(material_code,'') || ' ' ||
        coalesce(description,'') || ' ' ||
        coalesce(manufacturer,'')));

-- ── Nightly refresh via pg_cron (safety net — survivorship engine refreshes on write) ──
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        PERFORM cron.unschedule('nexus-golden-views-refresh')
        FROM cron.job WHERE jobname = 'nexus-golden-views-refresh';

        PERFORM cron.schedule(
            'nexus-golden-views-refresh',
            '30 1 * * *',
            $$
            REFRESH MATERIALIZED VIEW CONCURRENTLY core_mdm.golden_customers;
            REFRESH MATERIALIZED VIEW CONCURRENTLY core_mdm.golden_vendors;
            REFRESH MATERIALIZED VIEW CONCURRENTLY core_mdm.golden_materials;
            $$
        );
    END IF;
END $$;
