-- =========================================================
-- Nexus MDM Platform
-- Enterprise Role Initialization
-- =========================================================
DO
$$
BEGIN
    -- =====================================================
    -- APPLICATION ROLE
    -- =====================================================
    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'nexus_app'
    ) THEN
        CREATE ROLE nexus_app
        LOGIN
        PASSWORD 'CHANGE_ME_IN_PRODUCTION'
        NOSUPERUSER
        NOCREATEDB
        NOCREATEROLE
        NOREPLICATION;
    END IF;
    -- =====================================================
    -- READONLY ANALYTICS ROLE
    -- =====================================================
    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'nexus_readonly'
    ) THEN
        CREATE ROLE nexus_readonly
        LOGIN
        PASSWORD 'CHANGE_ME_IN_PRODUCTION'
        NOSUPERUSER
        NOCREATEDB
        NOCREATEROLE
        NOREPLICATION;
    END IF;
    -- =====================================================
    -- MIGRATION ROLE
    -- =====================================================
    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'nexus_migration'
    ) THEN
        CREATE ROLE nexus_migration
        LOGIN
        PASSWORD 'CHANGE_ME_IN_PRODUCTION'
        NOSUPERUSER
        CREATEDB
        CREATEROLE
        NOREPLICATION;
    END IF;
END
$$;
-- =========================================================
-- SCHEMA ACCESS
-- =========================================================

GRANT USAGE ON SCHEMA mdm TO nexus_app;
GRANT USAGE ON SCHEMA matching TO nexus_app;
GRANT USAGE ON SCHEMA survivorship TO nexus_app;
GRANT USAGE ON SCHEMA lineage TO nexus_app;
GRANT USAGE ON SCHEMA workflow TO nexus_app;
GRANT USAGE ON SCHEMA policy TO nexus_app;
GRANT USAGE ON SCHEMA semantic TO nexus_app;
GRANT USAGE ON SCHEMA audit TO nexus_app;
GRANT USAGE ON SCHEMA analytics TO nexus_app;
GRANT USAGE ON SCHEMA event_store TO nexus_app;
GRANT USAGE ON SCHEMA app_context TO nexus_app;
GRANT USAGE ON SCHEMA staging TO nexus_app;
GRANT USAGE ON SCHEMA reference TO nexus_app;
GRANT USAGE ON SCHEMA graph TO nexus_app;
-- =========================================================
-- READONLY ROLE ACCESS
-- =========================================================
GRANT USAGE ON SCHEMA analytics TO nexus_readonly;
GRANT USAGE ON SCHEMA mdm TO nexus_readonly;
-- =========================================================
-- FUTURE TABLE ACCESS
-- =========================================================
ALTER DEFAULT PRIVILEGES
IN SCHEMA mdm
GRANT SELECT, INSERT, UPDATE, DELETE
ON TABLES
TO nexus_app;
ALTER DEFAULT PRIVILEGES
IN SCHEMA event_store
GRANT SELECT, INSERT, UPDATE
ON TABLES
TO nexus_app;

ALTER DEFAULT PRIVILEGES
IN SCHEMA analytics
GRANT SELECT
ON TABLES
TO nexus_readonly;

-- =========================================================
-- SEQUENCE ACCESS
-- =========================================================

ALTER DEFAULT PRIVILEGES
IN SCHEMA mdm
GRANT USAGE, SELECT
ON SEQUENCES
TO nexus_app;

-- =========================================================
-- RLS SAFETY
-- =========================================================

ALTER ROLE nexus_app
SET row_security = on;

-- =========================================================
-- QUERY TAGGING
-- =========================================================

ALTER ROLE nexus_app
SET application_name = 'nexus-mdm-app';

ALTER ROLE nexus_readonly
SET application_name = 'nexus-mdm-readonly';

-- =========================================================
-- SECURITY COMMENTS
-- =========================================================

COMMENT ON ROLE nexus_app IS
'Primary Nexus MDM application runtime role';

COMMENT ON ROLE nexus_readonly IS
'Read-only analytics and BI role';

COMMENT ON ROLE nexus_migration IS
'Database migration and schema management role';
