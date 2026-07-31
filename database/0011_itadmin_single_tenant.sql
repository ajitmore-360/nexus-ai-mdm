-- =============================================================================
-- Migration 0011: Enforce single-tenant rule for ITAdmin
--
-- Business rule: tenants represent clients. A user belongs to exactly one
-- tenant. Migration 0010 mistakenly seeded ITAdmin into both the system
-- tenant (00...0001) and the demo tenant (00...0002).
--
-- This migration removes the system-tenant membership so login auto-selects
-- the Demo Organization without showing any tenant picker.
-- =============================================================================

DELETE FROM core_mdm.tenant_memberships
WHERE identity_id = (
          SELECT identity_id
          FROM   core_mdm.identities
          WHERE  email = 'ITAdmin@nexus.ai'
      )
  AND tenant_id = '00000000-0000-0000-0000-000000000001'::uuid;
