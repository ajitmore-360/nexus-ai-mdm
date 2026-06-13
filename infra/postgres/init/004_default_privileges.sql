--
-- =========================================================
-- Nexus MDM Platform
-- Default Privileges (runs after schemas are created)
-- File: 004_default_privileges.sql
-- =========================================================
-- ALTER DEFAULT PRIVILEGES sets permissions that are
-- automatically applied to objects created by nexus_migration
-- in the future.  Must run after 003_schemas.sql.
-- =========================================================
--

BEGIN;

-- ── Application role: tables ──────────────────────────────────────────────

ALTER DEFAULT PRIVILEGES FOR ROLE nexus_migration IN SCHEMA core_mdm
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO nexus_app;

ALTER DEFAULT PRIVILEGES FOR ROLE nexus_migration IN SCHEMA event_store
    GRANT SELECT, INSERT, UPDATE ON TABLES TO nexus_app;

ALTER DEFAULT PRIVILEGES FOR ROLE nexus_migration IN SCHEMA audit
    GRANT SELECT, INSERT ON TABLES TO nexus_app;

ALTER DEFAULT PRIVILEGES FOR ROLE nexus_migration IN SCHEMA ai
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO nexus_app;

ALTER DEFAULT PRIVILEGES FOR ROLE nexus_migration IN SCHEMA governance
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO nexus_app;

ALTER DEFAULT PRIVILEGES FOR ROLE nexus_migration IN SCHEMA platform
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO nexus_app;

-- ── Read-only role: tables ────────────────────────────────────────────────

ALTER DEFAULT PRIVILEGES FOR ROLE nexus_migration IN SCHEMA core_mdm
    GRANT SELECT ON TABLES TO nexus_readonly;

ALTER DEFAULT PRIVILEGES FOR ROLE nexus_migration IN SCHEMA audit
    GRANT SELECT ON TABLES TO nexus_readonly;

ALTER DEFAULT PRIVILEGES FOR ROLE nexus_migration IN SCHEMA lineage
    GRANT SELECT ON TABLES TO nexus_readonly;

ALTER DEFAULT PRIVILEGES FOR ROLE nexus_migration IN SCHEMA platform
    GRANT SELECT ON TABLES TO nexus_readonly;

-- ── Sequences ─────────────────────────────────────────────────────────────

ALTER DEFAULT PRIVILEGES FOR ROLE nexus_migration IN SCHEMA core_mdm
    GRANT USAGE, SELECT ON SEQUENCES TO nexus_app;

ALTER DEFAULT PRIVILEGES FOR ROLE nexus_migration IN SCHEMA ai
    GRANT USAGE, SELECT ON SEQUENCES TO nexus_app;

ALTER DEFAULT PRIVILEGES FOR ROLE nexus_migration IN SCHEMA platform
    GRANT USAGE, SELECT ON SEQUENCES TO nexus_app;

-- ── Functions ─────────────────────────────────────────────────────────────

ALTER DEFAULT PRIVILEGES FOR ROLE nexus_migration IN SCHEMA app_context
    GRANT EXECUTE ON FUNCTIONS TO nexus_app;

ALTER DEFAULT PRIVILEGES FOR ROLE nexus_migration IN SCHEMA event_store
    GRANT EXECUTE ON FUNCTIONS TO nexus_app;

ALTER DEFAULT PRIVILEGES FOR ROLE nexus_migration IN SCHEMA core_mdm
    GRANT EXECUTE ON FUNCTIONS TO nexus_app;

-- ── Prevent PUBLIC leakage ────────────────────────────────────────────────

ALTER DEFAULT PRIVILEGES FOR ROLE nexus_migration
    REVOKE ALL ON TABLES FROM PUBLIC;

ALTER DEFAULT PRIVILEGES FOR ROLE nexus_migration
    REVOKE ALL ON SEQUENCES FROM PUBLIC;

ALTER DEFAULT PRIVILEGES FOR ROLE nexus_migration
    REVOKE ALL ON FUNCTIONS FROM PUBLIC;

COMMIT;
