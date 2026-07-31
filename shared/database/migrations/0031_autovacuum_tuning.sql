-- =============================================================================
-- Migration 002030: Autovacuum tuning for high-churn large tables
--
-- Default autovacuum fires when 20% of rows are dead (scale_factor = 0.20).
-- At 385M attribute rows that's 77M dead rows before vacuum runs — causing
-- severe table bloat and degraded query plans.
--
-- Reducing to 1-2% fires vacuum much more often, keeping bloat under control
-- at the cost of slightly more background I/O (acceptable at scale).
--
-- These settings are per-table overrides; global postgresql.conf is unchanged.
-- =============================================================================

-- entity_attributes parent + all partitions (highest write churn)
ALTER TABLE core_mdm.entity_attributes SET (
    autovacuum_vacuum_scale_factor   = 0.01,
    autovacuum_analyze_scale_factor  = 0.005,
    autovacuum_vacuum_cost_delay     = 2,
    autovacuum_vacuum_threshold      = 1000
);

DO $$
DECLARE
    tbl TEXT;
BEGIN
    FOREACH tbl IN ARRAY ARRAY[
        'entity_attributes_customer',
        'entity_attributes_vendor',
        'entity_attributes_material',
        'entity_attributes_product',
        'entity_attributes_employee',
        'entity_attributes_account',
        'entity_attributes_location',
        'entity_attributes_organization',
        'entity_attributes_asset',
        'entity_attributes_refdata',
        'entity_attributes_other'
    ] LOOP
        IF EXISTS (
            SELECT 1 FROM pg_tables
            WHERE schemaname = 'core_mdm' AND tablename = tbl
        ) THEN
            EXECUTE format(
                'ALTER TABLE core_mdm.%I SET (
                    autovacuum_vacuum_scale_factor  = 0.01,
                    autovacuum_analyze_scale_factor = 0.005
                )',
                tbl
            );
        END IF;
    END LOOP;
END $$;

-- entities: updated on every re-ingest + trust_score / status changes
ALTER TABLE core_mdm.entities SET (
    autovacuum_vacuum_scale_factor   = 0.02,
    autovacuum_analyze_scale_factor  = 0.01,
    autovacuum_vacuum_threshold      = 500
);

-- golden_record_attributes: lower write rate but large (113M rows at scale)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'core_mdm' AND tablename = 'golden_record_attributes') THEN
        ALTER TABLE core_mdm.golden_record_attributes SET (
            autovacuum_vacuum_scale_factor   = 0.02,
            autovacuum_analyze_scale_factor  = 0.01
        );
    END IF;
END $$;

-- outbox_events: insert + publish on every entity write (very high churn)
ALTER TABLE event_store.outbox_events SET (
    autovacuum_vacuum_scale_factor   = 0.01,
    autovacuum_analyze_scale_factor  = 0.005,
    autovacuum_vacuum_threshold      = 1000
);

-- audit.audit_log: append-only but enormous volume
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_tables WHERE schemaname = 'audit' AND tablename = 'audit_log'
    ) THEN
        ALTER TABLE audit.audit_log SET (
            autovacuum_vacuum_scale_factor   = 0.05,
            autovacuum_analyze_scale_factor  = 0.02
        );
    END IF;
END $$;

-- match_candidates: high insert rate during matching runs
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_tables WHERE schemaname = 'core_mdm' AND tablename = 'match_candidates'
    ) THEN
        ALTER TABLE core_mdm.match_candidates SET (
            autovacuum_vacuum_scale_factor   = 0.02,
            autovacuum_analyze_scale_factor  = 0.01
        );
    END IF;
END $$;

-- field_match_results: highest insert rate (N fields × M candidates per entity)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_tables WHERE schemaname = 'core_mdm' AND tablename = 'field_match_results'
    ) THEN
        ALTER TABLE core_mdm.field_match_results SET (
            autovacuum_vacuum_scale_factor   = 0.01,
            autovacuum_analyze_scale_factor  = 0.005
        );
    END IF;
END $$;

-- ingest_jobs: status transitions on every job step
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_tables WHERE schemaname = 'ingest' AND tablename = 'ingest_jobs'
    ) THEN
        ALTER TABLE ingest.ingest_jobs SET (
            autovacuum_vacuum_scale_factor   = 0.05,
            autovacuum_analyze_scale_factor  = 0.02
        );
    END IF;
END $$;
