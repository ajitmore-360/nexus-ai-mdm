# Azile AI MDM â€” Database Architecture & Data Flow Reference

**Version:** 1.0  
**Platform:** Azile AI MDM  
**Database:** PostgreSQL 16 with pgvector, pg_trgm, citext extensions  
**Audience:** Architects, Backend Engineers, DBAs, Integration Teams

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Database Schema Design](#2-database-schema-design)
3. [Core Data Model](#3-core-data-model)
4. [Table Reference](#4-table-reference)
5. [Data Flow: Entity Ingestion](#5-data-flow-entity-ingestion)
6. [Data Flow: Matching Pipeline](#6-data-flow-matching-pipeline)
7. [Data Flow: Merge & Golden Record](#7-data-flow-merge--golden-record)
8. [Data Flow: Event Sourcing (Outbox Pattern)](#8-data-flow-event-sourcing-outbox-pattern)
9. [Data Flow: AI Enrichment & Embeddings](#9-data-flow-ai-enrichment--embeddings)
10. [Multi-Tenancy & Row-Level Security](#10-multi-tenancy--row-level-security)
11. [Auto-Numbering System](#11-auto-numbering-system)
12. [License & Feature Control](#12-license--feature-control)
13. [Migration Strategy](#13-migration-strategy)
14. [Performance Design](#14-performance-design)
15. [GDPR & Data Retention](#15-gdpr--data-retention)

---

## 1. Architecture Overview

### Technology Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Primary database | PostgreSQL 16 | All structured MDM data, ACID transactions |
| Vector search | pgvector extension | Semantic similarity, entity embeddings, RAG |
| Fuzzy text | pg_trgm extension | Trigram similarity for fuzzy name matching |
| Case-insensitive text | citext extension | Email, tenant codes, normalised lookups |
| Cache & sessions | Redis 7 | Entity read cache, JWT session store, rate limiting, pub/sub |
| Event streaming | Apache Kafka | Async entity event distribution to downstream systems |

### Deployment Model

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚                        APPLICATION TIER                              â”‚
â”‚                                                                      â”‚
â”‚  api-gateway â†’ mdm-core â†’ {ai, ingest, policy, search, ...}        â”‚
â”‚                    â”‚                                                 â”‚
â”‚                    â”‚  RequestContextFactory                          â”‚
â”‚                    â”‚  (sets app.current_tenant per transaction)     â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¼â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
                     â”‚
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â–¼â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚                        DATA TIER                                     â”‚
â”‚                                                                      â”‚
â”‚  â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â” â”‚
â”‚  â”‚                  PostgreSQL 16 (azile_mdm)                     â”‚ â”‚
â”‚  â”‚                                                                â”‚ â”‚
â”‚  â”‚  core_mdm  â”‚ event_store â”‚ ai â”‚ governance â”‚ platform â”‚ audit â”‚ â”‚
â”‚  â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜ â”‚
â”‚                          â”‚                                           â”‚
â”‚  â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”  â”Œâ”€â”€â”€â”€â”€â”€â”€â–¼â”€â”€â”€â”€â”€â”€â”€â”  â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚  â”‚ Redis 7    â”‚  â”‚ Outbox Poller â”‚  â”‚  Kafka (event streaming)  â”‚   â”‚
â”‚  â”‚ (cache)    â”‚  â”‚ kafka-event-  â”‚  â”‚  mdm.entity.events        â”‚   â”‚
â”‚  â”‚            â”‚  â”‚ service       â”‚  â”‚  mdm.golden.events        â”‚   â”‚
â”‚  â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜  â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜  â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

### Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Multi-tenancy by design** | Every table has `tenant_id UUID NOT NULL`; Row-Level Security enforced via PostgreSQL session variables |
| **Event sourcing** | All entity mutations emit events to `event_store.outbox_events` in the same ACID transaction |
| **Bitemporal data** | `valid_from / valid_to` (business time) + `recorded_at` (system time) on entities |
| **Soft deletes** | Status = `SoftDeleted` + `valid_to = now()` â€” records never destroyed (audit compliance) |
| **Immutable audit** | `audit` schema receives INSERT-only records; no UPDATE or DELETE permitted |
| **Schema isolation** | 7 schemas by concern â€” each with independent RBAC grants |

---

## 2. Database Schema Design

PostgreSQL uses **schema namespacing** to isolate concerns. Each schema has a dedicated security role with minimum required privileges.

```
azile_mdm (database)
â”‚
â”œâ”€â”€ core_mdm          â† Primary MDM data (entities, golden records, matching)
â”œâ”€â”€ event_store       â† Transactional outbox + dead-letter queue
â”œâ”€â”€ ai                â† Embeddings, RAG knowledge base, steward feedback
â”œâ”€â”€ governance        â† OPA policy rules, compliance tracking
â”œâ”€â”€ platform          â† Licenses, notifications, distribution, sequences
â”œâ”€â”€ audit             â† Immutable audit trail, GDPR request log
â””â”€â”€ lineage           â† Entity data lineage tracking (future)
```

### Schema Access Matrix

| Schema | `azile_app` (runtime) | `azile_readonly` (BI) | `azile_migration` (DDL) |
|--------|----------------------|----------------------|------------------------|
| core_mdm | SELECT, INSERT, UPDATE, DELETE | SELECT | ALL |
| event_store | SELECT, INSERT, UPDATE | â€” | ALL |
| ai | SELECT, INSERT, UPDATE, DELETE | â€” | ALL |
| governance | SELECT, INSERT, UPDATE, DELETE | â€” | ALL |
| platform | SELECT, INSERT, UPDATE, DELETE | SELECT | ALL |
| audit | SELECT, INSERT | SELECT | ALL |

### Role Security Settings

```sql
-- azile_app: runtime application role
SET row_security = on;                           -- RLS enforced on every query
SET default_transaction_isolation = 'read committed';
SET idle_in_transaction_session_timeout = '5min';

-- azile_readonly: analytics/BI role  
SET default_transaction_read_only = on;          -- Cannot accidentally write

-- azile_migration: DDL management
SET lock_timeout = '30s';
SET statement_timeout = '30min';
```

---

## 3. Core Data Model

### Entity Hierarchy

```
core_mdm.tenants (1)
    â”‚
    â”œâ”€â”€ core_mdm.users (N)           â† Users belonging to the tenant
    â”œâ”€â”€ core_mdm.source_systems (N)  â† Connected source systems
    â”œâ”€â”€ core_mdm.entity_sequences    â† Number generators (CUST-000001)
    â”œâ”€â”€ core_mdm.attribute_schemas   â† Field definitions per entity type
    â”‚
    â””â”€â”€ core_mdm.entities (N)        â† THE CORE RECORD
            â”‚
            â”œâ”€â”€ core_mdm.entity_attributes (N)   â† Key-value attribute store
            â”‚
            â”œâ”€â”€ core_mdm.match_candidates (N)    â† Duplicate candidates found
            â”‚       â””â”€â”€ core_mdm.field_match_results (N)
            â”‚
            â””â”€â”€ core_mdm.golden_records (1:N)    â† Master/golden record
                    â””â”€â”€ core_mdm.golden_attributes (N)

event_store.outbox_events  â† Every mutation emits here (same transaction)
event_store.outbox_dlq     â† Failed events after 3 retries

ai.entity_embeddings       â† pgvector semantic vectors
ai.rag_documents           â† RAG knowledge base
ai.steward_feedback        â† Human review decisions (training data)

governance.policy_rules    â† OPA Rego policies per tenant
platform.licenses          â† JWT-signed license tokens
platform.distribution_*    â† Downstream push connectors
```

### Entity Lifecycle State Machine

```
                    â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
                    â”‚                                         â”‚
          â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â–¼â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”                             â”‚
          â”‚      DRAFT         â”‚  â† Created but not active   â”‚
          â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜                             â”‚
                    â”‚ activate                               â”‚
          â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â–¼â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”                             â”‚
          â”‚      ACTIVE        â”‚ â—„â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ â”¤
          â””â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”˜                             â”‚
             â”‚      â”‚    â”‚ flag issue                        â”‚
             â”‚      â”‚    â–¼                                   â”‚
             â”‚      â”‚  UNDER_INVESTIGATION â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
             â”‚      â”‚                                        â”‚
             â”‚      â”‚ merge trigger                          â”‚
             â”‚      â–¼                                        â”‚
             â”‚   PENDING_REVIEW â”€â”€â–º MERGED â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
             â”‚                         (source entity)      â”‚
             â”‚                                              â”‚
             â”‚ deactivate                                    â”‚
             â–¼                                              â”‚
          INACTIVE â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
             â”‚                                              â”‚
             â”‚ retire                                        â”‚
             â–¼                                              â”‚
          ARCHIVED â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
             â”‚                                              â”‚
             â”‚ GDPR erasure                                  â”‚
             â–¼                                              â”‚
          SOFT_DELETED â—„â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

### Golden Record Lifecycle

```
Entities merged
    â”‚
    â–¼
  CREATED â”€â”€â–º MATCHED â”€â”€â–º SURVIVORSHIP_APPLIED â”€â”€â–º AI_VALIDATED
                                                          â”‚
                              â—„â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
                              â”‚
                         HUMAN_REVIEWED â”€â”€â–º APPROVED â”€â”€â–º PUBLISHED
                                                               â”‚
                                                          ARCHIVED
```

---

## 4. Table Reference

### 4.1 core_mdm.tenants

The root of the multi-tenant hierarchy. Every other table references `tenant_id`.

| Column | Type | Description |
|--------|------|-------------|
| tenant_id | UUID PK | Immutable tenant identifier |
| tenant_code | CITEXT UNIQUE | URL-safe slug: `acme-corp` |
| display_name | TEXT | Human-readable name |
| plan | TEXT | `community\|professional\|enterprise\|oem` |
| status | TEXT | `active\|suspended\|expired` |
| max_entities | BIGINT | License quota (NULL = unlimited) |
| llm_model | TEXT | Ollama model for this tenant |
| features | JSONB | Feature flags: `{"ai_matching": true}` |
| settings | JSONB | Tenant-specific config overrides |

### 4.2 core_mdm.entities

The central record store. Every master data object (Customer, Vendor, Product, etc.) lives here. The schema is intentionally flat â€” **attributes are stored in a separate table** for flexibility.

| Column | Type | Description |
|--------|------|-------------|
| entity_id | UUID PK | System identifier (used in all FK relations) |
| tenant_id | UUID NOT NULL | Multi-tenancy partition key |
| entity_type | TEXT NOT NULL | `Customer\|Vendor\|Product\|Material\|...` |
| status | TEXT NOT NULL | Entity lifecycle state |
| external_ids | JSONB | `{"salesforce": "SF-001", "sap": "K-9021"}` |
| tags | TEXT[] | Free-form classification tags |
| metadata | JSONB | Flexible catch-all for source-system data |
| trust_score | FLOAT4 | 0.0â€“1.0 data quality confidence |
| source_system | TEXT | Which system originally created this |
| golden_record_id | UUID | FK to golden record (if merged) |
| semantic_identity | TEXT | Human-readable summary for RAG |
| vector_namespace | TEXT | pgvector partition key |
| **valid_from** | TIMESTAMPTZ | Business time: when fact became true |
| **valid_to** | TIMESTAMPTZ | `'infinity'` for current records |
| **recorded_at** | TIMESTAMPTZ | Transaction time: when system recorded it |
| created_at / updated_at | TIMESTAMPTZ | Standard audit timestamps |

**Key indexes:**
```sql
-- Tenant + type lookup (most common query pattern)
CREATE INDEX idx_entities_tenant_type ON entities (tenant_id, entity_type) WHERE valid_to = 'infinity';

-- Full-text search on metadata JSONB
CREATE INDEX idx_entities_fts ON entities USING gin(to_tsvector('english', metadata::text)) WHERE valid_to = 'infinity';

-- Golden record link
CREATE INDEX idx_entities_golden ON entities (tenant_id, golden_record_id) WHERE golden_record_id IS NOT NULL;
```

### 4.3 core_mdm.entity_attributes

Stores all attribute values in a normalised EAV (Entity-Attribute-Value) table. This enables:
- Flexible schema per entity type
- Tenant-specific custom attributes
- Efficient indexing of specific attributes for blocking

| Column | Type | Description |
|--------|------|-------------|
| attribute_id | UUID PK | |
| tenant_id | UUID | |
| entity_id | UUID FK | â†’ entities |
| attribute_key | TEXT | Machine name: `legal_name`, `email` |
| attribute_value | JSONB | Value (supports string, number, array, object) |
| data_type | TEXT | `string\|number\|date\|boolean\|address` |
| confidence | FLOAT4 | Attribute-level confidence score |
| source_system | TEXT | Which source provided this value |
| is_masked | BOOLEAN | True if GDPR-masked |

**Key index for blocking:**
```sql
-- Blocking key lookups: email, phone, tax_id
CREATE INDEX idx_entity_attrs_lookup ON entity_attributes (tenant_id, attribute_key, entity_id);

-- JSONB value search for exact matches
CREATE INDEX idx_entity_attrs_value ON entity_attributes USING gin(attribute_value jsonb_path_ops);
```

### 4.4 core_mdm.golden_records

The output of the merge + survivorship process. One golden record represents the "master truth" about an entity across all source systems.

| Column | Type | Description |
|--------|------|-------------|
| golden_record_id | UUID PK | |
| tenant_id | UUID | |
| entity_type | TEXT | Inherited from merged entities |
| status | TEXT | `Active\|Pending\|Archived` |
| lifecycle_stage | TEXT | `Createdâ†’Matchedâ†’SurvivorshipAppliedâ†’AIValidatedâ†’HumanReviewedâ†’Approvedâ†’Publishedâ†’Archived` |
| trust_score | FLOAT4 | Aggregate quality score |
| quality_score | FLOAT4 | Data completeness metric |
| source_entities | UUID[] | Array of contributing entity IDs |
| golden_attributes | JSONB | Merged attributes with survivorship reasoning |
| valid_from / valid_to | TIMESTAMPTZ | Bitemporal validity |

### 4.5 core_mdm.match_candidates

Records the output of the matching pipeline. Stores which entity pairs were identified as potential duplicates and the evidence supporting that decision.

| Column | Type | Description |
|--------|------|-------------|
| match_candidate_id | UUID PK | |
| tenant_id | UUID | |
| request_id | UUID | Groups all candidates from one match run |
| source_entity_id | UUID | The entity being evaluated |
| matched_entity_id | UUID | The potential duplicate found |
| match_status | TEXT | `Pending\|Matched\|RequiresReview\|Rejected\|AutoMerged` |
| match_score | FLOAT4 | Overall similarity score (0.0â€“1.0) |
| confidence_score | FLOAT4 | Confidence in the score |
| vector_similarity | FLOAT4 | pgvector cosine similarity |
| ai_score | FLOAT4 | LLM semantic similarity (when used) |
| recommended_for_merge | BOOLEAN | True if score â‰¥ auto_merge_threshold (0.95) |
| requires_human_review | BOOLEAN | True if 0.75 â‰¤ score < 0.95 |
| explanations | JSONB | Human-readable match reasons |
| policy_decisions | JSONB | OPA policy evaluation results |

### 4.6 core_mdm.attribute_schemas

Defines the standard and custom attribute templates per entity type. Drives the dynamic form builder in the UI.

| Column | Type | Description |
|--------|------|-------------|
| schema_id | UUID PK | |
| tenant_id | UUID | NULL = global default for all tenants |
| entity_type | TEXT | `Customer\|Vendor\|Product\|...` |
| attribute_key | TEXT | Machine name: `legal_name` |
| display_name | TEXT | `"Legal Company Name"` |
| group_name | TEXT | UI group: `Identity\|Contact\|Financial` |
| data_type | TEXT | `string\|number\|date\|boolean\|enum\|address\|phone\|email\|url` |
| is_required | BOOLEAN | Form validation |
| is_pii | BOOLEAN | GDPR flag â€” triggers masking/erasure |
| is_system | BOOLEAN | Cannot be deleted (business number field) |
| enum_values | JSONB | `["Active","Inactive","Prospect"]` |
| validation | JSONB | `{"maxLength":200,"regex":"^[A-Z]"}` |
| display_order | INT | Ordering within group |

**Standard attributes seeded for Customer (20 fields across 5 groups):**
- `Identity`: customer_number (auto), legal_nameâœ¦, trade_name, customer_type, status
- `Contact`: emailâœ¦, phone, mobile, website, fax
- `Address`: billing_address, shipping_address, country
- `Financial`: tax_id, vat_number, credit_limit, payment_terms, currency
- `Business`: industry, annual_revenue, employee_count, account_manager

### 4.7 core_mdm.entity_sequences

Powers the auto-numbering system (CUST-000001, VEND-000001, etc.).

| Column | Type | Description |
|--------|------|-------------|
| tenant_id | UUID PK (composite) | Tenant scope |
| entity_type | TEXT PK (composite) | `Customer\|Vendor\|...` |
| prefix | TEXT | `CUST` (configurable) |
| separator | TEXT | `-` (configurable: `-_` or empty) |
| min_digits | INT | `6` â†’ `000001` (configurable 4â€“12) |
| current_value | BIGINT | Atomically incremented |
| step | INT | Usually 1 (configurable for gap-compatibility) |
| reset_yearly | BOOLEAN | Reset to 1 each January 1 |

### 4.8 event_store.outbox_events

The transactional outbox. Every data mutation in `core_mdm` simultaneously inserts a row here **in the same database transaction**. This guarantees exactly-once event publication to Kafka.

| Column | Type | Description |
|--------|------|-------------|
| event_id | UUID PK | |
| tenant_id | UUID | |
| aggregate_type | TEXT | `entity\|golden_record\|match` |
| aggregate_id | UUID | The entity/record that changed |
| event_type | TEXT | `EntityCreated\|EntityMerged\|GoldenRecordPublished` |
| event_payload | JSONB | Full event data (including entity snapshot) |
| event_metadata | JSONB | correlation_id, trace_id, causation_id |
| topic_name | TEXT | Kafka topic: `mdm.entity.events` |
| status | TEXT | `pending\|published\|failed` |
| **published** | BOOLEAN | `false` until kafka-event-service publishes it |
| retry_count | INT | Increments on each failed publish attempt |
| published_at | TIMESTAMPTZ | When successfully published |

### 4.9 event_store.outbox_dlq

Dead-letter queue for events that failed 3 publish attempts. Operators can inspect and replay.

### 4.10 ai.entity_embeddings

Stores pgvector embeddings (768-dimension from `nomic-embed-text`) for each entity. Used by the vector blocking strategy and semantic search.

| Column | Type | Description |
|--------|------|-------------|
| embedding_id | UUID PK | |
| tenant_id | UUID | |
| entity_id | UUID | FK â†’ entities |
| embedding_model | TEXT | `nomic-embed-text` |
| embedding | VECTOR(768) | pgvector column |
| generated_at | TIMESTAMPTZ | |

**ANN index:**
```sql
CREATE INDEX idx_entity_embeddings_ann
    ON ai.entity_embeddings USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);
-- Enables approximate nearest neighbour in O(log n) instead of O(n)
```

### 4.11 ai.steward_feedback

Records human steward decisions (approve/reject match) as labelled training data for the adaptive weight tuning system.

| Column | Type | Description |
|--------|------|-------------|
| feedback_id | UUID PK | |
| tenant_id | UUID | |
| steward_id | UUID | Who made the decision |
| feedback_type | TEXT | `match_approved\|match_rejected\|merge_overridden` |
| source_entity_id | UUID | Entity being reviewed |
| feature_vector | JSONB | `{"exact":0.9,"fuzzy":0.7,"phonetic":0.3,"semantic":0.8,"vector":0.6}` |
| system_decision | TEXT | What the system recommended |
| human_decision | TEXT | What the human chose |
| used_in_training | BOOLEAN | Has been incorporated into weight model |

### 4.12 platform.licenses

JWT-signed license tokens issued by the Azile MDM vendor.

| Column | Type | Description |
|--------|------|-------------|
| license_id | UUID PK | |
| organization | TEXT | Licensee company name |
| tier | TEXT | `Community\|Professional\|Enterprise\|OEM` |
| issued_at / expires_at | TIMESTAMPTZ | Validity window |
| features | JSONB | `["ai_matching","rag_copilot","webhooks",...]` |
| license_token | TEXT UNIQUE | The original JWT (for offline verification) |
| status | TEXT | `active\|expired\|revoked` |
| checksum | TEXT | SHA-256 of token (tamper detection) |

---

## 5. Data Flow: Entity Ingestion

### Flow Overview

```
External Source System
        â”‚
        â”‚  CSV / REST / Kafka / CDC
        â–¼
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚                    ingest-service (:8083)                       â”‚
â”‚                                                                 â”‚
â”‚  1. VALIDATION                                                  â”‚
â”‚     â€¢ Request body size limit (10 MB max)                       â”‚
â”‚     â€¢ Strip INTERNAL_FIELDS (trust_score, entity_id, etc.)     â”‚
â”‚     â€¢ Validate tenant_id from JWT                               â”‚
â”‚                                                                 â”‚
â”‚  2. SCHEMA MAPPING                                              â”‚
â”‚     â€¢ SchemaMapper applies tenant field mappings:               â”‚
â”‚       "company" â†’ "legal_name"                                 â”‚
â”‚       "email_address" â†’ "email" + EmailNormalize transform     â”‚
â”‚       "phone_number" â†’ "phone" + PhoneE164 transform           â”‚
â”‚                                                                 â”‚
â”‚  3. NORMALISATION                                               â”‚
â”‚     â€¢ Lowercase + trim: email                                   â”‚
â”‚     â€¢ E.164 format: +14085550100                               â”‚
â”‚     â€¢ Title case: company names                                 â”‚
â”‚     â€¢ ISO 8601 dates: YYYY-MM-DD                               â”‚
â”‚                                                                 â”‚
â”‚  4. ENTITY BUILD                                                â”‚
â”‚     â€¢ Assign entity_id (UUID v4)                               â”‚
â”‚     â€¢ Set entity_type from batch                               â”‚
â”‚     â€¢ Set record_origin = "Ingested"                           â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
                             â”‚  POST /entities (HTTP)
                             â–¼
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚                    mdm-core (:8081)                             â”‚
â”‚                                                                 â”‚
â”‚  EntityService.create_entity(ctx, request)                     â”‚
â”‚                                                                 â”‚
â”‚  5. IDEMPOTENCY CHECK                                           â”‚
â”‚     â€¢ If entity_id provided AND exists â†’ return existing       â”‚
â”‚     â€¢ Safe to retry on network failure                          â”‚
â”‚                                                                 â”‚
â”‚  6. AUTO-NUMBERING                                              â”‚
â”‚     â€¢ SELECT core_mdm.next_entity_number(tenant, type)         â”‚
â”‚     â€¢ Atomically increments sequence                           â”‚
â”‚     â€¢ Adds attribute: "customer_number" = "CUST-000042"       â”‚
â”‚                                                                 â”‚
â”‚  7. TRANSACTIONAL WRITE  (single ACID transaction)             â”‚
â”‚     â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚     â”‚ BEGIN                                                â”‚   â”‚
â”‚     â”‚                                                      â”‚   â”‚
â”‚     â”‚ SET app.current_tenant = '<tenant_id>'  â† RLS key   â”‚   â”‚
â”‚     â”‚ SET app.request_id     = '<request_id>'             â”‚   â”‚
â”‚     â”‚ SET app.trace_id       = '<trace_id>'               â”‚   â”‚
â”‚     â”‚                                                      â”‚   â”‚
â”‚     â”‚ INSERT INTO core_mdm.entities (...)                  â”‚   â”‚
â”‚     â”‚ INSERT INTO core_mdm.entity_attributes (Ã—N attrs)   â”‚   â”‚
â”‚     â”‚                                                      â”‚   â”‚
â”‚     â”‚ INSERT INTO event_store.outbox_events               â”‚   â”‚
â”‚     â”‚   (EntityCreated payload)                            â”‚   â”‚
â”‚     â”‚                                                      â”‚   â”‚
â”‚     â”‚ [If distribute=true]                                 â”‚   â”‚
â”‚     â”‚ INSERT INTO event_store.outbox_events               â”‚   â”‚
â”‚     â”‚   (EntityDistributionRequested payload)              â”‚   â”‚
â”‚     â”‚                                                      â”‚   â”‚
â”‚     â”‚ COMMIT                                               â”‚   â”‚
â”‚     â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                                                 â”‚
â”‚  8. POST-COMMIT (async, fire-and-forget)                        â”‚
â”‚     â€¢ Redis TaskQueue.enqueue("entity.embed", entity_data)     â”‚
â”‚     â€¢ Redis EntityCache.set(tenant, entity_id, entity)         â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
                             â”‚
              â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”´â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
              â”‚                                â”‚
              â–¼                                â–¼
     Redis Cache                      event_store.outbox_events
     (5-min TTL)                      status='pending'
              â”‚                                â”‚
              â”‚  Fast read path                â”‚ Polled every 5s
              â”‚                                â–¼
              â”‚                     kafka-event-service
              â”‚                     Publishes â†’ Kafka topic:
              â”‚                     "mdm.entity.events"
              â”‚                                â”‚
              â”‚                    â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â–¼â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
              â”‚                    â”‚ Downstream consumers:   â”‚
              â”‚                    â”‚ â€¢ enrichment-service   â”‚
              â”‚                    â”‚ â€¢ search indexer       â”‚
              â”‚                    â”‚ â€¢ distribution-service â”‚
              â”‚                    â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
              â–¼
     Subsequent reads: cache hit (no DB)
     After TTL: cache miss â†’ DB query â†’ re-cache
```

### SQL: Entity Creation Transaction

```sql
-- All 5 statements execute in one transaction with RLS session variables set

-- 1. Set tenant context for RLS policies
SELECT set_config('app.current_tenant', '550e8400-e29b-41d4-a716-446655440000', true);
SELECT set_config('app.request_id',     'abc123...',                             true);

-- 2. Auto-assign business number
SELECT core_mdm.next_entity_number('550e8400...', 'Customer');
-- â†’ 'CUST-000042'

-- 3. Insert entity
INSERT INTO core_mdm.entities (entity_id, tenant_id, entity_type, status, ...)
VALUES ('uuid', '550e8400...', 'Customer', 'Active', ...);

-- 4. Insert attributes (one row per attribute)
INSERT INTO core_mdm.entity_attributes (tenant_id, entity_id, attribute_key, attribute_value, ...)
VALUES
  ('550e8400...', 'uuid', 'customer_number', '"CUST-000042"', ...),
  ('550e8400...', 'uuid', 'legal_name',      '"Acme Corp"',   ...),
  ('550e8400...', 'uuid', 'email',           '"info@acme.com"', ...);

-- 5. Emit outbox event (same transaction = guaranteed delivery)
INSERT INTO event_store.outbox_events (tenant_id, aggregate_type, aggregate_id, event_type, event_payload, topic_name)
VALUES ('550e8400...', 'entity', 'uuid', 'EntityCreated', '{"entity": {...}}', 'mdm.entity.events');
```

---

## 6. Data Flow: Matching Pipeline

The matching pipeline identifies duplicate entities using a multi-stage approach that progressively narrows candidates from millions to a handful.

### Pipeline Overview

```
EntityCreated event (or manual match trigger)
        â”‚
        â–¼
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚              STAGE 1: BLOCKING (O(n) â†’ O(k))                     â”‚
â”‚  Reduces search space from millions to hundreds using cheap keys  â”‚
â”‚                                                                   â”‚
â”‚  â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”    â”‚
â”‚  â”‚ PhoneticBlocker          â†’ PHONETIC:{name_value}         â”‚    â”‚
â”‚  â”‚   "acme corporation"    â†’ lookup name attribute         â”‚    â”‚
â”‚  â”‚                                                          â”‚    â”‚
â”‚  â”‚ CanopyBlocker (token)   â†’ tokens from name/address      â”‚    â”‚
â”‚  â”‚   "acme" "corporation" â†’ find entities sharing tokens  â”‚    â”‚
â”‚  â”‚                                                          â”‚    â”‚
â”‚  â”‚ ExactBlocker            â†’ EMAIL:{email}                 â”‚    â”‚
â”‚  â”‚                           PHONE:{phone_e164}            â”‚    â”‚
â”‚  â”‚                           TAX:{tax_id}                  â”‚    â”‚
â”‚  â”‚                                                          â”‚    â”‚
â”‚  â”‚ VectorBlocker (pgvector)â†’ SELECT entity_id              â”‚    â”‚
â”‚  â”‚   (when semantic=true)    FROM ai.entity_embeddings      â”‚    â”‚
â”‚  â”‚                           ORDER BY embedding <=> $1 LIMIT 200â”‚    â”‚
â”‚  â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜    â”‚
â”‚                                                                   â”‚
â”‚  SQL for phonetic blocking:                                       â”‚
â”‚  SELECT DISTINCT entity_id                                        â”‚
â”‚  FROM core_mdm.entity_attributes                                  â”‚
â”‚  WHERE tenant_id = $1                                             â”‚
â”‚    AND attribute_key = 'name'                                     â”‚
â”‚    AND lower(attribute_value::text) = $2                          â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
                        â”‚  candidate_ids: HashSet<Uuid> (deduplicated)
                        â–¼
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚              STAGE 2: SCORING (per candidate pair)               â”‚
â”‚  Computes weighted similarity score for each sourceâ†’candidate pairâ”‚
â”‚                                                                   â”‚
â”‚  For each candidate entity:                                       â”‚
â”‚                                                                   â”‚
â”‚  field_score = Î£(field_i) / N                                    â”‚
â”‚    where field_i = (exact Ã— 0.35) + (fuzzy Ã— 0.30) + (phonetic Ã— 0.10)â”‚
â”‚                                                                   â”‚
â”‚  Algorithm per field:                                             â”‚
â”‚  â€¢ exact_similarity:    case-insensitive string equality (1.0/0.0)â”‚
â”‚  â€¢ fuzzy_similarity:    (jaro_winkler + levenshtein) / 2         â”‚
â”‚  â€¢ phonetic_similarity: soundex comparison (1.0/0.0)             â”‚
â”‚                                                                   â”‚
â”‚  final_score = (field_score Ã— 0.90) + (vector_score Ã— 0.10)     â”‚
â”‚                                                                   â”‚
â”‚  confidence = (score Ã— 0.80) + (coverage Ã— 0.20)                â”‚
â”‚    where coverage = matched_fields / total_fields                 â”‚
â”‚                                                                   â”‚
â”‚  [If score in grey zone 0.75â€“0.95 AND ai_assisted=true]:         â”‚
â”‚    â†’ POST /match/semantic to ai-service                          â”‚
â”‚    â†’ Llama 3.2 makes final match/no_match decision               â”‚
â”‚    â†’ Returns: decision, confidence (0-1), reasoning text         â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
                        â”‚  Vec<MatchCandidate> sorted by score DESC
                        â–¼
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚              STAGE 3: CLUSTERING (graph-based)                   â”‚
â”‚  Groups related entities into clusters, selects master record    â”‚
â”‚                                                                   â”‚
â”‚  Build undirected graph:                                          â”‚
â”‚    entity_A â”€â”€â”€â”€ entity_B  (score â‰¥ review_threshold 0.75)      â”‚
â”‚    entity_B â”€â”€â”€â”€ entity_C                                        â”‚
â”‚    entity_A â”€â”€â”€â”€ entity_C                                        â”‚
â”‚                                                                   â”‚
â”‚  DFS connected components:                                        â”‚
â”‚    cluster_1 = {entity_A, entity_B, entity_C}                   â”‚
â”‚                                                                   â”‚
â”‚  Master selection (weighted):                                     â”‚
â”‚    master_score = (avg_match Ã— 0.50)                             â”‚
â”‚                 + (avg_confidence Ã— 0.30)                        â”‚
â”‚                 + (node_centrality Ã— 0.20)                        â”‚
â”‚    â†’ entity with highest master_score = suggested master         â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
                        â”‚  Vec<MatchCluster>
                        â–¼
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚              STAGE 4: REVIEW DECISION                            â”‚
â”‚                                                                   â”‚
â”‚  score â‰¥ 0.95  â†’  AUTO-MERGE (no human needed)                   â”‚
â”‚  0.75 â‰¤ score < 0.95  â†’  HUMAN REVIEW (stewardship queue)       â”‚
â”‚  score < 0.75  â†’  REJECTED (not a duplicate)                     â”‚
â”‚                                                                   â”‚
â”‚  Priority assigned:                                              â”‚
â”‚    score â‰¥ 0.95  â†’ Critical                                      â”‚
â”‚    score â‰¥ 0.90  â†’ High                                          â”‚
â”‚    score â‰¥ 0.85  â†’ Medium                                        â”‚
â”‚    else          â†’ Low                                           â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
                        â”‚  Persisted to:
                        â”œâ”€â–º core_mdm.match_candidates (one row per pair)
                        â””â”€â–º core_mdm.field_match_results (one row per field)
```

### Database Writes During Matching

```sql
-- match_candidates: summary row per entity pair
INSERT INTO core_mdm.match_candidates (
    tenant_id, request_id, source_entity_id, matched_entity_id,
    match_status, match_score, confidence_score,
    vector_similarity, ai_score,
    recommended_for_merge, requires_human_review,
    explanations, policy_decisions
) VALUES (...);

-- field_match_results: one row per attribute compared
INSERT INTO core_mdm.field_match_results (
    tenant_id, request_id, source_entity_id, matched_entity_id,
    field_name, source_value, candidate_value,
    score, strategy, semantic_similarity, explanation
) VALUES (...);

-- FETCH (single JOIN â€” no N+1 query):
SELECT mc.*, fm.*
FROM core_mdm.match_candidates mc
LEFT JOIN core_mdm.field_match_results fm
  ON fm.tenant_id  = mc.tenant_id
 AND fm.request_id = mc.request_id
 AND fm.matched_entity_id = mc.matched_entity_id
WHERE mc.tenant_id  = $1
  AND mc.request_id = $2
ORDER BY mc.match_score DESC, fm.created_at ASC;
```

---

## 7. Data Flow: Merge & Golden Record

When a steward approves a merge (or auto-merge threshold is reached), the merge pipeline executes.

```
Steward clicks "Approve Merge" (or auto-merge triggered)
        â”‚
        â–¼
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚                  MergeService.execute_merge()                   â”‚
â”‚                                                                 â”‚
â”‚  1. LOAD ENTITIES                                               â”‚
â”‚     â€¢ Fetch primary entity from DB (or Redis cache)            â”‚
â”‚     â€¢ Fetch all candidate entities                              â”‚
â”‚                                                                 â”‚
â”‚  2. SURVIVORSHIP EVALUATION                                     â”‚
â”‚     For each attribute, apply winning rule:                     â”‚
â”‚     â€¢ TrustedSource: Salesforce wins over SAP for 'email'      â”‚
â”‚     â€¢ MostRecent:    Use attribute updated most recently       â”‚
â”‚     â€¢ LongestValue:  Use longest non-null value                â”‚
â”‚     â€¢ HighestConfidence: Use value with highest score          â”‚
â”‚     â€¢ AI-Recommended: Ask Llama to choose (with reasoning)     â”‚
â”‚                                                                 â”‚
â”‚  3. ATOMIC TRANSACTION                                          â”‚
â”‚     â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”    â”‚
â”‚     â”‚ BEGIN (with RLS context set)                        â”‚    â”‚
â”‚     â”‚                                                     â”‚    â”‚
â”‚     â”‚ INSERT INTO core_mdm.golden_records (...)           â”‚    â”‚
â”‚     â”‚   (merged attributes, lifecycle_stage='Created')   â”‚    â”‚
â”‚     â”‚                                                     â”‚    â”‚
â”‚     â”‚ UPDATE core_mdm.entities                            â”‚    â”‚
â”‚     â”‚   SET status = 'Merged'                             â”‚    â”‚
â”‚     â”‚   WHERE entity_id IN (merged_ids)                   â”‚    â”‚
â”‚     â”‚                                                     â”‚    â”‚
â”‚     â”‚ UPDATE core_mdm.entities                            â”‚    â”‚
â”‚     â”‚   SET golden_record_id = <new_golden_record_id>    â”‚    â”‚
â”‚     â”‚   WHERE entity_id = <primary_entity_id>            â”‚    â”‚
â”‚     â”‚                                                     â”‚    â”‚
â”‚     â”‚ INSERT INTO event_store.outbox_events              â”‚    â”‚
â”‚     â”‚   (GoldenRecordCreated)                            â”‚    â”‚
â”‚     â”‚ INSERT INTO event_store.outbox_events              â”‚    â”‚
â”‚     â”‚   (EntityMerged)                                   â”‚    â”‚
â”‚     â”‚                                                     â”‚    â”‚
â”‚     â”‚ COMMIT                                              â”‚    â”‚
â”‚     â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜    â”‚
â”‚                                                                 â”‚
â”‚  4. POST-COMMIT                                                 â”‚
â”‚     â€¢ Invalidate Redis cache for merged entity IDs             â”‚
â”‚     â€¢ Kafka events published by kafka-event-service           â”‚
â”‚     â€¢ enrichment-service receives EntityMerged â†’ re-enriches  â”‚
â”‚     â€¢ search-service reindexes the golden record               â”‚
â”‚     â€¢ distribution-service pushes to downstream systems        â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

### Golden Record Attribute Structure

```json
{
  "golden_record_id": "uuid",
  "entity_type": "Customer",
  "trust_score": 0.97,
  "source_entities": ["uuid-A", "uuid-B", "uuid-C"],
  "golden_attributes": {
    "legal_name": {
      "value": "Acme Corporation",
      "source_system": "salesforce",
      "survivorship_rule": "TrustedSource",
      "confidence": 0.94,
      "ai_reasoning": "Salesforce has trust_score 0.94 vs SAP 0.71",
      "human_override": false
    },
    "email": {
      "value": "info@acme.com",
      "source_system": "salesforce",
      "survivorship_rule": "TrustedSource",
      "confidence": 0.99,
      "human_override": false
    },
    "tax_id": {
      "value": "55-1234567",
      "source_system": "sap",
      "survivorship_rule": "HighestConfidence",
      "confidence": 1.0,
      "human_override": false
    }
  }
}
```

---

## 8. Data Flow: Event Sourcing (Outbox Pattern)

### Why Outbox?

Without the outbox pattern, there is a **dual-write problem**: if we write to the database AND publish to Kafka in separate operations, a crash between them causes one to succeed and the other to fail â€” data becomes inconsistent.

The outbox pattern solves this by writing the event to the database **inside the same transaction as the entity change**. The event is guaranteed to be published eventually because Kafka publication is separate from the entity mutation.

```
SERVICE (mdm-core, policy-service, etc.)
     â”‚
     â”‚  RequestContextFactory.begin_uow()
     â”‚  â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
     â”‚  â”‚  PostgreSQL Transaction                                 â”‚
     â”‚  â”‚                                                         â”‚
     â”‚  â”‚  SET app.current_tenant = '<tenant_id>'                â”‚
     â”‚  â”‚                                                         â”‚
     â”‚  â”‚  INSERT/UPDATE core_mdm.entities    â† business data    â”‚
     â”‚  â”‚                                                         â”‚
     â”‚  â”‚  INSERT event_store.outbox_events   â† event record     â”‚
     â”‚  â”‚    status = 'pending'                                   â”‚
     â”‚  â”‚    published = false                                    â”‚
     â”‚  â”‚                                                         â”‚
     â”‚  â”‚  COMMIT  â†â”€â”€ Both succeed or both fail (ACID)          â”‚
     â”‚  â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
     â”‚
     â”‚  uow.commit() â† Rust UnitOfWork pattern
     â”‚
     â–¼

kafka-event-service (background loop, every 5 seconds)
     â”‚
     â”‚  SELECT ... FROM event_store.outbox_events
     â”‚  WHERE published = false
     â”‚  ORDER BY created_at ASC
     â”‚  LIMIT 100
     â”‚  FOR UPDATE SKIP LOCKED    â† prevents duplicate processing
     â”‚
     â–¼
     
     For each pending event:
     â”‚
     â”‚  Try: rdkafka producer â†’ Kafka topic
     â”‚  â”‚
     â”‚  â”œâ”€â”€ Success:
     â”‚  â”‚     UPDATE outbox_events SET published=true, published_at=NOW()
     â”‚  â”‚     â†’ Event consumed by downstream services
     â”‚  â”‚
     â”‚  â””â”€â”€ Failure (attempt 1/2):
     â”‚        UPDATE outbox_events SET retry_count = retry_count + 1
     â”‚        Wait: 5s â†’ 25s â†’ 125s (exponential backoff)
     â”‚
     â””â”€â”€ Failure (attempt 3 = MAX_RETRIES):
           INSERT INTO event_store.outbox_dlq (event_id, failure_reason, ...)
           UPDATE outbox_events SET published=true  â† removed from polling
           â†’ Operator inspects DLQ, fixes issue, replays manually

DOWNSTREAM CONSUMERS (subscribed to Kafka topics):
     â€¢ enrichment-service:     triggers D&B/Experian enrichment
     â€¢ notification-service:   pushes real-time WebSocket alerts
     â€¢ distribution-service:   pushes to Salesforce, SAP, webhooks
     â€¢ search reindexer:        updates search index
     â€¢ audit service:           records immutable audit trail
```

### Kafka Topic Design

| Topic | Events | Consumers |
|-------|--------|-----------|
| `mdm.entity.events` | EntityCreated, EntityUpdated, EntityMerged, EntitySoftDeleted | enrichment, search, audit, notifications |
| `mdm.golden.events` | GoldenRecordCreated, GoldenRecordPublished, GoldenRecordArchived | distribution, notifications |
| `mdm.entity.distribution` | EntityDistributionRequested | distribution-service |
| `mdm.match.events` | MatchApprovedByHuman, MatchRejectedByHuman | ai-service (feedback collection) |

---

## 9. Data Flow: AI Enrichment & Embeddings

### Embedding Pipeline

```
EntityCreated event
        â”‚
        â–¼  (via Redis task queue)
ai-service
  EnrichmentOrchestrator.enrich(entity_id)
        â”‚
        â”œâ”€â”€ 1. Build entity text
        â”‚     "legal_name: Acme Corp. email: info@acme.com. country: US"
        â”‚
        â”œâ”€â”€ 2. Call Ollama API
        â”‚     POST http://ollama:11434/api/embeddings
        â”‚     { "model": "nomic-embed-text", "prompt": "..." }
        â”‚     â†’ 768-dimension float vector
        â”‚
        â”œâ”€â”€ 3. Store embedding
        â”‚     INSERT INTO ai.entity_embeddings (entity_id, embedding, model)
        â”‚
        â””â”€â”€ 4. Update entity's semantic_identity
              UPDATE core_mdm.entities SET semantic_identity = "brief summary"
```

### Vector Search (Hybrid)

```sql
-- Hybrid: blend FTS score and pgvector similarity
SELECT
    e.entity_id, e.entity_type, e.status,
    ts_rank(to_tsvector('english', e.metadata::text),
            plainto_tsquery('english', $3)) AS fts_score,
    (1 - (ae.embedding <=> '[0.1, 0.2, ...]'::vector))::FLOAT4 AS vector_score,
    -- Weighted blend: 70% FTS + 30% vector
    (0.70 * ts_rank(...) + 0.30 * (1 - (ae.embedding <=> '...'::vector))) AS final_score
FROM core_mdm.entities e
JOIN ai.entity_embeddings ae ON ae.entity_id = e.entity_id
WHERE e.tenant_id = $1
  AND e.valid_to  = 'infinity'
ORDER BY final_score DESC
LIMIT $4 OFFSET $5;
```

### RAG Copilot Pipeline

```
User types: "Find customers with duplicate tax IDs"
        â”‚
        â–¼
ai-service MCP Router
        â”‚
        â”œâ”€â”€ 1. Sanitize prompt (injection detection)
        â”‚     â†’ 20+ patterns blocked, 2048 char limit
        â”‚
        â”œâ”€â”€ 2. Embed query
        â”‚     POST /api/embeddings â†’ 768-dim vector
        â”‚
        â”œâ”€â”€ 3. Retrieve context (pgvector ANN)
        â”‚     SELECT * FROM ai.rag_documents
        â”‚     ORDER BY embedding <=> $1::vector LIMIT 5
        â”‚
        â”œâ”€â”€ 4. Build augmented prompt
        â”‚     "You are Azile AI... CONTEXT: [retrieved docs]... QUESTION: ..."
        â”‚
        â”œâ”€â”€ 5. Generate response
        â”‚     POST /api/generate â†’ llama3.2:8b
        â”‚
        â””â”€â”€ 6. Return to Flutter UI
              { answer: "I found 3 customers sharing tax_id 55-1234567...",
                source_docs: [...] }
```

---

## 10. Multi-Tenancy & Row-Level Security

### Tenant Isolation Architecture

Every service request carries a `tenant_id` from the validated JWT. The `RequestContextFactory` sets this as a PostgreSQL session variable **before any DML executes** â€” ensuring RLS policies can filter data.

```
HTTP Request arrives
    â”‚
    â”œâ”€â”€ api-gateway: validate JWT â†’ extract nxs_tenant_id
    â”œâ”€â”€ tenant_middleware: compare JWT tenant_id === x-tenant-id header
    â”‚   (mismatch â†’ 403 FORBIDDEN â€” prevents cross-tenant access)
    â”‚
    â””â”€â”€ mdm-core handler:
            â”‚
            â–¼
        RequestContextFactory.begin_uow(tenant_id, user_id, trace_id)
            â”‚
            â”œâ”€â”€ BEGIN transaction
            â”œâ”€â”€ SELECT set_config('app.current_tenant', tenant_id, true)
            â”œâ”€â”€ SELECT set_config('app.request_id',     request_id, true)
            â”œâ”€â”€ SELECT set_config('app.trace_id',       trace_id,   true)
            â”‚
            â””â”€â”€ All queries in this transaction see only tenant's data
                (RLS policies read current_setting('app.current_tenant'))
```

### RLS Policy Example

```sql
-- Entities: each tenant sees only their own records
CREATE POLICY entities_tenant_isolation ON core_mdm.entities
    USING (tenant_id::text = current_setting('app.current_tenant', true));

-- The azile_app role has row_security=ON â€” all queries filtered automatically
-- The azile_migration role bypasses RLS (needed for schema migrations)
```

### Session Variables Set Per Transaction

| Variable | Value | Used By |
|----------|-------|---------|
| `app.current_tenant` | UUID string | RLS policies on every table |
| `app.request_id` | UUID string | Audit trail correlation |
| `app.trace_id` | String | Distributed tracing |
| `app.correlation_id` | UUID string | Event causation chain |
| `app.current_user_id` | UUID string | Audit logging |

---

## 11. Auto-Numbering System

### How CUST-000001 Gets Generated

```sql
-- Function definition (lives in PostgreSQL, executed atomically)
CREATE FUNCTION core_mdm.next_entity_number(p_tenant UUID, p_type TEXT) RETURNS TEXT
LANGUAGE plpgsql AS $$
DECLARE
    v_prefix    TEXT;
    v_separator TEXT;
    v_digits    INT;
    v_next      BIGINT;
BEGIN
    -- Atomic: lock row + increment + return in one statement
    UPDATE core_mdm.entity_sequences
    SET current_value = CASE
            WHEN reset_yearly AND last_reset_year < EXTRACT(YEAR FROM NOW())
            THEN 1
            ELSE current_value + step
          END,
        last_reset_year = EXTRACT(YEAR FROM NOW())::INT,
        updated_at = NOW()
    WHERE tenant_id   = p_tenant
      AND entity_type = p_type
    RETURNING prefix, separator, min_digits, current_value
    INTO v_prefix, v_separator, v_digits, v_next;

    -- e.g.: 'CUST' || '-' || LPAD('42', 6, '0') = 'CUST-000042'
    RETURN v_prefix || v_separator || LPAD(v_next::TEXT, v_digits, '0');
END;
$$;
```

### Number Format Configuration Per Tenant

```
Default:  CUST-000001  (prefix=CUST, separator=-, digits=6)
Custom A: C_00001      (prefix=C, separator=_, digits=5)
Custom B: CUSTOMER2025000001  (prefix=CUSTOMER, separator=empty, digits=6, reset_yearly=true)
Legacy:   10001        (prefix=empty, separator=empty, digits=5, start=10000)
```

---

## 12. License & Feature Control

### License Validation Flow

```
Customer receives nexus-license.json from vendor
        â”‚
        â–¼
POST http://localhost:8090/license/import
{ "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..." }
        â”‚
        â–¼
tenant-service:
  1. JWT.decode(token, VENDOR_PUBLIC_KEY)     â† signature verification
  2. Check exp (not expired)
  3. Check iss == "azile-mdm-vendor"
  4. Check for duplicate (idempotent re-import)
  5. INSERT INTO platform.licenses (tier, features, limits, token, checksum)
        â”‚
        â–¼
Feature check at runtime:
  SELECT features @> '["ai_matching"]'::jsonb
  FROM platform.active_license
  â†’ true/false
```

### Feature Gate Example (Rust)

```rust
// In any service handler â€” check before expensive operation
if !license::is_feature_enabled(&pool, "ai_matching").await {
    return (StatusCode::PAYMENT_REQUIRED,
            Json(json!({"error": "ai_matching requires Professional tier"}))).into_response();
}
```

---

## 13. Migration Strategy

Migrations run in two phases:

### Phase 1: Container Init Scripts (PostgreSQL initdb)
Run **once** when the Docker volume is first created. Create infrastructure before application tables.

| File | Creates |
|------|---------|
| `001_extensions.sql` | pgvector, pg_trgm, citext, uuid-ossp, pg_stat_statements |
| `002_roles.sql` | azile_app, azile_readonly, azile_migration roles + security settings |
| `003_schemas.sql` | core_mdm, event_store, ai, governance, platform, audit schemas + grants |
| `004_table_grants.sql` | Explicit grants on tables created by postgres (not azile_migration) |

### Phase 2: SQLx Migrations (mdm-core startup)
Run **every startup** â€” idempotent, only applies pending migrations. These create all tables.

| Migration | Creates |
|-----------|---------|
| `0001_workspace_stub.sql` | No-op placeholder |
| `0002_ai_schema.sql` | ai.steward_feedback, ai.rag_documents, ai.entity_embeddings, ai.anomalies |
| `0003_production_tables.sql` | ALL core tables: tenants, users, entities, entity_attributes, golden_records, match_candidates, field_match_results, survivorship_rules, outbox_events, governance.policy_rules, platform.notifications, platform.distribution_*, audit.gdpr_requests |
| `0004_outbox_dlq_and_compat.sql` | event_store.outbox_dlq, platform.revoked_tokens, published/retry_count columns, users.password_hash |
| `0005_data_retention.sql` | Retention functions: purge_old_outbox_events(), purge_old_steward_feedback(), etc. |
| `0006_entity_schemas_and_licensing.sql` | core_mdm.attribute_schemas, core_mdm.entity_sequences, core_mdm.tenant_profiles, platform.licenses, platform.license_feature_registry + **seeds all standard attribute definitions and default number sequences** |

### Migration Ownership

**mdm-core is the migration owner.** No other service runs migrations. This prevents race conditions. All other services depend on `mdm-core:healthy` in Docker Compose, which means migrations are complete before any other service attempts DB access.

```
docker compose up
    â”‚
    â”œâ”€â”€ postgres starts â†’ init scripts run (Phase 1)
    â”‚
    â”œâ”€â”€ mdm-core starts:
    â”‚     database::migration::run_migrations(&pool)  â† Phase 2
    â”‚     Applies 0001 â†’ 0002 â†’ 0003 â†’ 0004 â†’ 0005 â†’ 0006
    â”‚     /health/ready â†’ 200 OK
    â”‚
    â””â”€â”€ All other services start (depend on mdm-core:healthy)
```

---

## 14. Performance Design

### Index Strategy

| Pattern | Index Type | Example |
|---------|-----------|---------|
| Tenant + type filter (hot path) | B-tree partial | `(tenant_id, entity_type) WHERE valid_to = 'infinity'` |
| Full-text search | GIN on tsvector | `to_tsvector('english', metadata::text)` |
| JSONB attribute lookup | GIN jsonb_path_ops | `attribute_value jsonb_path_ops` |
| Blocking key exact match | B-tree composite | `(tenant_id, attribute_key, entity_id)` |
| Vector ANN similarity | IVFFlat | `embedding vector_cosine_ops WITH (lists=100)` |
| Outbox polling | B-tree partial | `(created_at ASC) WHERE published = false` |
| Review queue | B-tree partial | `(tenant_id) WHERE requires_human_review = true` |
| Retention cleanup | B-tree | `(published_at) WHERE published = true` |

### Cache Strategy

```
Read Entity:
  1. Check Redis: key = "nexus:{tenant_id}:entity:{entity_id}"  TTL=5min
  2. Cache hit  â†’ return immediately (sub-millisecond)
  3. Cache miss â†’ query PostgreSQL â†’ write to Redis â†’ return

Write Entity:
  1. Write to PostgreSQL (transactional)
  2. Write to Redis cache (write-through, post-commit)
  3. On merge/update â†’ invalidate_entity(tenant_id, entity_id)

Invalidation:
  â€¢ Entity update/merge â†’ delete specific key
  â€¢ Tenant bulk import â†’ delete "nexus:{tenant_id}:*" (SCAN + DEL batch)
```

### Connection Pool Sizing

```
mdm-core PostgreSQL pool:
  max_connections = 50
  min_connections = 5
  acquire_timeout = 10s
  idle_timeout    = 600s (10 min)
  max_lifetime    = 1800s (30 min)
  test_before_acquire = true

Redis pool (deadpool-redis):
  max_size = 20 connections per service

Rationale:
  PostgreSQL max_connections defaults to 100.
  With 10 services Ã— 50 max = 500 (exceeds limit).
  In production: use PgBouncer connection pooler in front of PostgreSQL,
  or configure POSTGRES_MAX_CONNECTIONS=500 in docker-compose.
```

---

## 15. GDPR & Data Retention

### Data Subject Rights Implementation

| GDPR Article | Right | Implementation |
|-------------|-------|---------------|
| Art. 15 | Access | `GET /policy/gdpr/access` â†’ returns all data held |
| Art. 17 | Erasure | `POST /policy/gdpr/erasure` â†’ 7-step erasure process |
| Art. 20 | Portability | `GET /policy/gdpr/access` â†’ JSON export |

### Erasure Process (7 Steps)

When `POST /policy/gdpr/erasure` is called for `subject_id`:

```
1. Find all entities where external_ids->>'subject_id' = subject_id
2. For each entity:
   a. Erase PII attribute values â†’ '"ERASED"'::jsonb
   b. Clear entity metadata â†’ '{}'::jsonb
   c. DELETE from ai.entity_embeddings  (derived from PII text)
   d. DELETE from ai.rag_documents      (may contain entity text)
   e. DELETE from ai.steward_feedback   (contains entity references)
   f. Mark outbox events with gdpr_erased=true (prevents redistribution)
   g. Set entity status = 'SoftDeleted'
3. INSERT INTO audit.gdpr_requests (audit record for compliance proof)
4. Return: { subject_id, fields_erased, records_affected, audit_id }
```

### Retention Policy Functions (scheduled via pg_cron)

```sql
-- Run daily at 2 AM:
SELECT * FROM platform.run_retention_policies();

-- Individual policies:
SELECT event_store.purge_old_outbox_events(90);     -- Keep 90 days of published events
SELECT event_store.purge_old_dlq_events(180);       -- Keep 180 days of DLQ events
SELECT ai.purge_old_steward_feedback(365);          -- Keep 1 year of feedback
SELECT platform.purge_expired_revoked_tokens();     -- Remove tokens older than 8 days
SELECT platform.purge_old_notifications(30);        -- Remove read notifications after 30 days
```

---

## Appendix A: Entity Type â†’ Standard Attributes Mapping

| Entity Type | Key Attributes | Auto-Number Format |
|------------|---------------|-------------------|
| **Customer** | legal_nameâœ¦, emailâœ¦, customer_type, status, tax_id, credit_limit, payment_terms | `CUST-000001` |
| **Vendor** | vendor_nameâœ¦, vendor_type, emailâœ¦, category, payment_terms, tax_id, certifications | `VEND-000001` |
| **Product** | product_nameâœ¦, sku, barcode, uomâœ¦, unit_price, manufacturer, category | `PROD-000001` |
| **Material** | material_nameâœ¦, material_typeâœ¦, uomâœ¦, min_stock, max_stock, hazardous | `MATL-000001` |
| **Account** | account_nameâœ¦, account_typeâœ¦, account_number, currency, parent_account | `ACCT-000001` |
| **Employee** | first_nameâœ¦, last_nameâœ¦, work_emailâœ¦, department, job_title, hire_date | `EMP-000001` |
| **Location** | location_nameâœ¦, location_typeâœ¦, street, city, state, country, timezone | `LOC-000001` |
| **Organization** | legal_nameâœ¦, org_type, tax_id, parent_org, country | `ORG-000001` |
| **Asset** | asset_nameâœ¦, asset_type, serial_number, purchase_date, location | `ASST-000001` |

âœ¦ = Required field

---

## Appendix B: Service â†’ Database Access Map

| Service | Reads From | Writes To | Via |
|---------|-----------|----------|-----|
| mdm-core | core_mdm.*, event_store | core_mdm.*, event_store.outbox_events | Direct (owns migrations) |
| ai-service | core_mdm.entities, ai.* | ai.*, event_store.outbox_events (indirect) | Direct |
| ingest-service | â€” | core_mdm.entities (via mdm-core REST) | HTTP proxy |
| policy-service | governance.policy_rules, core_mdm.entities | audit.gdpr_requests, governance.* | Direct |
| search-service | core_mdm.entities, ai.entity_embeddings | â€” | Read-only |
| tenant-service | core_mdm.*, platform.licenses | core_mdm.tenants, platform.licenses, core_mdm.entity_sequences | Direct |
| enrichment-service | core_mdm.entities (via Kafka events) | ai.entity_enrichments, core_mdm.entities (via mdm-core PATCH) | HTTP proxy |
| distribution-service | platform.distribution_* | platform.distribution_jobs | Direct |
| notification-service | â€” | platform.notifications | Via Redis pub/sub |
| kafka-event-service | event_store.outbox_events | event_store.outbox_events (status update), event_store.outbox_dlq | Direct |

---

*Document generated from Azile AI MDM codebase â€” reflects implementation as of Sprint 6.*  
*For API documentation, see `docs/openapi.yaml`. For deployment, see `infra/README.md`.*
