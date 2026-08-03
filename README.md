# Nexus AI MDM

Nexus AI MDM is a multi-tenant Master Data Management platform built with Rust microservices, a Flutter web UI, PostgreSQL with pgvector, Redis, Kafka, and an embedded Ollama LLM/embedding engine.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Clone the Repository](#2-clone-the-repository)
3. [Configure the Environment](#3-configure-the-environment)
4. [Start the Stack with Docker](#4-start-the-stack-with-docker)
5. [Verify the Stack is Healthy](#5-verify-the-stack-is-healthy)
6. [Access Points](#6-access-points)
7. [Default Login Credentials](#7-default-login-credentials)
8. [Common Operations](#8-common-operations)
9. [Service Architecture](#9-service-architecture)
10. [Flutter UI — Local Development](#10-flutter-ui--local-development)
11. [Port Reference](#11-port-reference)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. Prerequisites

Install all of the following before proceeding.

### Required

| Tool | Minimum Version | Notes |
|---|---|---|
| **Git** | 2.x | Any recent version works |
| **Docker Desktop** | 4.20 / Engine 24+ | Must include Compose v2 (`docker compose`, not `docker-compose`) |
| **Docker Compose** | v2.20+ | Bundled with Docker Desktop; verify with `docker compose version` |

### Hardware

| Resource | Minimum | Recommended |
|---|---|---|
| RAM | 12 GB free | 16 GB free |
| Disk | 20 GB free | 40 GB free |
| CPU | 4 cores | 8 cores |

> **Why so much RAM?**  
> Ollama runs `llama3.2:3b` (≈ 2 GB) and `nomic-embed-text` (≈ 600 MB) inside Docker. PostgreSQL, Kafka, and the Rust services add another 2–3 GB. On 8 GB machines, disable Ollama (see [Troubleshooting](#12-troubleshooting)).

### For Flutter UI development only (optional)

| Tool | Version |
|---|---|
| Flutter SDK | 3.x (stable channel) |
| Dart | Bundled with Flutter |

> If you only need the backend services and will access the UI via the Docker-built container, Flutter is **not required**.

---

## 2. Clone the Repository

```bash
git clone <repository-url> nexus-ai-mdm
cd nexus-ai-mdm
```

Verify you are on the `main` branch:

```bash
git branch
# * main
```

The repository structure relevant to this guide:

```
nexus-ai-mdm/
├── infra/
│   ├── docker-compose.yml      ← main compose file (run all commands from here)
│   ├── docker-compose.dev.yml  ← dev override (infrastructure only, no Rust services)
│   ├── .env.template           ← copy this to .env and fill in values
│   ├── .env                    ← YOUR local config (never committed to git)
│   └── postgres/init/          ← SQL init scripts run by postgres on first start
├── services/                   ← Rust microservices (11 services)
├── shared/                     ← Shared Rust crates (auth, database, redis, etc.)
├── ui/nexus_mdm_ui/            ← Flutter web application
└── database/                   ← Standalone migration scripts (for manual DB setup)
```

---

## 3. Configure the Environment

All runtime secrets and settings live in `infra/.env`. This file is **never committed to git** — it is in `.gitignore`.

### Step 1 — Copy the template

```bash
# macOS / Linux
cp infra/.env.template infra/.env

# Windows PowerShell
Copy-Item infra\.env.template infra\.env
```

### Step 2 — Edit `infra/.env`

Open `infra/.env` in any editor and review every value. The table below explains each variable:

---

#### PostgreSQL

| Variable | Default | Description |
|---|---|---|
| `POSTGRES_USER` | `postgres` | Database superuser username |
| `POSTGRES_PASSWORD` | `azile_dev_2024` | Database superuser password. **Change for any shared or production environment.** |
| `POSTGRES_PORT` | `5433` | Host port PostgreSQL is exposed on. Change if port 5433 is already in use on your machine. |

The database name is fixed as `azile_mdm` and does not need to be set in `.env`.

---

#### Redis

| Variable | Default | Description |
|---|---|---|
| `REDIS_PASSWORD` | `azile_redis_pass` | Redis `requirepass` value. All services use this to authenticate. |

---

#### Authentication & Security

| Variable | Default | Required | Description |
|---|---|---|---|
| `AUTH_DISABLED` | `false` | Yes | Set to `true` only for local testing without JWT tokens. **Never set true in production.** |
| `JWT_SECRET` | `azile-local-dev-jwt-secret-min-32-chars!!` | Yes | HMAC-SHA256 secret for signing and verifying JWTs. Must be at least 32 characters. **Generate a random value for any shared environment:** `openssl rand -hex 32` |
| `API_BEARER_TOKEN` | `azile-local-dev-token` | Yes | Static bearer token used for service-to-service calls. |
| `FIELD_ENCRYPTION_KEY` | *(empty)* | Optional | AES-256-GCM key for encrypting PII fields (email, phone, tax_id) at rest. Generate with: `openssl rand -hex 32` (produces exactly 64 hex characters). If left empty, PII is stored as plaintext — acceptable for local dev, **not for production**. |

---

#### AI / Ollama

| Variable | Default | Description |
|---|---|---|
| `LLM_MODEL` | `llama3.2:3b` | Ollama model used for AI matching and the RAG copilot. `llama3.2:3b` is the default (small, fast). Switch to `llama3.2:8b` for better quality at the cost of more RAM. |
| `EMBED_MODEL` | `nomic-embed-text` | Ollama model used to generate 768-dimensional embeddings for vector search. Do not change unless you also update the VECTOR(768) column size in the database. |
| `LLM_TEMPERATURE` | `0.2` | Controls LLM response randomness. Lower = more deterministic. |

> **Note:** On first startup, the `ollama-init` container pulls these models from the internet. `llama3.2:3b` is ≈ 2 GB and `nomic-embed-text` is ≈ 600 MB. This only happens once — models are cached in the `ollama_models` Docker volume.

---

#### Email (MailHog — dev only)

MailHog is included in the stack as a local SMTP catch-all. All emails sent by the application are intercepted and visible at `http://localhost:8025`. The defaults work as-is for local development.

| Variable | Default | Description |
|---|---|---|
| `SMTP_HOST` | `mailhog` | SMTP server hostname (Docker service name) |
| `SMTP_PORT` | `1025` | MailHog SMTP port |
| `SMTP_FROM` | `Azile AI MDM <noreply@azile-mdm.io>` | From address on all outgoing emails |
| `SMTP_INSECURE` | `true` | Skips TLS verification (fine for MailHog) |
| `SMTP_USER` | *(empty)* | SMTP username (not needed for MailHog) |
| `SMTP_PASS` | *(empty)* | SMTP password (not needed for MailHog) |

---

#### Observability

| Variable | Default | Description |
|---|---|---|
| `RUST_LOG` | `info` | Log level for all Rust services. Options: `error`, `warn`, `info`, `debug`, `trace` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://tempo:4318` | OpenTelemetry trace collector endpoint. Grafana Tempo is included in the stack — leave this as-is for local dev. |
| `APP_ENV` | `development` | Runtime mode. Set to `production` to enable security guards: ALLOWED_ORIGINS must not contain `localhost`, and FIELD_ENCRYPTION_KEY must be set. |
| `ALLOWED_ORIGINS` | `http://localhost:3000` | Comma-separated list of allowed CORS origins. Must match the URL where the Flutter UI is served. |

---

#### Admin UI passwords

| Variable | Default | Description |
|---|---|---|
| `PGADMIN_EMAIL` | `admin@nexus.ai` | PgAdmin login email |
| `PGADMIN_PASSWORD` | `AZILE_pgadmin_dev` | PgAdmin login password |
| `GRAFANA_PASSWORD` | `AZILE_grafana_dev` | Grafana `admin` user password |

---

### Minimum viable `infra/.env` for local development

For a clean local install the defaults work. The only values you may need to adjust are the ports if you have conflicts:

```dotenv
POSTGRES_USER=postgres
POSTGRES_PASSWORD=azile_dev_2024
POSTGRES_PORT=5433
REDIS_PASSWORD=azile_redis_pass
AUTH_DISABLED=false
JWT_SECRET=azile-local-dev-jwt-secret-min-32-chars!!
API_BEARER_TOKEN=azile-local-dev-token
FIELD_ENCRYPTION_KEY=
LLM_MODEL=llama3.2:3b
EMBED_MODEL=nomic-embed-text
LLM_TEMPERATURE=0.2
ALLOWED_ORIGINS=http://localhost:3000
APP_ENV=development
OTEL_EXPORTER_OTLP_ENDPOINT=http://tempo:4318
RUST_LOG=info
PGADMIN_EMAIL=admin@nexus.ai
PGADMIN_PASSWORD=AZILE_pgadmin_dev
GRAFANA_PASSWORD=AZILE_grafana_dev
```

---

## 4. Start the Stack with Docker

> **Important:** All `docker compose` commands must be run from inside the `infra/` directory — not the repo root. The build context in the Compose file is `..` (the parent), so Docker needs to be invoked from `infra/`.

```bash
cd infra
```

### First-time start (build all images + pull Ollama models)

```bash
docker compose up -d
```

This will:
1. Pull all third-party images (postgres, redis, kafka, ollama, grafana, etc.)
2. Build all 11 Rust service images and the Flutter UI image from source
3. Start infrastructure (postgres, redis, kafka, zookeeper, opa)
4. Start `mdm-core`, which runs all database migrations automatically
5. Start all remaining services once `mdm-core` is healthy
6. Trigger `ollama-init` to download `llama3.2:3b` and `nomic-embed-text`

> **First build takes 10–20 minutes** depending on your internet speed and machine. Rust compiles the entire workspace from scratch. Subsequent builds are much faster due to Docker layer caching.

### Watch the boot sequence

```bash
# Watch all services
docker compose logs -f

# Watch just the database migrations
docker compose logs -f mdm-core

# Watch just the API Gateway (confirms all upstream services are reachable)
docker compose logs -f api-gateway
```

The stack is ready when `mdm-core` logs something like:
```
mdm-core  | Applied migration: 0034_missing_runtime_tables
mdm-core  | All migrations applied successfully
mdm-core  | MDM Core listening on 0.0.0.0:8081
```

---

## 5. Verify the Stack is Healthy

Check that all containers are running and healthy:

```bash
docker compose ps
```

All services should show `healthy` or `running`. Key services to confirm:

| Container | Expected Status |
|---|---|
| `azile-postgres` | `healthy` |
| `azile-redis` | `healthy` |
| `azile-kafka` | `healthy` |
| `azile-mdm-core` | `healthy` |
| `nexus-api-gateway` | `healthy` |
| `azile-ui` | `healthy` |

If any service is `unhealthy` or `restarting`, check its logs:

```bash
docker compose logs <service-name>
```

### Quick API health check

```bash
curl http://localhost:8080/health
# Expected: {"status":"healthy","service":"api-gateway"}
```

---

## 6. Access Points

Once the stack is healthy, open these URLs in your browser:

| Service | URL | Notes |
|---|---|---|
| **Nexus MDM UI** | http://localhost:3000 | Flutter web application — main entry point |
| **API Gateway** | http://localhost:8080 | REST API — all UI calls route through here |
| **PgAdmin** | http://localhost:5050 | PostgreSQL browser (localhost-only) |
| **Kafka UI** | http://localhost:9000 | Kafka topic browser |
| **MailHog** | http://localhost:8025 | Email catch-all (view all outbound emails) |
| **Grafana** | http://localhost:3001 | Metrics dashboards |
| **Prometheus** | http://localhost:9090 | Raw metrics scrape endpoint |
| **OPA** | http://localhost:8181 | Open Policy Agent (governance rules) |

---

## 7. Default Login Credentials

### Application UI (http://localhost:3000)

| Account | Email | Password | Role |
|---|---|---|---|
| IT Admin | `ITAdmin@nexus.ai` | `Itadmin@123` | super_admin — recommended for first login |
| System Admin | `admin@nexus.ai` | `Admin@123` | super_admin |

> **Security note:** These credentials are seeded by the database migrations. Change them immediately in any environment that is not purely local.

### Admin Tools

| Tool | URL | Username | Password |
|---|---|---|---|
| PgAdmin | http://localhost:5050 | `admin@nexus.ai` | `AZILE_pgadmin_dev` (or value of `PGADMIN_PASSWORD` in `.env`) |
| Grafana | http://localhost:3001 | `admin` | `AZILE_grafana_dev` (or value of `GRAFANA_PASSWORD` in `.env`) |

### Database (direct connection)

| Parameter | Value |
|---|---|
| Host | `localhost` |
| Port | `5433` (or value of `POSTGRES_PORT` in `.env`) |
| Database | `azile_mdm` |
| Username | `postgres` (or value of `POSTGRES_USER` in `.env`) |
| Password | `azile_dev_2024` (or value of `POSTGRES_PASSWORD` in `.env`) |

---

## 8. Common Operations

All commands run from the `infra/` directory.

### Rebuild after code changes

```bash
# Rebuild and restart all services
docker compose up -d --build

# Rebuild only one service (faster)
docker compose up -d --build mdm-core
docker compose up -d --build api-gateway
```

### Stop the stack (preserves data volumes)

```bash
docker compose down
```

### Wipe everything and start fresh

```bash
# Stops containers AND deletes all volumes (database, redis, kafka, Ollama models)
docker compose down -v --remove-orphans

# Fresh start
docker compose up -d
```

> **Warning:** `-v` deletes all data including the database. Ollama models will need to be re-downloaded (several GB).

### View logs for a specific service

```bash
docker compose logs -f mdm-core
docker compose logs -f api-gateway
docker compose logs -f ingest-service
docker compose logs --tail=100 ai-service
```

### Restart a single service

```bash
docker compose restart mdm-core
docker compose restart api-gateway
```

### Connect to the database via psql

```bash
docker exec -it azile-postgres psql -U postgres -d azile_mdm
```

### Run infrastructure only (no Rust services or UI)

Use the dev override to start only postgres, redis, kafka, ollama, and monitoring — useful when running Rust services locally outside Docker:

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d
```

---

## 9. Service Architecture

The stack boots in two waves managed by Docker health checks.

```
Wave 1 — Infrastructure
  postgres ──┐
  redis      ├──► All Wave 2 services wait for these to be healthy
  kafka      │
  zookeeper  │
  opa        ┘

Wave 2 — Application (Wave 1 must be healthy first)
  mdm-core ──────────────► Runs ALL database migrations on startup
      │                    All other services wait for mdm-core:healthy
      ▼
  api-gateway      (port 8080)   — Routes all client requests
  ai-service       (port 8082)   — LLM matching, embeddings, RAG copilot
  ingest-service   (port 8083)   — Batch and CSV data ingestion
  policy-service   (port 8084)   — OPA governance policy evaluation
  search-service   (port 8085)   — Full-text + vector hybrid search
  notification-service (8086)    — WebSocket + email notifications
  enrichment-service   (8088)    — Third-party data enrichment
  distribution-service (8089)    — Downstream system sync
  tenant-service       (8090)    — Tenant and user management
  kafka-event-service            — Outbox → Kafka event relay

  azile-ui         (port 3000)   — Flutter web UI (nginx)
```

---

## 10. Flutter UI — Local Development

If you want to run the Flutter UI locally (hot reload, debugging) rather than through the Docker container:

### Prerequisites

Install Flutter (stable channel): https://docs.flutter.dev/get-started/install

Verify:
```bash
flutter doctor
# All checks should pass except Android/iOS if you don't need mobile
```

### Run in a browser (Chrome)

The backend Docker stack must be running first (so the API is available at `http://localhost:8080`).

```bash
cd ui/nexus_mdm_ui

# Install dependencies
flutter pub get

# Run in Chrome with the Docker API backend
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080
```

The UI will open at `http://localhost:PORT` (Flutter picks a random port) with hot reload enabled. Saved changes reflect immediately.

### Build a release web bundle

```bash
cd ui/nexus_mdm_ui
flutter build web --release --dart-define=API_BASE_URL=http://localhost:8080
# Output: ui/nexus_mdm_ui/build/web/
```

---

## 11. Port Reference

| Port | Service | Notes |
|---|---|---|
| **3000** | Nexus MDM UI | Flutter web app (nginx) |
| **8080** | API Gateway | All client traffic routes here |
| **8081** | mdm-core | Direct access (bypass gateway) |
| **8082** | ai-service | |
| **8083** | ingest-service | |
| **8084** | policy-service | |
| **8085** | search-service | |
| **8086** | notification-service | |
| **8088** | enrichment-service | |
| **8089** | distribution-service | |
| **8090** | tenant-service | |
| **5433** | PostgreSQL | Configurable via `POSTGRES_PORT` in `.env` |
| **6379** | Redis | |
| **9092** | Kafka | External listener |
| **9000** | Kafka UI | |
| **8025** | MailHog (web) | Email catch-all browser |
| **1025** | MailHog (SMTP) | |
| **8181** | OPA | Governance policy engine |
| **5050** | PgAdmin | localhost-only |
| **3001** | Grafana | |
| **9090** | Prometheus | |
| **3200** | Grafana Tempo | Distributed trace UI |
| **4317** | Tempo (OTLP gRPC) | |
| **4318** | Tempo (OTLP HTTP) | |
| **9093** | Alertmanager | localhost-only |

---

## 12. Troubleshooting

### `docker compose` not found

You have Compose v1 (`docker-compose`). Upgrade Docker Desktop to version 4.20+ which bundles Compose v2. Compose v1 is no longer supported.

---

### Port conflict — "address already in use"

Check which process owns the port and either stop it or change the port in `infra/.env`.

```bash
# macOS / Linux
lsof -i :5433    # example for PostgreSQL

# Windows PowerShell
netstat -ano | findstr :5433
```

Common conflicts and `.env` fixes:

| Conflict | `.env` change |
|---|---|
| Port 5433 taken | `POSTGRES_PORT=5435` |
| Port 6379 taken (local Redis) | Stop local Redis, or change the Redis port mapping in `docker-compose.yml` |
| Port 3000 taken | Change the `azile-ui` port mapping in `docker-compose.yml` |

---

### `mdm-core` keeps restarting

mdm-core waits for postgres to be healthy, then runs all database migrations. If it restarts:

```bash
docker compose logs mdm-core
```

Common causes:
- `DATABASE_URL` incorrect — check `POSTGRES_USER` and `POSTGRES_PASSWORD` in `.env`
- postgres container not yet healthy — wait another 30 seconds and check `docker compose ps`
- Migration SQL error — the `database/` folder at the repo root contains standalone migration files for manual inspection

---

### Ollama models not downloading

`ollama-init` pulls models from ollama.com on first start. If it fails:

```bash
docker compose logs ollama-init
```

If your network is slow, the 600-second timeout may expire. Re-run the init container:

```bash
docker compose up ollama-init
```

To skip Ollama entirely (disables AI matching and RAG copilot):

1. Comment out the `ollama` and `ollama-init` services in `infra/docker-compose.yml`
2. Remove `ollama` from `ai-service` depends_on
3. Add `OLLAMA_URL=` (empty) to the `ai-service` environment block

---

### Low RAM — stack crashes or is slow

If your machine has 8 GB of RAM or less:

1. **Disable Ollama** (biggest RAM consumer — see above)
2. Reduce Kafka memory: in `docker-compose.yml`, change the `kafka` deploy limits to `memory: 512M`
3. Run infrastructure-only mode with `docker-compose.dev.yml` and start only the services you need

---

### PgAdmin cannot connect to PostgreSQL

PgAdmin is pre-configured to connect to the `postgres` service inside Docker. If you add it manually:

- **Host**: `postgres` (Docker service name, not `localhost`)
- **Port**: `5432` (internal Docker port, not 5433)
- **Database**: `azile_mdm`
- **Username**: value of `POSTGRES_USER` from `.env`
- **Password**: value of `POSTGRES_PASSWORD` from `.env`

---

### "SECURITY: ALLOWED_ORIGINS contains 'localhost'" error

This guard fires when `APP_ENV=production` and `ALLOWED_ORIGINS` still contains `localhost`. Either:
- Set `APP_ENV=development` in `.env`, or
- Set `ALLOWED_ORIGINS` to your actual domain

---

### Inspect the database schema

The complete schema is documented in `database/README.md`. To explore it live:

```bash
# Connect via psql
docker exec -it azile-postgres psql -U postgres -d azile_mdm

# List all schemas
\dn

# List all tables in core_mdm schema
\dt core_mdm.*

# Describe a specific table
\d core_mdm.entities
```
