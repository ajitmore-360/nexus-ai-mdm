--
-- =========================================================
-- Azile MDM Platform
-- Default Privileges (runs after schemas are created)
-- File: 004_default_privileges.sql
-- =========================================================
-- ALTER DEFAULT PRIVILEGES sets permissions that are
-- automatically applied to objects created by azile_migration
-- in the future.  Must run after 003_schemas.sql.
-- =========================================================
--

BEGIN;

-- â”€â”€ Application role: tables â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

ALTER DEFAULT PRIVILEGES FOR ROLE azile_migration IN SCHEMA core_mdm
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO azile_app;

ALTER DEFAULT PRIVILEGES FOR ROLE azile_migration IN SCHEMA event_store
    GRANT SELECT, INSERT, UPDATE ON TABLES TO azile_app;

ALTER DEFAULT PRIVILEGES FOR ROLE azile_migration IN SCHEMA audit
    GRANT SELECT, INSERT ON TABLES TO azile_app;

ALTER DEFAULT PRIVILEGES FOR ROLE azile_migration IN SCHEMA ai
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO azile_app;

ALTER DEFAULT PRIVILEGES FOR ROLE azile_migration IN SCHEMA governance
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO azile_app;

ALTER DEFAULT PRIVILEGES FOR ROLE azile_migration IN SCHEMA platform
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO azile_app;

-- â”€â”€ Read-only role: tables â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

ALTER DEFAULT PRIVILEGES FOR ROLE azile_migration IN SCHEMA core_mdm
    GRANT SELECT ON TABLES TO azile_readonly;

ALTER DEFAULT PRIVILEGES FOR ROLE azile_migration IN SCHEMA audit
    GRANT SELECT ON TABLES TO azile_readonly;

ALTER DEFAULT PRIVILEGES FOR ROLE azile_migration IN SCHEMA lineage
    GRANT SELECT ON TABLES TO azile_readonly;

ALTER DEFAULT PRIVILEGES FOR ROLE azile_migration IN SCHEMA platform
    GRANT SELECT ON TABLES TO azile_readonly;

-- â”€â”€ Sequences â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

ALTER DEFAULT PRIVILEGES FOR ROLE azile_migration IN SCHEMA core_mdm
    GRANT USAGE, SELECT ON SEQUENCES TO azile_app;

ALTER DEFAULT PRIVILEGES FOR ROLE azile_migration IN SCHEMA ai
    GRANT USAGE, SELECT ON SEQUENCES TO azile_app;

ALTER DEFAULT PRIVILEGES FOR ROLE azile_migration IN SCHEMA platform
    GRANT USAGE, SELECT ON SEQUENCES TO azile_app;

-- â”€â”€ Functions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

ALTER DEFAULT PRIVILEGES FOR ROLE azile_migration IN SCHEMA app_context
    GRANT EXECUTE ON FUNCTIONS TO azile_app;

ALTER DEFAULT PRIVILEGES FOR ROLE azile_migration IN SCHEMA event_store
    GRANT EXECUTE ON FUNCTIONS TO azile_app;

ALTER DEFAULT PRIVILEGES FOR ROLE azile_migration IN SCHEMA core_mdm
    GRANT EXECUTE ON FUNCTIONS TO azile_app;

-- â”€â”€ Prevent PUBLIC leakage â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

ALTER DEFAULT PRIVILEGES FOR ROLE azile_migration
    REVOKE ALL ON TABLES FROM PUBLIC;

ALTER DEFAULT PRIVILEGES FOR ROLE azile_migration
    REVOKE ALL ON SEQUENCES FROM PUBLIC;

ALTER DEFAULT PRIVILEGES FOR ROLE azile_migration
    REVOKE ALL ON FUNCTIONS FROM PUBLIC;

COMMIT;
