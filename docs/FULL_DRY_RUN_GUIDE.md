# Azile AI MDM â€” Full Dry-Run Guide

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
            â”‚
            â”‚  HTTP/REST + WebSocket
            â–¼
    â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
    â”‚         API Gateway  :8080              â”‚
    â”‚  auth_middleware â†’ tenant_middleware    â”‚
    â”‚  rate_limit_middleware â†’ cors           â”‚
    â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
                        â”‚
          â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¼â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
          â–¼             â–¼                 â–¼
    mdm-core:8081  ai-service:8082  other services
    PostgreSQL 16   Ollama LLM       (see below)
    Redis 7         pgvector
    Kafka outbox
          â”‚
    Kafka topics (published by kafka-event-service)
    â”œâ”€ mdm.entity.events
    â”œâ”€ mdm.golden.events
    â”œâ”€ mdm.entity.distribution
    â””â”€ mdm.match.events
          â”‚
    Consumers
    â”œâ”€ enrichment-service  â€” D&B / Experian API calls
    â”œâ”€ search-service:8085 â€” FTS + vector indexing
    â”œâ”€ distribution-service:8089 â€” Salesforce / SAP / webhooks
    â”œâ”€ notification-service:8086 â€” WebSocket push alerts
    â””â”€ audit-service       â€” immutable log writes

Other services:
  ingest-service:8083   â€” CSV / REST batch ingest
  policy-service:8084   â€” OPA Rego evaluation, GDPR
  tenant-service:8090   â€” license management
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
   - `access_token` â€” expires in 900 s (15 min), contains `{ sub, nxs_tenant_id, role }`.
   - `refresh_token` â€” expires in 604 800 s (7 days).
4. Stores refresh token in Redis: `session:{tenant_id}:{user_id}`.

**Response**:
```json
{
  "access_token": "eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJ1c2VyXâ€¦",
  "refresh_token": "eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJ1c2VyXâ€¦",
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
{ "refresh_token": "eyJhbGciOiJSUzI1NiJ9â€¦" }
```
Returns a fresh `access_token` with a new 15-minute window.

### 2.3 Development Mode

When `AUTH_DISABLED=true` in `.env`, the auth middleware is bypassed and a
synthetic tenant token is issued for `tenant_id = 00000000-0000-0000-0000-000000000000`.
**This is blocked at startup if `APP_ENV=production`.**

---

## 3. Entity Create Module

### 3.1 Scenario: Create a new Customer from the UI

A data steward opens **Entity Explorer â†’ New Entity**, fills the form, and
clicks **Save**.

#### Step 1 â€” Flutter UI builds the payload

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

#### Step 2 â€” API Gateway middleware

1. `request_id_middleware` â€” attaches `X-Request-Id: req_7f3aâ€¦` for tracing.
2. `tenant_middleware` â€” reads `x-tenant-id` header, verifies it equals `nxs_tenant_id` claim in the JWT. Returns **400** if header is missing, **403** if mismatch.
3. `auth_middleware` â€” validates JWT signature + expiry.
4. `rate_limit_middleware` â€” checks token-bucket per user; returns **429** if exceeded.
5. Proxies request to `mdm-core:8081/entities`.

#### Step 3 â€” MDM Core transaction

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
   WHERE tenant_id = 'a1b2â€¦' AND entity_name = 'Customer'),
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
  (gen_random_uuid(), 'a1b2â€¦', 'f47aâ€¦', 'legal_name',  '"Acme Corporation"', 'string', 1.0, 'mdm_ui', NOW()),
  (gen_random_uuid(), 'a1b2â€¦', 'f47aâ€¦', 'email',        '"billing@acme.com"', 'email',  1.0, 'mdm_ui', NOW()),
  (gen_random_uuid(), 'a1b2â€¦', 'f47aâ€¦', 'phone',        '"+14155550123"',     'phone',  1.0, 'mdm_ui', NOW()),
  (gen_random_uuid(), 'a1b2â€¦', 'f47aâ€¦', 'tax_id',       '"12-3456789"',       'string', 1.0, 'mdm_ui', NOW());

