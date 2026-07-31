-- =============================================================================
-- Migration 0032: Materialized views for golden records per entity type
--
-- These views extract the most-queried attributes from golden_records.current_attributes
-- (JSONB, added by migration 0027) into typed, B-tree-indexed columns per entity
-- type, making UI grid queries, reports, and exports hit a narrow typed table.
--
-- Created WITH NO DATA so migration succeeds on a fresh database (no golden
-- records yet). The survivorship engine refreshes them after each write;
-- a nightly pg_cron sweep is a safety net against drift.
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
    gr.current_attributes->>'full_name'        AS full_name,
    gr.current_attributes->>'first_name'       AS first_name,
    gr.current_attributes->>'last_name'        AS last_name,
    gr.current_attributes->>'email'            AS email,
    gr.current_attributes->>'phone'            AS phone,
    gr.current_attributes->>'company'          AS company,
    gr.current_attributes->>'company_name'     AS company_name,
    gr.current_attributes->>'tax_id'           AS tax_id,
    gr.current_attributes->>'customer_id'      AS customer_id,
    gr.current_attributes->>'address'          AS address,
    gr.current_attributes->>'city'             AS city,
    gr.current_attributes->>'state'            AS state,
    gr.current_attributes->>'country'          AS country,
    gr.current_attributes->>'postal_code'      AS postal_code,
    gr.current_attributes->>'date_of_birth'    AS date_of_birth,
    gr.current_attributes->>'customer_segment' AS customer_segment
FROM core_mdm.golden_records gr
WHERE gr.entity_type = 'Customer'
  AND gr.valid_to    = 'infinity'
WITH NO DATA;

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
    gr.current_attributes->>'name'          AS name,
    gr.current_attributes->>'legal_name'    AS legal_name,
    gr.current_attributes->>'vendor_id'     AS vendor_id,
    gr.current_attributes->>'tax_id'        AS tax_id,
    gr.current_attributes->>'email'         AS email,
    gr.current_attributes->>'phone'         AS phone,
    gr.current_attributes->>'website'       AS website,
    gr.current_attributes->>'country'       AS country,
    gr.current_attributes->>'city'          AS city,
    gr.current_attributes->>'payment_terms' AS payment_terms,
    gr.current_attributes->>'category'      AS category
FROM core_mdm.golden_records gr
WHERE gr.entity_type = 'Vendor'
  AND gr.valid_to    = 'infinity'
WITH NO DATA;

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
    gr.current_attributes->>'material_code'        AS material_code,
    gr.current_attributes->>'description'          AS description,
    gr.current_attributes->>'short_text'           AS short_text,
    gr.current_attributes->>'material_group'       AS material_group,
    gr.current_attributes->>'unit_of_measure'      AS unit_of_measure,
    gr.current_attributes->>'weight'               AS weight,
    gr.current_attributes->>'weight_unit'          AS weight_unit,
    gr.current_attributes->>'length'               AS length,
    gr.current_attributes->>'width'                AS width,
    gr.current_attributes->>'height'               AS height,
    gr.current_attributes->>'hsn_code'             AS hsn_code,
    gr.current_attributes->>'gtin'                 AS gtin,
    gr.current_attributes->>'manufacturer'         AS manufacturer,
    gr.current_attributes->>'manufacturer_part_no' AS manufacturer_part_no,
    gr.current_attributes->>'storage_conditions'   AS storage_conditions,
    gr.current_attributes->>'hazard_class'         AS hazard_class
FROM core_mdm.golden_records gr
WHERE gr.entity_type = 'Material'
  AND gr.valid_to    = 'infinity'
WITH NO DATA;

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
