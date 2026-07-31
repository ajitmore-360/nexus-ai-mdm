# Nexus AI MDM — Complete Database Setup

Running the SQL files in this folder in order produces a fully functional Nexus MDM
PostgreSQL database from scratch, including all schemas, tables, indexes, RLS policies,
seed data, and the development admin account.

## Prerequisites

| Requirement | Notes |
|---|---|
| PostgreSQL 14+ | 13 works; pgvector requires Postgres 12+ |
| pgvector extension | `git clone https://github.com/pgvector/pgvector && cd pgvector && make && make install` |
| pgcrypto | Bundled with PostgreSQL (`postgresql-contrib`) |
| A database user with SUPERUSER or CREATEROLE + CREATE EXTENSION | Needed for `00_bootstrap.sql` only |

## How to apply

```bash
# 1. Create the database (skip if it already exists)
createdb -U postgres nexus_mdm

# 2. Bootstrap: extensions + schemas  (run as superuser)
psql -U postgres -d nexus_mdm -f 00_bootstrap.sql

# 3. Apply all migrations in order
for f in $(ls 0*.sql | sort); do
    echo "Applying $f ..."
    psql -U postgres -d nexus_mdm -f "$f"
done
```

On Windows (PowerShell):
```powershell
# Create database
& createdb -U postgres nexus_mdm

# Bootstrap
& psql -U postgres -d nexus_mdm -f "00_bootstrap.sql"

# Apply all migrations
Get-ChildItem "0*.sql" | Sort-Object Name | ForEach-Object {
    Write-Host "Applying $($_.Name) ..."
    & psql -U postgres -d nexus_mdm -f $_.FullName
}
```

## File order

| File | What it creates |
|---|---|
| `00_bootstrap.sql` | Extensions (pgcrypto, citext, vector, pg_trgm) and all application schemas |
| `0001_workspace_stub.sql` | No-op stub |
| `0002_ai_schema.sql` | ai.steward_feedback, ai.rag_documents, ai.entity_embeddings, ai.anomalies |
| `0003_production_tables.sql` | Core tables: tenants, entities, entity_attributes, golden_records, match_candidates, field_match_results, survivorship_rules, outbox_events, policy_rules, notifications, distribution jobs |
| `0004_outbox_dlq_and_compat.sql` | event_store.outbox_dlq, platform.revoked_tokens |
| `0005_data_retention.sql` | Retention functions for GDPR Art.5(1)(e) storage limitation |
| `0006_entity_schemas_and_licensing.sql` | attribute_schemas, entity_sequences, tenant_profiles, licenses, license_feature_registry — seeds global default attribute schemas for Customer / Vendor / Product / Material / Employee / Location |
| `0007_supplemental_tables.sql` | match_records, lineage.entity_lineage, consent_records |
| `0008_identities_and_memberships.sql` | identities, tenant_memberships, user_invitations, password_resets, tenant_licenses — seeds admin@nexus.ai |
| `0009_fix_dev_admin_seed.sql` | Idempotent repair for admin@nexus.ai password hash |
| `0010_uat_ready.sql` | core_mdm.audit_events, seeds ITAdmin@nexus.ai (password: Itadmin@123) |
| `0011_itadmin_single_tenant.sql` | Restricts ITAdmin to demo tenant only |
| `0012_submaster_reference_data.sql` | submaster_types, submaster_values — seeds currency, UOM, payment terms, industry, region, etc. |
| `0013_quality_rules.sql` | quality_rules, quality_violations |
| `0014_postal_codes.sql` | geo_postal_codes (global postal code reference; sample seed for dev) |
| `0015_ai_suggestions.sql` | ai_suggestions |
| `0016_entity_xrefs.sql` | entity_xrefs (cross-reference / ID mapping registry) |
| `0017_entity_comments.sql` | entity_comments (discussion threads on MDM records) |
| `0018_quality_snapshots.sql` | quality_snapshots (trend analytics scorecards) |
| `0019_entity_hierarchy.sql` | entity_hierarchies (closure table), set_entity_parent() function |
| `0020_merge_requests.sql` | merge_requests |
| `0021_data_profiling.sql` | data_profiles, entity_versions (bitemporal records) |
| `0022_tasks_and_reference_data.sql` | tasks, reference_lists, reference_values, notification_subscriptions |
| `0023_transformation_rules.sql` | transformation_rules, transformation_log, party_roles |
| `0024_sso_scim.sql` | sso_configurations, saml_sessions, scim_tokens |
| `0025_workflow_connectors_enrichment.sql` | workflow_definitions, workflow_runs, connector_catalog, tenant_connectors, enrichment_providers, tenant_enrichment_configs, enrichment_requests — seeds 15 certified connectors and 10 enrichment providers |
| `0026_entity_blocking_keys.sql` | entity_blocking_keys (pre-computed phonetic blocking keys for matching) |
| `0027_current_attributes_denormalisation.sql` | Adds current_attributes JSONB to entities and golden_records |
| `0028_entity_attributes_improvements.sql` | Adds entity_type and attribute_value_text (generated) to entity_attributes |
| `0029_entity_attributes_partition.sql` | Converts entity_attributes to LIST-partitioned table (Customer/Vendor/Material/+8 more) |
| `0030_retention_and_cleanup.sql` | Retention functions for match_requests, delivery_log, ingest_jobs |
| `0031_autovacuum_tuning.sql` | Per-table autovacuum settings for high-churn tables |
| `0032_golden_materialized_views.sql` | Materialized views: golden_customers, golden_vendors, golden_materials |
| `0033_entity_type_blocking_rules.sql` | entity_type_blocking_rules |
| `0034_missing_runtime_tables.sql` | match_requests, match_review_queue, entity_type_configs, number_sequences, entity_type_assignments, entity_approval_requests, notifications schema + tables |
| `0035_final_gaps.sql` | audit_event_log, survivorship_field_decisions, gdpr_erase_entity(), ingest.ingest_jobs |

## Default credentials (development only)

| Account | Email | Password | Role |
|---|---|---|---|
| System Admin | admin@nexus.ai | Admin@123 | super_admin |
| IT Admin | ITAdmin@nexus.ai | Itadmin@123 | super_admin |

**These credentials must be rotated before any production deployment.**

## Default tenant

The default tenant is seeded in `0003_production_tables.sql`:
- **ID**: `00000000-0000-0000-0000-000000000001`
- **Code**: `default`
- **Name**: Default Organisation
- **Tier**: Enterprise (all features enabled, unlimited entities)

## Docker / application usage

The Rust services run `sqlx::migrate!("./migrations")` which bakes
`shared/database/migrations/` into the binary at compile time. The files in THIS
folder (nexus-ai-mdm/database/) are an audited, standalone copy intended for:

- Setting up a fresh database outside Docker
- Database reviews and audits
- Manual schema recovery
- Sharing the complete schema with DBAs

When running the Docker stack, the application migrations run automatically on
startup — you do not need to run these files separately.

## Known limitations

- `golden_records.rs` handler: the handler still references `golden_record_attributes`
  (the old EAV table) at runtime. After migration 0027 added `current_attributes` JSONB,
  the handler code was not updated to use it. The matching and survivorship engine work
  correctly; the affected handler is the golden records detail view which will return
  an empty attributes list until the Rust code is updated.

- `pg_cron`: the retention and materialized-view refresh schedules in migrations 0030
  and 0032 are wrapped in `IF EXISTS` guards. Without pg_cron installed they are
  silently skipped. Retention must then be triggered manually or via application
  scheduler.