-- 3. Insert outbox event (same transaction â€” atomicity guarantee)
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
  '{"entity_id":"f47aâ€¦","entity_type":"Customer","attributes":[â€¦],"record_origin":"mdm_authoritative","tenant_id":"a1b2â€¦"}',
  'mdm.entity.events',
  'a1b2c3d4-0000-0000-0000-000000000001',   -- partition by tenant
  false,
  NOW()
);

COMMIT;
```

#### Step 4 â€” Response to UI

```json
{
  "success": true,
  "data": {
    "entity_id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
    "entity_code": "CUST-00001",
    "outbox_event_ids": ["e1234567-â€¦"]
  }
}
```

`EntityCreatePage` receives `Success<CreateEntityResponse>`, shows a snackbar
**"Entity created successfully"**, and calls `context.pop(true)` which returns
to `EntityExplorerPage` and triggers `_loadEntities()`.

#### Step 5 â€” Async post-commit processing

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
- `search-service` â€” indexes entity text + generates embedding via `ai-service`.
- `enrichment-service` â€” calls D&B/Experian to fill missing attributes.
- `notification-service` â€” pushes WebSocket alert to all connected stewards in that tenant.
- `audit-service` â€” copies event to `event_store.event_log` (immutable).

#### Final database state after entity create:

```
core_mdm.entities
â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
entity_id  | f47ac10b-58cc-4372-a567-0e02b2c3d479
tenant_id  | a1b2c3d4-0000-0000-0000-000000000001
entity_code| CUST-00001
status     | ACTIVE
trust_score| 1.0
created_at | 2026-06-17 09:42:11Z

core_mdm.entity_attributes (4 rows)
â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
attribute_name | attribute_value       | data_type | confidence_score
legal_name     | "Acme Corporation"    | string    | 1.0
email          | "billing@acme.com"    | email     | 1.0
phone          | "+14155550123"        | phone     | 1.0
tax_id         | "12-3456789"          | string    | 1.0

event_store.outbox_events (1 row)
â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
event_type | EntityCreated
published  | true  (after kafka-event-service processes)
topic_name | mdm.entity.events

ai.entity_embeddings (1 row, written by search-service after consume)
â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
entity_id       | f47ac10b-â€¦
embedding_model | nomic-embed-text
embedding       | [0.023, -0.144, 0.871, â€¦]  (768 dimensions)
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
WHERE entity_id = 'f47aâ€¦'
  AND tenant_id = 'a1b2â€¦'
  AND attribute_name = 'phone';

UPDATE core_mdm.entities
SET updated_at = NOW()
WHERE entity_id = 'f47aâ€¦' AND tenant_id = 'a1b2â€¦';

