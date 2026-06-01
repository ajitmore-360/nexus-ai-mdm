--
-- =========================================================
-- Nexus MDM Platform
-- Production Role Initialization
-- File: 003_roles.sql
-- =========================================================
--

BEGIN;

--
-- =========================================================
-- APPLICATION ROLE
-- =========================================================
--

DO
$$
BEGIN

    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'nexus_app'
    ) THEN

        CREATE ROLE nexus_app
        LOGIN
        NOSUPERUSER
        NOCREATEDB
        NOCREATEROLE
        NOREPLICATION
        INHERIT;

    END IF;

END
$$;

--
-- =========================================================
-- READONLY ROLE
-- =========================================================
--

DO
$$
BEGIN

    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'nexus_readonly'
    ) THEN

        CREATE ROLE nexus_readonly
        LOGIN
        NOSUPERUSER
        NOCREATEDB
        NOCREATEROLE
        NOREPLICATION
        INHERIT;

    END IF;

END
$$;

--
-- =========================================================
-- MIGRATION ROLE
-- =========================================================
--

DO
$$
BEGIN

    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'nexus_migration'
    ) THEN

        CREATE ROLE nexus_migration
        LOGIN
        NOSUPERUSER
        CREATEDB
        CREATEROLE
        NOREPLICATION
        INHERIT;

    END IF;

END
$$;

--
-- =========================================================
-- SECURITY SETTINGS
-- =========================================================
--

ALTER ROLE nexus_app
SET row_security = on;

ALTER ROLE nexus_app
SET default_transaction_isolation = 'read committed';

ALTER ROLE nexus_readonly
SET default_transaction_read_only = on;

ALTER ROLE nexus_app
SET idle_in_transaction_session_timeout = '5min';

ALTER ROLE nexus_readonly
SET idle_in_transaction_session_timeout = '5min';

ALTER ROLE nexus_migration
SET lock_timeout = '30s';

ALTER ROLE nexus_migration
SET statement_timeout = '30min';

--
-- =========================================================
-- QUERY IDENTIFICATION
-- =========================================================
--

ALTER ROLE nexus_app
SET application_name = 'nexus-mdm-app';

ALTER ROLE nexus_readonly
SET application_name = 'nexus-mdm-readonly';

ALTER ROLE nexus_migration
SET application_name = 'nexus-mdm-migrations';

--
-- =========================================================
-- DATABASE CONNECT
-- =========================================================
--

GRANT CONNECT ON DATABASE postgres TO nexus_app;
GRANT CONNECT ON DATABASE postgres TO nexus_readonly;
GRANT CONNECT ON DATABASE postgres TO nexus_migration;

--
-- =========================================================
-- DEFAULT TABLE PRIVILEGES
-- =========================================================
--

ALTER DEFAULT PRIVILEGES
FOR ROLE nexus_migration
IN SCHEMA core_mdm
GRANT
    SELECT,
    INSERT,
    UPDATE,
    DELETE
ON TABLES
TO nexus_app;

ALTER DEFAULT PRIVILEGES
FOR ROLE nexus_migration
IN SCHEMA event_store
GRANT
    SELECT,
    INSERT,
    UPDATE
ON TABLES
TO nexus_app;

ALTER DEFAULT PRIVILEGES
FOR ROLE nexus_migration
IN SCHEMA audit
GRANT
    SELECT,
    INSERT
ON TABLES
TO nexus_app;

ALTER DEFAULT PRIVILEGES
FOR ROLE nexus_migration
IN SCHEMA ai
GRANT
    SELECT,
    INSERT,
    UPDATE,
    DELETE
ON TABLES
TO nexus_app;

--
-- =========================================================
-- READONLY PRIVILEGES
-- =========================================================
--

ALTER DEFAULT PRIVILEGES
FOR ROLE nexus_migration
IN SCHEMA core_mdm
GRANT SELECT
ON TABLES
TO nexus_readonly;

ALTER DEFAULT PRIVILEGES
FOR ROLE nexus_migration
IN SCHEMA audit
GRANT SELECT
ON TABLES
TO nexus_readonly;

ALTER DEFAULT PRIVILEGES
FOR ROLE nexus_migration
IN SCHEMA lineage
GRANT SELECT
ON TABLES
TO nexus_readonly;

--
-- =========================================================
-- SEQUENCE PRIVILEGES
-- =========================================================
--

ALTER DEFAULT PRIVILEGES
FOR ROLE nexus_migration
IN SCHEMA core_mdm
GRANT
    USAGE,
    SELECT
ON SEQUENCES
TO nexus_app;

ALTER DEFAULT PRIVILEGES
FOR ROLE nexus_migration
IN SCHEMA ai
GRANT
    USAGE,
    SELECT
ON SEQUENCES
TO nexus_app;

--
-- =========================================================
-- FUNCTION PRIVILEGES
-- =========================================================
--

ALTER DEFAULT PRIVILEGES
FOR ROLE nexus_migration
IN SCHEMA app_context
GRANT EXECUTE
ON FUNCTIONS
TO nexus_app;

ALTER DEFAULT PRIVILEGES
FOR ROLE nexus_migration
IN SCHEMA event_store
GRANT EXECUTE
ON FUNCTIONS
TO nexus_app;

--
-- =========================================================
-- PREVENT PUBLIC LEAKAGE
-- =========================================================
--

ALTER DEFAULT PRIVILEGES
FOR ROLE nexus_migration
REVOKE ALL
ON TABLES
FROM PUBLIC;

ALTER DEFAULT PRIVILEGES
FOR ROLE nexus_migration
REVOKE ALL
ON SEQUENCES
FROM PUBLIC;

ALTER DEFAULT PRIVILEGES
FOR ROLE nexus_migration
REVOKE ALL
ON FUNCTIONS
FROM PUBLIC;

--
-- =========================================================
-- ROLE COMMENTS
-- =========================================================
--

COMMENT ON ROLE nexus_app
IS 'Primary runtime role for Nexus MDM platform';

COMMENT ON ROLE nexus_readonly
IS 'Read-only analytics and BI role';

COMMENT ON ROLE nexus_migration
IS 'Schema migration and DDL management role';

COMMIT;