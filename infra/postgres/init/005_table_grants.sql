--
-- =========================================================
-- Nexus MDM Platform
-- Table-level Grants
-- File: 004_table_grants.sql
--
-- Runs AFTER schema creation and role setup.
-- Grants explicit permissions on all tables to nexus_app
-- so that services connecting as nexus_app (or postgres in
-- dev mode) can perform DML without RLS issues.
-- =========================================================
--

BEGIN;

-- ─────────────────────────────────────────────────────────
-- GRANT ALL FUTURE TABLES (via ALTER DEFAULT PRIVILEGES)
-- is already in 002_roles.sql for nexus_migration.
--
-- But since SQLx migrations run as the POSTGRES superuser,
-- not as nexus_migration, we also need explicit grants on
-- tables that already exist when this script runs.
--
-- In practice, for LOCAL DEV, services connect as postgres
-- (superuser) so all permissions are bypassed. For STAGING/
-- PRODUCTION, uncomment the explicit grants below once
-- migrations have been run and tables exist.
-- ─────────────────────────────────────────────────────────

-- NOTE: This file intentionally runs last (004_) to allow
-- migration tables to be created first by the services on
-- startup. The explicit grants are applied via a DO block
-- that only acts if tables already exist.

DO
$$
BEGIN

    -- Grant on any core_mdm tables that already exist
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'core_mdm'
        LIMIT 1
    ) THEN
        EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE
                 ON ALL TABLES IN SCHEMA core_mdm
                 TO nexus_app';

        EXECUTE 'GRANT USAGE, SELECT
                 ON ALL SEQUENCES IN SCHEMA core_mdm
                 TO nexus_app';
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'event_store'
        LIMIT 1
    ) THEN
        EXECUTE 'GRANT SELECT, INSERT, UPDATE
                 ON ALL TABLES IN SCHEMA event_store
                 TO nexus_app';
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'ai'
        LIMIT 1
    ) THEN
        EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE
                 ON ALL TABLES IN SCHEMA ai
                 TO nexus_app';
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'governance'
        LIMIT 1
    ) THEN
        EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE
                 ON ALL TABLES IN SCHEMA governance
                 TO nexus_app';
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'platform'
        LIMIT 1
    ) THEN
        EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE
                 ON ALL TABLES IN SCHEMA platform
                 TO nexus_app';
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'audit'
        LIMIT 1
    ) THEN
        EXECUTE 'GRANT SELECT, INSERT
                 ON ALL TABLES IN SCHEMA audit
                 TO nexus_app';
    END IF;

END
$$;

COMMIT;