-- Outbox event (same transaction)
INSERT INTO event_store.outbox_events (event_type, â€¦)
VALUES ('EntityUpdated', '{"entity_id":"f47aâ€¦","changes":[{"attr":"phone","old_val":"+14155550123","new_val":"+14155559999"}]}', â€¦);
```

**Redis cache** for `entity:f47aâ€¦` is invalidated immediately.

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
2. Applies `SchemaMapper` â€” maps `"Company"` â†’ `"legal_name"`, etc.
3. Normalises values â€” email to lowercase, phone to E.164 format.
4. POSTs each entity to `mdm-core POST /entities` in batches of 50 (configurable).
5. Returns:
```json
{
  "batch_id": "b9e12a3b-â€¦",
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

### 6.2 Stage 1 â€” Blocking (candidate reduction)

Four parallel blockers reduce the search space:

| Blocker | SQL/Action | Candidates found |
|---------|-----------|-----------------|
| ExactBlocker | `WHERE attribute_name='email' AND attribute_value='"billing@acme.com"'` | entity_id: c1a2â€¦ |
| PhoneticBlocker | `WHERE attribute_name='name' AND lower(value) LIKE '%acme%'` | entity_id: c1a2â€¦, c3b4â€¦ |
| CanopyBlocker | Tokenise â†’ `ILIKE ANY(['acme','corporation'])` | entity_id: c1a2â€¦, c5d6â€¦ |
| VectorBlocker | `ORDER BY embedding <=> $query_embed::vector LIMIT 200` | entity_id: c1a2â€¦, c3b4â€¦, c7e8â€¦ |

Union of all blockers: `{c1a2â€¦, c3b4â€¦, c5d6â€¦, c7e8â€¦}` â€” 4 candidates from potentially millions.

### 6.3 Stage 2 â€” Field-level scoring

For each candidate, the engine compares field by field:

**Source entity "ACME CORPORATION" vs Candidate "Acme Corp" (entity c1a2â€¦)**:

| Field | Source value | Candidate value | Exact | Fuzzy (JW+Lev) | Phonetic | Semantic | Field Score |
|-------|-------------|----------------|-------|----------------|----------|----------|-------------|
| legal_name | ACME CORPORATION | Acme Corp | 0.0 | 0.78 | 1.0 (soundex match) | 0.92 | 0.74 |
| email | billing@acme.com | billing@acme.com | 1.0 | 1.0 | â€” | 1.0 | 1.0 |
| tax_id | 12-3456789 | 12-3456789 | 1.0 | 1.0 | â€” | 1.0 | 1.0 |

```
field_score = (0.35 Ã— exact) + (0.30 Ã— fuzzy) + (0.10 Ã— phonetic) + (0.25 Ã— semantic)
legal_name  = (0.35Ã—0.0) + (0.30Ã—0.78) + (0.10Ã—1.0) + (0.25Ã—0.92) = 0.00 + 0.23 + 0.10 + 0.23 = 0.574 ... 
              â†’ weighted up by email/tax_id exact matches
overall_score = 0.94   (aggregate across all fields weighted by field coverage)
confidence    = (0.94 Ã— 0.80) + (field_coverage:1.0 Ã— 0.20) = 0.952
```

**Score â‰¥ 0.95 â†’ AUTO_MERGE recommended** (no human review required).

For grey-zone (0.75 â‰¤ score < 0.95), AI scoring is triggered:

```
POST ai-service /match/semantic
{
  "entity_a": { "legal_name": "ACME CORPORATION", "tax_id": "12-3456789" },
  "entity_b": { "legal_name": "Acme Corp",        "tax_id": "12-3456789" }
}
â†’ Ollama llama3.2:3b: "Compare these two entities. Are they the same? Reply match or no_match with confidence."
â†’ Response: { "decision": "match", "ai_score": 0.97 }
```

### 6.4 Stage 3 â€” Clustering

```
Graph nodes: {source, c1a2, c3b4, c5d6}
Edges (score â‰¥ 0.75):
  source â†’ c1a2: 0.94
  source â†’ c3b4: 0.82

Connected component: {source, c1a2, c3b4}
master_score = avg_match Ã— 0.50 + avg_confidence Ã— 0.30 + centrality Ã— 0.20
  c1a2: 0.94Ã—0.5 + 0.95Ã—0.3 + 0.66Ã—0.2 = 0.47 + 0.285 + 0.132 = 0.887  â† suggested master
```

### 6.5 Database writes during matching

```sql
INSERT INTO core_mdm.match_requests (
  request_id, tenant_id, entity_type, source_entity_id,
  strategy, threshold, ai_assisted, status, â€¦
) VALUES ('req-uuid-â€¦', 'a1b2â€¦', 'Customer', 'f47aâ€¦', 'Hybrid', 0.75, true, 'Completed', â€¦);

INSERT INTO core_mdm.match_candidates (
  match_candidate_id, request_id, source_entity_id, matched_entity_id,
  match_status, match_score, confidence_score, ai_score,
  recommended_for_merge, requires_human_review, auto_approved, â€¦
) VALUES
  ('cand-1â€¦', 'req-uuid', 'f47aâ€¦', 'c1a2â€¦', 'Matched', 0.94, 0.95, 0.97, true, false, true, â€¦),
  ('cand-2â€¦', 'req-uuid', 'f47aâ€¦', 'c3b4â€¦', 'RequiresReview', 0.82, 0.85, null, false, true, false, â€¦);

-- Per-field detail for audit/explanation
INSERT INTO core_mdm.field_match_results (field_name, score, strategy, algorithm, â€¦)
VALUES
  ('legal_name', 0.74, 'Fuzzy',   'Jaro-Winkler', â€¦),
  ('email',      1.00, 'Exact',   'Exact',         â€¦),
  ('tax_id',     1.00, 'Exact',   'Exact',         â€¦);

-- Human review queue for the grey-zone candidate
INSERT INTO core_mdm.match_review_queue (
  review_id, tenant_id, request_id, match_candidate_id,
  review_status, priority
) VALUES (gen_random_uuid(), 'a1b2â€¦', 'req-uuid', 'cand-2â€¦', 'Pending', 3);
```

### 6.6 Match response

```json
{
  "request_id": "req-uuid-â€¦",
  "matches": [
    {
      "entity_id": "c1a2â€¦",
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
      "entity_id": "c3b4â€¦",
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
      "cluster_id": "clus-1â€¦",
      "entity_ids": ["f47aâ€¦","c1a2â€¦","c3b4â€¦"],
      "confidence": 0.88,
      "suggested_master": "c1a2â€¦"
    }
  ]
}
```

---

## 7. Survivorship & Merge Module

### 7.1 Scenario: Merge auto-approved pair (score â‰¥ 0.95)

**Endpoint**: `POST /merge` (or triggered automatically)

**Input**: source entity `f47aâ€¦` + matched entity `c1a2â€¦` (the suggested master).

**Step 1 â€” Load survivorship rules** (from `core_mdm.survivorship_rules`):

| Attribute | Strategy | Priority sources |
|-----------|----------|-----------------|
| legal_name | TrustedSource | salesforce (0.90) > sap (0.60) > d&b (0.80) |
| email | TrustedSource | salesforce (1.00) |
| tax_id | HighestConfidence | â€” |
| updated_at | MostRecent | â€” |

**Step 2 â€” Evaluate each attribute**:

| Attribute | Source A value | Source B value | Winner | Rule | Confidence |
|-----------|---------------|----------------|--------|------|-----------|
| legal_name | "Acme Corporation" (mdm_ui, trust=1.0) | "ACME Corp" (salesforce, trust=0.94) | "ACME Corp" | TrustedSource (Salesforce wins) | 0.94 |
| email | "billing@acme.com" (both identical) | same | "billing@acme.com" | TrustedSource | 1.0 |
| tax_id | "12-3456789" (both identical) | same | "12-3456789" | HighestConfidence | 1.0 |

**Step 3 â€” Single ACID transaction**:

```sql
BEGIN;

-- Create golden record
INSERT INTO core_mdm.golden_records (
  golden_record_id, tenant_id, entity_type_id,
  status, survivorship_score, ai_validated, metadata, created_at
) VALUES (
  'gold-uuid-â€¦',
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
SET status = 'MERGED', golden_record_id = 'gold-uuid-â€¦', updated_at = NOW()
WHERE entity_id IN ('f47aâ€¦', 'c1a2â€¦') AND tenant_id = 'a1b2â€¦';

-- Per-attribute decision log
INSERT INTO core_mdm.survivorship_field_decisions (execution_id, field_name, selected_entity_id, selected_value, strategy, confidence_score, explanation)
VALUES
  ('exec-uuid', 'legal_name', 'c1a2â€¦', '"ACME Corp"',        'TrustedSource',    0.94, 'Salesforce source weight 0.94 > mdm_ui 1.0'),
  ('exec-uuid', 'email',      'c1a2â€¦', '"billing@acme.com"', 'TrustedSource',    1.00, 'Single authoritative source'),
  ('exec-uuid', 'tax_id',     'f47aâ€¦', '"12-3456789"',       'HighestConfidence',1.00, 'Equal confidence, first source wins');

-- Outbox events (same transaction)
INSERT INTO event_store.outbox_events (event_type, aggregate_id, topic_name, event_payload, â€¦)
VALUES
  ('GoldenRecordCreated', 'gold-uuid-â€¦', 'mdm.golden.events', '{"golden_id":"gold-uuid-â€¦","source_ids":["f47aâ€¦","c1a2â€¦"],"survivorship_score":0.96}', â€¦),
  ('EntityMerged',        'f47aâ€¦',       'mdm.entity.events',  '{"source_id":"f47aâ€¦","golden_id":"gold-uuid-â€¦","merged_with_ids":["c1a2â€¦"]}', â€¦);

COMMIT;
```

**Post-commit**:
- Redis cache invalidated for `f47aâ€¦`, `c1a2â€¦`, `gold-uuidâ€¦`.
- `distribution-service` consumes `GoldenRecordCreated` â†’ pushes to Salesforce, SAP.
- `notification-service` alerts assigned stewards.

---

## 8. AI Copilot Module

### 8.1 Scenario: Steward asks a free-form question

**Endpoint**: `POST /copilot`

```json
{
  "tenant_id": "a1b2c3d4-0000-0000-0000-000000000001",
  "user_id": "steward-uuid-â€¦",
  "prompt": "Why were Acme Corporation and ACME Corp merged?"
}
```

**ai-service internal pipeline**:

**Step 1 â€” Safety checks**:
- Prompt injection detection (regex-based: blocks `ignore previous instructions`, etc.).
- Length limit: 2048 chars.

**Step 2 â€” Embed the query**:
```
POST http://ollama:11434/api/embeddings
{ "model": "nomic-embed-text", "prompt": "Why were Acme Corporation and ACME Corp merged?" }
â†’ embedding: [0.041, -0.289, 0.712, â€¦]  (768 dims)
```

**Step 3 â€” Vector search for context**:
```sql
SELECT chunk_text, metadata
FROM ai.rag_chunks
WHERE tenant_id = 'a1b2â€¦'
ORDER BY embedding <=> $query_embedding::vector
LIMIT 5;
```

Returns the 5 most semantically relevant knowledge chunks (match explanations,
survivorship evaluations, previous copilot answers stored as RAG documents).

**Step 4 â€” Build augmented prompt**:
```
You are Azile MDM Copilot, an AI assistant for master data management.
Answer only about data management topics. Do not reveal system internals.

CONTEXT:
[1] Entity f47ac10b (Acme Corporation, mdm_ui) merged with c1a2bbâ€¦ (ACME Corp, salesforce)
    Reason: email exact match, tax_id exact match, overall score 0.94.
[2] Survivorship rule: legal_name â†’ TrustedSource, Salesforce wins (weight 0.94).
[3] Golden record gold-uuid created 2026-06-17, survivorship_score 0.96.

QUESTION: Why were Acme Corporation and ACME Corp merged?
```

**Step 5 â€” LLM generation**:
```
POST http://ollama:11434/api/generate
{
  "model": "llama3.2:3b",
  "prompt": "<augmented prompt above>",
  "stream": false,
  "options": { "temperature": 0.2 }
}
â†’ response: "Acme Corporation and ACME Corp were merged because they share the
   same billing email (billing@acme.com) and tax ID (12-3456789), producing a
   match score of 0.94 â€” above the automatic merge threshold of 0.95 after
   AI validation. The legal name 'ACME Corp' from Salesforce was selected as
   the golden value because Salesforce has the highest configured trust weight
   (0.94) for this attribute."
```

**Response to UI**:
```json
{
  "success": true,
  "answer": "Acme Corporation and ACME Corp were merged because they share the same billing emailâ€¦",
  "source_docs": [
    { "chunk_text": "Entity f47ac10b merged with c1a2bbâ€¦", "relevance": 0.94 },
    { "chunk_text": "Survivorship rule: legal_name â†’ TrustedSourceâ€¦", "relevance": 0.88 }
  ]
}
```

### 8.2 Scenario: MCP tool call â€” explain a specific match

```json
{
  "tenant_id": "a1b2â€¦",
  "tool": "explain_match",
  "args": {
    "source_id": "f47ac10b-â€¦",
    "matched_id": "c1a2bb00-â€¦"
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
  "tenant_id": "a1b2â€¦",
  "tool": "detect_anomalies",
  "args": { "entity_type": "Customer" }
}
```

The `AnomalyDetector` runs statistical checks:
- **Duplicate detection** â€” entities with identical email/phone but different entity_ids.
- **Outlier detection** â€” attribute values more than 3Ïƒ from the mean (e.g. suspiciously long `legal_name`).
- **Pattern violation** â€” phone numbers not in E.164 format, emails without `@`.

Results written to `ai.anomalies` and returned in the response.

---

## 9. Distribution Module

### 9.1 Scenario: Push golden record to Salesforce after merge

Triggered by `GoldenRecordCreated` Kafka event consumed by `distribution-service`.

**distribution-service**:
1. Loads golden record `gold-uuid-â€¦` from mdm-core.
2. For each configured target (`Salesforce`, `SAP`):

   ```
   Target: Salesforce (delivery_mode: push)
   â”œâ”€â”€ Format entity per Salesforce schema
   â”‚   { "Name": "ACME Corp", "Email__c": "billing@acme.com", â€¦ }
   â”œâ”€â”€ POST https://salesforce.com/api/â€¦
   â”œâ”€â”€ On success: INSERT platform.distribution_jobs (status='succeeded')
   â””â”€â”€ On failure: INSERT platform.distribution_jobs (status='failed', retry_count=1)
                   (retry with exponential backoff up to 3 attempts)
   ```

3. Emits `DistributionCompleted` event.

**Manual distribution** (from UI):

`POST /distribution/jobs`
```json
{
  "entity_id": "gold-uuid-â€¦",
  "targets": [
    { "connector_id": "salesforce-prod", "target_system": "Salesforce", "delivery_mode": "push" }
  ]
}
```

**Retry failed jobs**:

`POST /distribution-jobs/{id}/retry`
â€” Re-queues the job; resets retry_count.

---

## 10. GDPR Erasure Module

### 10.1 Scenario: Data subject requests deletion

**Endpoint**: `POST /policy/gdpr/erasure`

```json
{
  "subject_id": "data-subject-uuid-â€¦",
  "reason": "User requested account deletion under GDPR Art. 17"
}
```

**policy-service flow**:
1. Finds all entities where `metadata->>'subject_id' = 'data-subject-uuid-â€¦'`.
2. For each entity:
   - `UPDATE core_mdm.entity_attributes SET attribute_value = '"ERASED"' WHERE entity_id = â€¦` (PII fields).
   - Clears `metadata` JSONB.
   - `DELETE FROM ai.entity_embeddings WHERE entity_id = â€¦`.
   - `DELETE FROM ai.rag_chunks WHERE entity_id = â€¦`.
   - `DELETE FROM ai.steward_feedback WHERE source_entity_id = â€¦`.
   - `UPDATE core_mdm.entities SET status = 'SoftDeleted', valid_to = NOW()`.
3. `INSERT INTO audit.gdpr_requests (subject_id, request_type='erasure', status='completed', fields_erased=N, â€¦)`.

**Response**:
```json
{
  "subject_id": "data-subject-uuid-â€¦",
  "fields_erased": 12,
  "records_affected": 3,
  "audit_id": "audit-uuid-â€¦",
  "completed_at": "2026-06-17T11:00:00Z"
}
```

The audit record in `audit.gdpr_requests` is **immutable** â€” it persists even
after the data is erased to demonstrate compliance.

---

## 11. End-to-End Flow: Full Customer Lifecycle

```
Day 1 â€” Steward creates Acme Corporation manually in the UI
â”‚  â†’ core_mdm.entities row (CUST-00001, status=ACTIVE)
â”‚  â†’ 4 attribute rows in core_mdm.entity_attributes
â”‚  â†’ outbox event EntityCreated (published â†’ search indexes + embeddings)
â”‚
Day 2 â€” Salesforce batch ingest CSV with "ACME Corp"
â”‚  â†’ core_mdm.entities row (CUST-00002, status=ACTIVE, source_system=salesforce)
â”‚  â†’ 4 attribute rows (legal_name="ACME Corp", same email+tax_id)
â”‚  â†’ outbox event EntityCreated
â”‚
Day 3 â€” Nightly matching job runs
â”‚  â†’ POST /match (Hybrid strategy, ai_assisted=true)
â”‚  â†’ Blocking: ExactBlocker finds email match immediately
â”‚  â†’ Scoring: overall_score=0.94, ai_score=0.97 â†’ AUTO_MERGE
â”‚  â†’ core_mdm.match_requests row (status=Completed)
â”‚  â†’ core_mdm.match_candidates row (Matched, auto_approved=true)
â”‚  â†’ core_mdm.field_match_results rows (per-field detail)
â”‚  â†’ Outbox event MatchApproved
â”‚
Day 3 (continued) â€” Survivorship executes
â”‚  â†’ legal_name = "ACME Corp" (Salesforce wins, TrustedSource)
â”‚  â†’ email = "billing@acme.com" (both identical)
â”‚  â†’ tax_id = "12-3456789" (HighestConfidence, same value)
â”‚  â†’ core_mdm.golden_records row (gold-uuid, status=ACTIVE, score=0.96)
â”‚  â†’ Both source entities status â†’ MERGED
â”‚  â†’ core_mdm.survivorship_field_decisions rows
â”‚  â†’ Outbox events: GoldenRecordCreated + EntityMerged
â”‚
Day 3 (async) â€” Distribution
â”‚  â†’ distribution-service consumes GoldenRecordCreated
â”‚  â†’ Pushes "ACME Corp" to Salesforce (upsert)
â”‚  â†’ platform.distribution_jobs row (status=succeeded)
â”‚
Day 4 â€” Steward asks copilot: "Why were these merged?"
â”‚  â†’ ai-service embeds query â†’ vector search â†’ RAG context
â”‚  â†’ Ollama generates plain-English explanation
â”‚  â†’ Copilot answer returned with source_docs citations
â”‚
Day 90 â€” GDPR erasure request from data subject
   â†’ PII attributes â†’ "ERASED"
   â†’ ai.entity_embeddings deleted
   â†’ ai.rag_chunks deleted
   â†’ core_mdm.entities status â†’ SoftDeleted
   â†’ audit.gdpr_requests row (immutable compliance record)
```

---

## 12. Database Storage Reference

### Complete table inventory by schema

#### core_mdm (primary MDM data)

| Table | Purpose | Key columns |
|-------|---------|-------------|
| `tenants` | Tenant registry | tenant_id, tenant_code, status, subscription_plan |
| `entity_types` | Supported entity kinds | entity_name (Customer/Vendor/Productâ€¦), ai_enabled, rag_enabled |
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
| `outbox_events` | Transactional outbox â€” pending Kafka publishes |
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
DRAFT â†’ ACTIVE â†’ PENDING_REVIEW â†’ UNDER_INVESTIGATION â†’ MERGED
                                                       â†’ ARCHIVED
                                                       â†’ SOFT_DELETED
```

### Kafka topic â†’ consumer group mapping

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
| `azile:notifications:{tenant_id}:{user_id}` | â€” | WebSocket pub/sub channel |
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

`ivfflat` with 100 lists gives O(âˆšN) approximate nearest-neighbour search â€”
adequate for up to ~10 M embeddings per tenant before switching to HNSW.

---

*Document generated from codebase exploration â€” Azile AI MDM, June 2026.*
