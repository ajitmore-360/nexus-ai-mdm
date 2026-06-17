# Nexus AI MDM — Full Dry-Run Guide

A complete end-to-end walkthrough of every module in the system, with sample
payloads, exact API calls, Kafka events, and final database rows for each
scenario. Use this as both a developer handbook and a QA acceptance checklist.

---

## Contents

1. [System Map](#1-system-map)
2. [Authentication Module](#2-authentication-module)
3. [Entity Create Module](#3-entity-create-module)
4. [Entity Edit Module](#4-entity-edit-module)
5. [Batch Ingest Module](#5-batch-ingest-module)
6. [Duplicate Match Module](#6-duplicate-match-module)
7. [Survivorship & Merge Module](#7-survivorship--merge-module)
8. [AI Copilot Module](#8-ai-copilot-module)
9. [Distribution Module](#9-distribution-module)
10. [GDPR Erasure Module](#10-gdpr-erasure-module)
11. [End-to-End Flow: Full Customer Lifecycle](#11-end-to-end-flow-full-customer-lifecycle)
12. [Database Storage Reference](#12-database-storage-reference)

---

## 1. System Map

```
Browser / Flutter UI (localhost:4000)
            │
            │  HTTP/REST + WebSocket
            ▼
    ┌─────────────────────────────────────────┐
    │         API Gateway  :8080              │
    │  auth_middleware → tenant_middleware    │
    │  rate_limit_middleware → cors           │
    └───────────────────┬─────────────────────┘
                        │
          ┌─────────────┼─────────────────┐
          ▼             ▼                 ▼
    mdm-core:8081  ai-service:8082  other services
    PostgreSQL 16   Ollama LLM       (see below)
    Redis 7         pgvector
    Kafka outbox
          │
    Kafka topics (published by kafka-event-service)
    ├─ mdm.entity.events
    ├─ mdm.golden.events
    ├─ mdm.entity.distribution
    └─ mdm.match.events
          │
    Consumers
    ├─ enrichment-service  — D&B / Experian API calls
    ├─ search-service:8085 — FTS + vector indexing
    ├─ distribution-service:8089 — Salesforce / SAP / webhooks
    ├─ notification-service:8086 — WebSocket push alerts
    └─ audit-service       — immutable log writes

Other services:
  ingest-service:8083   — CSV / REST batch ingest
  policy-service:8084   — OPA Rego evaluation, GDPR
  tenant-service:8090   — license management
```

**Multi-tenancy**: every table carries `tenant_id`. PostgreSQL RLS enforces
isolation via `app.current_tenant` session variable set at the start of every
transaction.

**Bitemporal**: entities track `valid_from`/`valid_to` (business time) and
`recorded_at` (system time).

---

## 2. Authentication Module

### 2.1 Login

**Endpoint**: `POST /auth/login`

**Request**:
```json
{
  "email": "steward@acmecorp.com",
  "password": "S3cur3P@ss!",
  "tenant_id": "a1b2c3d4-0000-0000-0000-000000000001"
}
```

**What happens inside api-gateway**:
1. Looks up user in `core_mdm.users` by email + tenant_id.
2. Verifies bcrypt password hash.
3. Signs two JWTs (RS256):
   - `access_token` — expires in 900 s (15 min), contains `{ sub, nxs_tenant_id, role }`.
   - `refresh_token` — expires in 604 800 s (7 days).
4. Stores refresh token in Redis: `session:{tenant_id}:{user_id}`.

**Response**:
```json
{
  "access_token": "eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJ1c2VyX…",
  "refresh_token": "eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJ1c2VyX…",
  "token_type": "Bearer",
  "expires_in": 900
}
```

**Every subsequent request must include**:
```
Authorization: Bearer <access_token>
x-tenant-id: a1b2c3d4-0000-0000-0000-000000000001
```

### 2.2 Token Refresh

**Endpoint**: `POST /auth/refresh`
```json
{ "refresh_token": "eyJhbGciOiJSUzI1NiJ9…" }
```
Returns a fresh `access_token` with a new 15-minute window.

### 2.3 Development Mode

When `AUTH_DISABLED=true` in `.env`, the auth middleware is bypassed and a
synthetic tenant token is issued for `tenant_id = 00000000-0000-0000-0000-000000000000`.
**This is blocked at startup if `APP_ENV=production`.**

---

## 3. Entity Create Module

### 3.1 Scenario: Create a new Customer from the UI

A data steward opens **Entity Explorer → New Entity**, fills the form, and
clicks **Save**.

#### Step 1 — Flutter UI builds the payload

The `EntityCreatePage` collects:
- **Entity Type**: `Customer`
- **Predefined attributes** (shown as read-only labels): `legal_name`, `email`, `phone`, `tax_id`
- **Custom attributes** added by the steward: any extra key/value pairs

`EntityRepository.createEntity()` sends:
```json
POST /entities
Authorization: Bearer <token>
x-tenant-id: a1b2c3d4-0000-0000-0000-000000000001

{
  "entity": {
    "entity_id": "00000000-0000-0000-0000-000000000000",
    "tenant_id": "a1b2c3d4-0000-0000-0000-000000000001",
    "entity_type": "Customer",
    "external_ids": {},
    "status": "Active",
    "attributes": [
      {
        "attribute_id": "00000000-0000-0000-0000-000000000000",
        "key": "legal_name",
        "value": "Acme Corporation",
        "data_type": "string",
        "searchable": true,
        "indexed": true,
        "encrypted": false,
        "survivorship_eligible": true,
        "attribute_version": 1
      },
      {
        "attribute_id": "00000000-0000-0000-0000-000000000000",
        "key": "email",
        "value": "billing@acme.com",
        "data_type": "email",
        "searchable": true,
        "indexed": true,
        "encrypted": false,
        "survivorship_eligible": true,
        "attribute_version": 1
      },
      {
        "attribute_id": "00000000-0000-0000-0000-000000000000",
        "key": "phone",
        "value": "+14155550123",
        "data_type": "phone",
        "searchable": true,
        "indexed": true,
        "encrypted": false,
        "survivorship_eligible": true,
        "attribute_version": 1
      },
      {
        "attribute_id": "00000000-0000-0000-0000-000000000000",
        "key": "tax_id",
        "value": "12-3456789",
        "data_type": "string",
        "searchable": false,
        "indexed": false,
        "encrypted": true,
        "survivorship_eligible": true,
        "attribute_version": 1
      }
    ],
    "relationships": [],
    "source_snapshots": [],
    "tags": [],
    "trust_score": 1.0,
    "valid_from": "2026-06-17T00:00:00Z",
    "valid_to": null
  },
  "record_origin": "mdm_authoritative",
  "distribute": false,
  "distribution_targets": []
}
```

#### Step 2 — API Gateway middleware

1. `request_id_middleware` — attaches `X-Request-Id: req_7f3a…` for tracing.
2. `tenant_middleware` — reads `x-tenant-id` header, verifies it equals `nxs_tenant_id` claim in the JWT. Returns **400** if header is missing, **403** if mismatch.
3. `auth_middleware` — validates JWT signature + expiry.
4. `rate_limit_middleware` — checks token-bucket per user; returns **429** if exceeded.
5. Proxies request to `mdm-core:8081/entities`.

#### Step 3 — MDM Core transaction

```sql
-- begin_uow sets RLS context
SET app.current_tenant = 'a1b2c3d4-0000-0000-0000-000000000001';

BEGIN;

-- 1. Insert entity header
INSERT INTO core_mdm.entities (
  entity_id, tenant_id, entity_type_id, entity_code,
  status, source_system, trust_score, metadata,
  created_at, updated_at
) VALUES (
  'f47ac10b-58cc-4372-a567-0e02b2c3d479',   -- new UUID assigned
  'a1b2c3d4-0000-0000-0000-000000000001',
  (SELECT entity_type_id FROM core_mdm.entity_types
   WHERE tenant_id = 'a1b2…' AND entity_name = 'Customer'),
  'CUST-00001',                               -- next_entity_number()
  'ACTIVE',
  'mdm_ui',
  1.0,
  '{}',
  NOW(), NOW()
);

-- 2. Insert attributes (one row per attribute)
INSERT INTO core_mdm.entity_attributes
  (attribute_id, tenant_id, entity_id, attribute_name, attribute_value,
   data_type, confidence_score, source_system, created_at)
VALUES
  (gen_random_uuid(), 'a1b2…', 'f47a…', 'legal_name',  '"Acme Corporation"', 'string', 1.0, 'mdm_ui', NOW()),
  (gen_random_uuid(), 'a1b2…', 'f47a…', 'email',        '"billing@acme.com"', 'email',  1.0, 'mdm_ui', NOW()),
  (gen_random_uuid(), 'a1b2…', 'f47a…', 'phone',        '"+14155550123"',     'phone',  1.0, 'mdm_ui', NOW()),
  (gen_random_uuid(), 'a1b2…', 'f47a…', 'tax_id',       '"12-3456789"',       'string', 1.0, 'mdm_ui', NOW());

-- 3. Insert outbox event (same transaction — atomicity guarantee)
INSERT INTO event_store.outbox_events (
  event_id, tenant_id, aggregate_type, aggregate_id,
  event_type, event_version, event_payload,
  topic_name, partition_key,
  published, created_at
) VALUES (
  gen_random_uuid(),
  'a1b2c3d4-0000-0000-0000-000000000001',
  'entity',
  'f47ac10b-58cc-4372-a567-0e02b2c3d479',
  'EntityCreated',
  1,
  '{"entity_id":"f47a…","entity_type":"Customer","attributes":[…],"record_origin":"mdm_authoritative","tenant_id":"a1b2…"}',
  'mdm.entity.events',
  'a1b2c3d4-0000-0000-0000-000000000001',   -- partition by tenant
  false,
  NOW()
);

COMMIT;
```

#### Step 4 — Response to UI

```json
{
  "success": true,
  "data": {
    "entity_id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
    "entity_code": "CUST-00001",
    "outbox_event_ids": ["e1234567-…"]
  }
}
```

`EntityCreatePage` receives `Success<CreateEntityResponse>`, shows a snackbar
**"Entity created successfully"**, and calls `context.pop(true)` which returns
to `EntityExplorerPage` and triggers `_loadEntities()`.

#### Step 5 — Async post-commit processing

**kafka-event-service** polls every 5 seconds:
```sql
SELECT * FROM event_store.outbox_events
WHERE published = false
ORDER BY created_at ASC
LIMIT 100
FOR UPDATE SKIP LOCKED;
```
Publishes `EntityCreated` event to Kafka topic `mdm.entity.events`.
Updates `outbox_events SET published = true, published_at = NOW()`.

**Consumers** (independent, parallel):
- `search-service` — indexes entity text + generates embedding via `ai-service`.
- `enrichment-service` — calls D&B/Experian to fill missing attributes.
- `notification-service` — pushes WebSocket alert to all connected stewards in that tenant.
- `audit-service` — copies event to `event_store.event_log` (immutable).

#### Final database state after entity create:

```
core_mdm.entities
──────────────────────────────────────────────────────────────────────────────
entity_id  | f47ac10b-58cc-4372-a567-0e02b2c3d479
tenant_id  | a1b2c3d4-0000-0000-0000-000000000001
entity_code| CUST-00001
status     | ACTIVE
trust_score| 1.0
created_at | 2026-06-17 09:42:11Z

core_mdm.entity_attributes (4 rows)
──────────────────────────────────────────────────────────────────────────────
attribute_name | attribute_value       | data_type | confidence_score
legal_name     | "Acme Corporation"    | string    | 1.0
email          | "billing@acme.com"    | email     | 1.0
phone          | "+14155550123"        | phone     | 1.0
tax_id         | "12-3456789"          | string    | 1.0

event_store.outbox_events (1 row)
──────────────────────────────────────────────────────────────────────────────
event_type | EntityCreated
published  | true  (after kafka-event-service processes)
topic_name | mdm.entity.events

ai.entity_embeddings (1 row, written by search-service after consume)
──────────────────────────────────────────────────────────────────────────────
entity_id       | f47ac10b-…
embedding_model | nomic-embed-text
embedding       | [0.023, -0.144, 0.871, …]  (768 dimensions)
```

---

## 4. Entity Edit Module

### 4.1 Scenario: Update phone number on existing Customer

**Endpoint**: `PATCH /entities/f47ac10b-58cc-4372-a567-0e02b2c3d479`

```json
{
  "entity_type": "Customer",
  "status": "Active",
  "attributes": [
    { "key": "phone", "value": "+14155559999", "data_type": "phone" }
  ]
}
```

**What changes in the DB**:
```sql
-- mdm-core updates only the supplied attributes
UPDATE core_mdm.entity_attributes
SET attribute_value = '"+14155559999"',
    confidence_score = 1.0
WHERE entity_id = 'f47a…'
  AND tenant_id = 'a1b2…'
  AND attribute_name = 'phone';

UPDATE core_mdm.entities
SET updated_at = NOW()
WHERE entity_id = 'f47a…' AND tenant_id = 'a1b2…';

-- Outbox event (same transaction)
INSERT INTO event_store.outbox_events (event_type, …)
VALUES ('EntityUpdated', '{"entity_id":"f47a…","changes":[{"attr":"phone","old_val":"+14155550123","new_val":"+14155559999"}]}', …);
```

**Redis cache** for `entity:f47a…` is invalidated immediately.

---

## 5. Batch Ingest Module

### 5.1 Scenario: Ingest 500 Customers from Salesforce CSV

**Endpoint**: `POST /ingest/csv`  
Content-Type: `multipart/form-data`

Fields:
- `file`: customers.csv
- `entity_type`: `Customer`
- `mappings`: `{"Company":"legal_name","Email Address":"email","Phone":"phone","Tax ID":"tax_id"}`

**Sample CSV rows**:
```
Company,Email Address,Phone,Tax ID
Acme Corp,billing@acme.com,+14155550100,12-0000001
Beta Ltd,info@beta.com,+14155550200,12-0000002
```

**ingest-service processing**:
1. Parses CSV into 500 entity objects.
2. Applies `SchemaMapper` — maps `"Company"` → `"legal_name"`, etc.
3. Normalises values — email to lowercase, phone to E.164 format.
4. POSTs each entity to `mdm-core POST /entities` in batches of 50 (configurable).
5. Returns:
```json
{
  "batch_id": "b9e12a3b-…",
  "succeeded": 498,
  "failed": 2,
  "errors": [
    { "row": 47, "error": "invalid email format: not_an_email" },
    { "row": 213, "error": "duplicate tax_id detected" }
  ]
}
```

**For each successfully ingested entity**, the same flow as Section 3 applies:
INSERT into `core_mdm.entities` + `core_mdm.entity_attributes` + outbox event,
then Kafka consumers process asynchronously.

`record_origin` is set to `"ingested"` (not `"mdm_authoritative"`) to indicate
this entity came from an external source.

---

## 6. Duplicate Match Module

### 6.1 Scenario: Match a newly ingested Customer against existing records

**Endpoint**: `POST /match`

```json
{
  "request_id": "00000000-0000-0000-0000-000000000000",
  "tenant_id": "a1b2c3d4-0000-0000-0000-000000000001",
  "entity_type": "Customer",
  "entity": {
    "entity_id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
    "entity_type": "Customer",
    "attributes": [
      { "key": "legal_name", "value": "ACME CORPORATION", "data_type": "string" },
      { "key": "email",      "value": "billing@acme.com", "data_type": "email" },
      { "key": "tax_id",     "value": "12-3456789",       "data_type": "string" }
    ]
  },
  "threshold": 0.75,
  "strategy": "Hybrid",
  "ai_assisted": true,
  "explainability_enabled": true,
  "semantic_matching": true,
  "graph_matching": false,
  "max_candidates": 50
}
```

### 6.2 Stage 1 — Blocking (candidate reduction)

Four parallel blockers reduce the search space:

| Blocker | SQL/Action | Candidates found |
|---------|-----------|-----------------|
| ExactBlocker | `WHERE attribute_name='email' AND attribute_value='"billing@acme.com"'` | entity_id: c1a2… |
| PhoneticBlocker | `WHERE attribute_name='name' AND lower(value) LIKE '%acme%'` | entity_id: c1a2…, c3b4… |
| CanopyBlocker | Tokenise → `ILIKE ANY(['acme','corporation'])` | entity_id: c1a2…, c5d6… |
| VectorBlocker | `ORDER BY embedding <=> $query_embed::vector LIMIT 200` | entity_id: c1a2…, c3b4…, c7e8… |

Union of all blockers: `{c1a2…, c3b4…, c5d6…, c7e8…}` — 4 candidates from potentially millions.

### 6.3 Stage 2 — Field-level scoring

For each candidate, the engine compares field by field:

**Source entity "ACME CORPORATION" vs Candidate "Acme Corp" (entity c1a2…)**:

| Field | Source value | Candidate value | Exact | Fuzzy (JW+Lev) | Phonetic | Semantic | Field Score |
|-------|-------------|----------------|-------|----------------|----------|----------|-------------|
| legal_name | ACME CORPORATION | Acme Corp | 0.0 | 0.78 | 1.0 (soundex match) | 0.92 | 0.74 |
| email | billing@acme.com | billing@acme.com | 1.0 | 1.0 | — | 1.0 | 1.0 |
| tax_id | 12-3456789 | 12-3456789 | 1.0 | 1.0 | — | 1.0 | 1.0 |

```
field_score = (0.35 × exact) + (0.30 × fuzzy) + (0.10 × phonetic) + (0.25 × semantic)
legal_name  = (0.35×0.0) + (0.30×0.78) + (0.10×1.0) + (0.25×0.92) = 0.00 + 0.23 + 0.10 + 0.23 = 0.574 ... 
              → weighted up by email/tax_id exact matches
overall_score = 0.94   (aggregate across all fields weighted by field coverage)
confidence    = (0.94 × 0.80) + (field_coverage:1.0 × 0.20) = 0.952
```

**Score ≥ 0.95 → AUTO_MERGE recommended** (no human review required).

For grey-zone (0.75 ≤ score < 0.95), AI scoring is triggered:

```
POST ai-service /match/semantic
{
  "entity_a": { "legal_name": "ACME CORPORATION", "tax_id": "12-3456789" },
  "entity_b": { "legal_name": "Acme Corp",        "tax_id": "12-3456789" }
}
→ Ollama llama3.2:3b: "Compare these two entities. Are they the same? Reply match or no_match with confidence."
→ Response: { "decision": "match", "ai_score": 0.97 }
```

### 6.4 Stage 3 — Clustering

```
Graph nodes: {source, c1a2, c3b4, c5d6}
Edges (score ≥ 0.75):
  source → c1a2: 0.94
  source → c3b4: 0.82

Connected component: {source, c1a2, c3b4}
master_score = avg_match × 0.50 + avg_confidence × 0.30 + centrality × 0.20
  c1a2: 0.94×0.5 + 0.95×0.3 + 0.66×0.2 = 0.47 + 0.285 + 0.132 = 0.887  ← suggested master
```

### 6.5 Database writes during matching

```sql
INSERT INTO core_mdm.match_requests (
  request_id, tenant_id, entity_type, source_entity_id,
  strategy, threshold, ai_assisted, status, …
) VALUES ('req-uuid-…', 'a1b2…', 'Customer', 'f47a…', 'Hybrid', 0.75, true, 'Completed', …);

INSERT INTO core_mdm.match_candidates (
  match_candidate_id, request_id, source_entity_id, matched_entity_id,
  match_status, match_score, confidence_score, ai_score,
  recommended_for_merge, requires_human_review, auto_approved, …
) VALUES
  ('cand-1…', 'req-uuid', 'f47a…', 'c1a2…', 'Matched', 0.94, 0.95, 0.97, true, false, true, …),
  ('cand-2…', 'req-uuid', 'f47a…', 'c3b4…', 'RequiresReview', 0.82, 0.85, null, false, true, false, …);

-- Per-field detail for audit/explanation
INSERT INTO core_mdm.field_match_results (field_name, score, strategy, algorithm, …)
VALUES
  ('legal_name', 0.74, 'Fuzzy',   'Jaro-Winkler', …),
  ('email',      1.00, 'Exact',   'Exact',         …),
  ('tax_id',     1.00, 'Exact',   'Exact',         …);

-- Human review queue for the grey-zone candidate
INSERT INTO core_mdm.match_review_queue (
  review_id, tenant_id, request_id, match_candidate_id,
  review_status, priority
) VALUES (gen_random_uuid(), 'a1b2…', 'req-uuid', 'cand-2…', 'Pending', 3);
```

### 6.6 Match response

```json
{
  "request_id": "req-uuid-…",
  "matches": [
    {
      "entity_id": "c1a2…",
      "status": "Matched",
      "score": 0.94,
      "confidence": 0.95,
      "ai_score": 0.97,
      "recommended_for_merge": true,
      "requires_human_review": false,
      "auto_approved": true,
      "explanations": [
        "email exact match: billing@acme.com",
        "tax_id exact match: 12-3456789",
        "legal_name fuzzy similarity 0.78 + phonetic match"
      ]
    },
    {
      "entity_id": "c3b4…",
      "status": "RequiresReview",
      "score": 0.82,
      "confidence": 0.85,
      "recommended_for_merge": false,
      "requires_human_review": true,
      "explanations": ["legal_name partial match", "no email overlap"]
    }
  ],
  "clusters": [
    {
      "cluster_id": "clus-1…",
      "entity_ids": ["f47a…","c1a2…","c3b4…"],
      "confidence": 0.88,
      "suggested_master": "c1a2…"
    }
  ]
}
```

---

## 7. Survivorship & Merge Module

### 7.1 Scenario: Merge auto-approved pair (score ≥ 0.95)

**Endpoint**: `POST /merge` (or triggered automatically)

**Input**: source entity `f47a…` + matched entity `c1a2…` (the suggested master).

**Step 1 — Load survivorship rules** (from `core_mdm.survivorship_rules`):

| Attribute | Strategy | Priority sources |
|-----------|----------|-----------------|
| legal_name | TrustedSource | salesforce (0.90) > sap (0.60) > d&b (0.80) |
| email | TrustedSource | salesforce (1.00) |
| tax_id | HighestConfidence | — |
| updated_at | MostRecent | — |

**Step 2 — Evaluate each attribute**:

| Attribute | Source A value | Source B value | Winner | Rule | Confidence |
|-----------|---------------|----------------|--------|------|-----------|
| legal_name | "Acme Corporation" (mdm_ui, trust=1.0) | "ACME Corp" (salesforce, trust=0.94) | "ACME Corp" | TrustedSource (Salesforce wins) | 0.94 |
| email | "billing@acme.com" (both identical) | same | "billing@acme.com" | TrustedSource | 1.0 |
| tax_id | "12-3456789" (both identical) | same | "12-3456789" | HighestConfidence | 1.0 |

**Step 3 — Single ACID transaction**:

```sql
BEGIN;

-- Create golden record
INSERT INTO core_mdm.golden_records (
  golden_record_id, tenant_id, entity_type_id,
  status, survivorship_score, ai_validated, metadata, created_at
) VALUES (
  'gold-uuid-…',
  'a1b2c3d4-0000-0000-0000-000000000001',
  (SELECT entity_type_id WHERE entity_name='Customer'),
  'ACTIVE',
  0.96,
  true,
  '{
    "legal_name":  {"value":"ACME Corp",          "source":"salesforce","rule":"TrustedSource","confidence":0.94},
    "email":       {"value":"billing@acme.com",   "source":"salesforce","rule":"TrustedSource","confidence":1.00},
    "tax_id":      {"value":"12-3456789",         "source":"mdm_ui",   "rule":"HighestConfidence","confidence":1.00}
  }',
  NOW()
);

-- Mark both source entities as Merged
UPDATE core_mdm.entities
SET status = 'MERGED', golden_record_id = 'gold-uuid-…', updated_at = NOW()
WHERE entity_id IN ('f47a…', 'c1a2…') AND tenant_id = 'a1b2…';

-- Per-attribute decision log
INSERT INTO core_mdm.survivorship_field_decisions (execution_id, field_name, selected_entity_id, selected_value, strategy, confidence_score, explanation)
VALUES
  ('exec-uuid', 'legal_name', 'c1a2…', '"ACME Corp"',        'TrustedSource',    0.94, 'Salesforce source weight 0.94 > mdm_ui 1.0'),
  ('exec-uuid', 'email',      'c1a2…', '"billing@acme.com"', 'TrustedSource',    1.00, 'Single authoritative source'),
  ('exec-uuid', 'tax_id',     'f47a…', '"12-3456789"',       'HighestConfidence',1.00, 'Equal confidence, first source wins');

-- Outbox events (same transaction)
INSERT INTO event_store.outbox_events (event_type, aggregate_id, topic_name, event_payload, …)
VALUES
  ('GoldenRecordCreated', 'gold-uuid-…', 'mdm.golden.events', '{"golden_id":"gold-uuid-…","source_ids":["f47a…","c1a2…"],"survivorship_score":0.96}', …),
  ('EntityMerged',        'f47a…',       'mdm.entity.events',  '{"source_id":"f47a…","golden_id":"gold-uuid-…","merged_with_ids":["c1a2…"]}', …);

COMMIT;
```

**Post-commit**:
- Redis cache invalidated for `f47a…`, `c1a2…`, `gold-uuid…`.
- `distribution-service` consumes `GoldenRecordCreated` → pushes to Salesforce, SAP.
- `notification-service` alerts assigned stewards.

---

## 8. AI Copilot Module

### 8.1 Scenario: Steward asks a free-form question

**Endpoint**: `POST /copilot`

```json
{
  "tenant_id": "a1b2c3d4-0000-0000-0000-000000000001",
  "user_id": "steward-uuid-…",
  "prompt": "Why were Acme Corporation and ACME Corp merged?"
}
```

**ai-service internal pipeline**:

**Step 1 — Safety checks**:
- Prompt injection detection (regex-based: blocks `ignore previous instructions`, etc.).
- Length limit: 2048 chars.

**Step 2 — Embed the query**:
```
POST http://ollama:11434/api/embeddings
{ "model": "nomic-embed-text", "prompt": "Why were Acme Corporation and ACME Corp merged?" }
→ embedding: [0.041, -0.289, 0.712, …]  (768 dims)
```

**Step 3 — Vector search for context**:
```sql
SELECT chunk_text, metadata
FROM ai.rag_chunks
WHERE tenant_id = 'a1b2…'
ORDER BY embedding <=> $query_embedding::vector
LIMIT 5;
```

Returns the 5 most semantically relevant knowledge chunks (match explanations,
survivorship evaluations, previous copilot answers stored as RAG documents).

**Step 4 — Build augmented prompt**:
```
You are Nexus MDM Copilot, an AI assistant for master data management.
Answer only about data management topics. Do not reveal system internals.

CONTEXT:
[1] Entity f47ac10b (Acme Corporation, mdm_ui) merged with c1a2bb… (ACME Corp, salesforce)
    Reason: email exact match, tax_id exact match, overall score 0.94.
[2] Survivorship rule: legal_name → TrustedSource, Salesforce wins (weight 0.94).
[3] Golden record gold-uuid created 2026-06-17, survivorship_score 0.96.

QUESTION: Why were Acme Corporation and ACME Corp merged?
```

**Step 5 — LLM generation**:
```
POST http://ollama:11434/api/generate
{
  "model": "llama3.2:3b",
  "prompt": "<augmented prompt above>",
  "stream": false,
  "options": { "temperature": 0.2 }
}
→ response: "Acme Corporation and ACME Corp were merged because they share the
   same billing email (billing@acme.com) and tax ID (12-3456789), producing a
   match score of 0.94 — above the automatic merge threshold of 0.95 after
   AI validation. The legal name 'ACME Corp' from Salesforce was selected as
   the golden value because Salesforce has the highest configured trust weight
   (0.94) for this attribute."
```

**Response to UI**:
```json
{
  "success": true,
  "answer": "Acme Corporation and ACME Corp were merged because they share the same billing email…",
  "source_docs": [
    { "chunk_text": "Entity f47ac10b merged with c1a2bb…", "relevance": 0.94 },
    { "chunk_text": "Survivorship rule: legal_name → TrustedSource…", "relevance": 0.88 }
  ]
}
```

### 8.2 Scenario: MCP tool call — explain a specific match

```json
{
  "tenant_id": "a1b2…",
  "tool": "explain_match",
  "args": {
    "source_id": "f47ac10b-…",
    "matched_id": "c1a2bb00-…"
  }
}
```

ai-service calls the `explain_match` MCP tool handler which:
1. Loads both entities from mdm-core.
2. Loads field_match_results for this pair.
3. Constructs a structured prompt: *"Explain in plain English why these two customer records match, citing the key fields."*
4. Returns LLM-generated plain-English explanation.

### 8.3 Anomaly detection

```json
{
  "tenant_id": "a1b2…",
  "tool": "detect_anomalies",
  "args": { "entity_type": "Customer" }
}
```

The `AnomalyDetector` runs statistical checks:
- **Duplicate detection** — entities with identical email/phone but different entity_ids.
- **Outlier detection** — attribute values more than 3σ from the mean (e.g. suspiciously long `legal_name`).
- **Pattern violation** — phone numbers not in E.164 format, emails without `@`.

Results written to `ai.anomalies` and returned in the response.

---

## 9. Distribution Module

### 9.1 Scenario: Push golden record to Salesforce after merge

Triggered by `GoldenRecordCreated` Kafka event consumed by `distribution-service`.

**distribution-service**:
1. Loads golden record `gold-uuid-…` from mdm-core.
2. For each configured target (`Salesforce`, `SAP`):

   ```
   Target: Salesforce (delivery_mode: push)
   ├── Format entity per Salesforce schema
   │   { "Name": "ACME Corp", "Email__c": "billing@acme.com", … }
   ├── POST https://salesforce.com/api/…
   ├── On success: INSERT platform.distribution_jobs (status='succeeded')
   └── On failure: INSERT platform.distribution_jobs (status='failed', retry_count=1)
                   (retry with exponential backoff up to 3 attempts)
   ```

3. Emits `DistributionCompleted` event.

**Manual distribution** (from UI):

`POST /distribution/jobs`
```json
{
  "entity_id": "gold-uuid-…",
  "targets": [
    { "connector_id": "salesforce-prod", "target_system": "Salesforce", "delivery_mode": "push" }
  ]
}
```

**Retry failed jobs**:

`POST /distribution-jobs/{id}/retry`
— Re-queues the job; resets retry_count.

---

## 10. GDPR Erasure Module

### 10.1 Scenario: Data subject requests deletion

**Endpoint**: `POST /policy/gdpr/erasure`

```json
{
  "subject_id": "data-subject-uuid-…",
  "reason": "User requested account deletion under GDPR Art. 17"
}
```

**policy-service flow**:
1. Finds all entities where `metadata->>'subject_id' = 'data-subject-uuid-…'`.
2. For each entity:
   - `UPDATE core_mdm.entity_attributes SET attribute_value = '"ERASED"' WHERE entity_id = …` (PII fields).
   - Clears `metadata` JSONB.
   - `DELETE FROM ai.entity_embeddings WHERE entity_id = …`.
   - `DELETE FROM ai.rag_chunks WHERE entity_id = …`.
   - `DELETE FROM ai.steward_feedback WHERE source_entity_id = …`.
   - `UPDATE core_mdm.entities SET status = 'SoftDeleted', valid_to = NOW()`.
3. `INSERT INTO audit.gdpr_requests (subject_id, request_type='erasure', status='completed', fields_erased=N, …)`.

**Response**:
```json
{
  "subject_id": "data-subject-uuid-…",
  "fields_erased": 12,
  "records_affected": 3,
  "audit_id": "audit-uuid-…",
  "completed_at": "2026-06-17T11:00:00Z"
}
```

The audit record in `audit.gdpr_requests` is **immutable** — it persists even
after the data is erased to demonstrate compliance.

---

## 11. End-to-End Flow: Full Customer Lifecycle

```
Day 1 — Steward creates Acme Corporation manually in the UI
│  → core_mdm.entities row (CUST-00001, status=ACTIVE)
│  → 4 attribute rows in core_mdm.entity_attributes
│  → outbox event EntityCreated (published → search indexes + embeddings)
│
Day 2 — Salesforce batch ingest CSV with "ACME Corp"
│  → core_mdm.entities row (CUST-00002, status=ACTIVE, source_system=salesforce)
│  → 4 attribute rows (legal_name="ACME Corp", same email+tax_id)
│  → outbox event EntityCreated
│
Day 3 — Nightly matching job runs
│  → POST /match (Hybrid strategy, ai_assisted=true)
│  → Blocking: ExactBlocker finds email match immediately
│  → Scoring: overall_score=0.94, ai_score=0.97 → AUTO_MERGE
│  → core_mdm.match_requests row (status=Completed)
│  → core_mdm.match_candidates row (Matched, auto_approved=true)
│  → core_mdm.field_match_results rows (per-field detail)
│  → Outbox event MatchApproved
│
Day 3 (continued) — Survivorship executes
│  → legal_name = "ACME Corp" (Salesforce wins, TrustedSource)
│  → email = "billing@acme.com" (both identical)
│  → tax_id = "12-3456789" (HighestConfidence, same value)
│  → core_mdm.golden_records row (gold-uuid, status=ACTIVE, score=0.96)
│  → Both source entities status → MERGED
│  → core_mdm.survivorship_field_decisions rows
│  → Outbox events: GoldenRecordCreated + EntityMerged
│
Day 3 (async) — Distribution
│  → distribution-service consumes GoldenRecordCreated
│  → Pushes "ACME Corp" to Salesforce (upsert)
│  → platform.distribution_jobs row (status=succeeded)
│
Day 4 — Steward asks copilot: "Why were these merged?"
│  → ai-service embeds query → vector search → RAG context
│  → Ollama generates plain-English explanation
│  → Copilot answer returned with source_docs citations
│
Day 90 — GDPR erasure request from data subject
   → PII attributes → "ERASED"
   → ai.entity_embeddings deleted
   → ai.rag_chunks deleted
   → core_mdm.entities status → SoftDeleted
   → audit.gdpr_requests row (immutable compliance record)
```

---

## 12. Database Storage Reference

### Complete table inventory by schema

#### core_mdm (primary MDM data)

| Table | Purpose | Key columns |
|-------|---------|-------------|
| `tenants` | Tenant registry | tenant_id, tenant_code, status, subscription_plan |
| `entity_types` | Supported entity kinds | entity_name (Customer/Vendor/Product…), ai_enabled, rag_enabled |
| `attribute_definitions` | Schema definitions per entity type | attribute_name, data_type, required, pii, vectorizable |
| `entities` | Master entity record | entity_id, entity_code, status, trust_score, source_system |
| `entity_attributes` | EAV attribute store | attribute_name, attribute_value (JSONB), confidence_score, vector_embedding |
| `golden_records` | Merge output | survivorship_score, ai_validated, golden_attributes (JSONB) |
| `match_requests` | Matching execution log | strategy, threshold, ai_assisted, execution_time_ms |
| `match_candidates` | Per-pair scores | match_score, confidence_score, ai_score, recommended_for_merge |
| `field_match_results` | Per-field comparison detail | field_name, score, strategy, algorithm, semantic_similarity |
| `match_clusters` | Entity groupings | entity_ids (JSONB array), suggested_master |
| `match_review_queue` | Human steward workflow | review_status, priority, assigned_to, reviewed_at |
| `survivorship_rules` | Business merge logic | attribute_name, strategy, source_priority, source_weights |
| `survivorship_executions` | Merge run log | overall_confidence, ai_assisted, execution_time_ms |
| `survivorship_evaluations` | Per-attribute decision | selected_value, selected_source, reasoning |
| `survivorship_field_decisions` | Atomic merge decisions | field_name, selected_entity_id, confidence_score, explanation |

#### event_store (event sourcing)

| Table | Purpose |
|-------|---------|
| `outbox_events` | Transactional outbox — pending Kafka publishes |
| `event_log` | Immutable partitioned audit log (monthly partitions) |
| `dead_letter_events` | Failed events after 3 retry attempts |
| `consumer_offsets` | Kafka partition offset tracking per consumer group |

#### ai (vector/LLM)

| Table | Purpose |
|-------|---------|
| `entity_embeddings` | 768-dim pgvector embeddings per entity (nomic-embed-text) |
| `rag_chunks` | Knowledge base text segments with 1536-dim embeddings |
| `steward_feedback` | Human match decisions for adaptive weight tuning |
| `anomalies` | Detected data quality issues (duplicate/outlier/pattern violation) |

#### governance

| Table | Purpose |
|-------|---------|
| `policy_rules` | OPA Rego policy definitions per tenant |

#### platform

| Table | Purpose |
|-------|---------|
| `licenses` | JWT-signed license tokens (tier, features, expiry) |
| `notifications` | User alert messages (match_available, review_queue, etc.) |
| `distribution_jobs` | Downstream delivery tracking (Salesforce, SAP, webhook) |

#### audit

| Table | Purpose |
|-------|---------|
| `gdpr_requests` | GDPR access/erasure/portability compliance records |

---

### Entity lifecycle status transitions

```
DRAFT → ACTIVE → PENDING_REVIEW → UNDER_INVESTIGATION → MERGED
                                                       → ARCHIVED
                                                       → SOFT_DELETED
```

### Kafka topic → consumer group mapping

| Topic | Producer | Consumer Groups |
|-------|---------|----------------|
| `mdm.entity.events` | mdm-core (via kafka-event-service) | enrichment-consumer, search-consumer, audit-consumer, notification-consumer |
| `mdm.golden.events` | mdm-core | distribution-consumer, notification-consumer, audit-consumer |
| `mdm.entity.distribution` | mdm-core | distribution-consumer |
| `mdm.match.events` | mdm-core | ai-consumer (weight tuning) |

### Redis key patterns

| Pattern | TTL | Purpose |
|---------|-----|---------|
| `entity:{entity_id}` | 5 min | Entity response cache |
| `session:{tenant_id}:{user_id}` | 7 days | Refresh token store |
| `nexus:notifications:{tenant_id}:{user_id}` | — | WebSocket pub/sub channel |
| `rate_limit:{user_id}` | 60 s | Token bucket for rate limiting |

### pgvector index strategy

```sql
-- entity_attributes: per-attribute embeddings (1536-dim from attribute-level models)
CREATE INDEX ON core_mdm.entity_attributes
  USING ivfflat (vector_embedding vector_cosine_ops) WITH (lists = 100);

-- ai.entity_embeddings: entity-level embeddings (768-dim, nomic-embed-text)
CREATE INDEX ON ai.entity_embeddings
  USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- ai.rag_chunks: knowledge base chunks (1536-dim)
CREATE INDEX ON ai.rag_chunks
  USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
```

`ivfflat` with 100 lists gives O(√N) approximate nearest-neighbour search —
adequate for up to ~10 M embeddings per tenant before switching to HNSW.

---

*Document generated from codebase exploration — Nexus AI MDM, June 2026.*
