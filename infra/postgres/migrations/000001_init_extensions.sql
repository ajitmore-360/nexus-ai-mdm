-- =========================================================
-- Azile MDM Platform
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
        WHERE rolname = 'azile_app'
    ) THEN
        CREATE ROLE azile_app
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
        WHERE rolname = 'azile_readonly'
    ) THEN
        CREATE ROLE azile_readonly
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
        WHERE rolname = 'azile_migration'
    ) THEN
        CREATE ROLE azile_migration
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

GRANT USAGE ON SCHEMA mdm TO azile_app;
GRANT USAGE ON SCHEMA matching TO azile_app;
GRANT USAGE ON SCHEMA survivorship TO azile_app;
GRANT USAGE ON SCHEMA lineage TO azile_app;
GRANT USAGE ON SCHEMA workflow TO azile_app;
GRANT USAGE ON SCHEMA policy TO azile_app;
GRANT USAGE ON SCHEMA semantic TO azile_app;
GRANT USAGE ON SCHEMA audit TO azile_app;
GRANT USAGE ON SCHEMA analytics TO azile_app;
GRANT USAGE ON SCHEMA event_store TO azile_app;
GRANT USAGE ON SCHEMA app_context TO azile_app;
GRANT USAGE ON SCHEMA staging TO azile_app;
GRANT USAGE ON SCHEMA reference TO azile_app;
GRANT USAGE ON SCHEMA graph TO azile_app;
-- =========================================================
-- READONLY ROLE ACCESS
-- =========================================================
GRANT USAGE ON SCHEMA analytics TO azile_readonly;
GRANT USAGE ON SCHEMA mdm TO azile_readonly;
-- =========================================================
-- FUTURE TABLE ACCESS
-- =========================================================
ALTER DEFAULT PRIVILEGES
IN SCHEMA mdm
GRANT SELECT, INSERT, UPDATE, DELETE
ON TABLES
TO azile_app;
ALTER DEFAULT PRIVILEGES
IN SCHEMA event_store
GRANT SELECT, INSERT, UPDATE
ON TABLES
TO azile_app;

ALTER DEFAULT PRIVILEGES
IN SCHEMA analytics
GRANT SELECT
ON TABLES
TO azile_readonly;

-- =========================================================
-- SEQUENCE ACCESS
-- =========================================================

ALTER DEFAULT PRIVILEGES
IN SCHEMA mdm
GRANT USAGE, SELECT
ON SEQUENCES
TO azile_app;

-- =========================================================
-- RLS SAFETY
-- =========================================================

ALTER ROLE azile_app
SET row_security = on;

-- =========================================================
-- QUERY TAGGING
-- =========================================================

ALTER ROLE azile_app
SET application_name = 'azile-mdm-app';

ALTER ROLE azile_readonly
SET application_name = 'azile-mdm-readonly';

-- =========================================================
-- SECURITY COMMENTS
-- =========================================================

COMMENT ON ROLE azile_app IS
'Primary Azile MDM application runtime role';

COMMENT ON ROLE azile_readonly IS
'Read-only analytics and BI role';

COMMENT ON ROLE azile_migration IS
'Database migration and schema management role';
