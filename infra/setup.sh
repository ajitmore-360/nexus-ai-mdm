#!/usr/bin/env bash
# =============================================================================
# Azile AI MDM — Complete Setup Script
# =============================================================================
# Usage:
#   ./setup.sh               Full setup (infra + build all services)
#   ./setup.sh --infra-only  Start infrastructure only (run services locally)
#   ./setup.sh --reset       Wipe volumes and start fresh
#   ./setup.sh --migrate     Run database migrations only
#   ./setup.sh --status      Show service health status
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSE="docker compose"

# Colours
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
info() { echo -e "${CYAN}→${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC}  $*"; }
fail() { echo -e "${RED}✗${NC} $*" >&2; exit 1; }

cd "$SCRIPT_DIR"

# ── Parse arguments ────────────────────────────────────────────────────────
MODE="full"
case "${1:-}" in
  --infra-only) MODE="infra" ;;
  --reset)      MODE="reset" ;;
  --migrate)    MODE="migrate" ;;
  --status)     MODE="status" ;;
  --help|-h)
    sed -n '2,12p' "$0"
    exit 0 ;;
esac

# ── Check dependencies ────────────────────────────────────────────────────
check_deps() {
  command -v docker  >/dev/null || fail "Docker not found. Install Docker Desktop."
  docker compose version >/dev/null 2>&1 || fail "docker compose plugin not found."
  ok "Docker available"
}

# ── Environment file ──────────────────────────────────────────────────────
setup_env() {
  if [ ! -f .env ]; then
    warn ".env not found — copying from template"
    cp .env.template .env 2>/dev/null || cat > .env << 'EOF'
POSTGRES_USER=postgres
POSTGRES_PASSWORD=azile_dev_2024
POSTGRES_PORT=5433
REDIS_PASSWORD=azile_redis_pass
PGADMIN_EMAIL=admin@nexus.ai
PGADMIN_PASSWORD=AZILE_pgadmin_dev
AUTH_DISABLED=false
JWT_SECRET=nexus-local-dev-jwt-secret-min-32-chars!!
API_BEARER_TOKEN=nexus-local-dev-token
GRAFANA_PASSWORD=AZILE_grafana_dev
OLLAMA_URL=http://ollama:11434
LLM_MODEL=llama3.2:8b
EMBED_MODEL=nomic-embed-text
RUST_LOG=info
APP_ENV=development
EOF
    ok ".env created with development defaults"
  else
    ok ".env found"
  fi
}

# ── Reset ─────────────────────────────────────────────────────────────────
do_reset() {
  warn "This will DESTROY all data. Continue? (y/N)"
  read -r confirm
  [ "$confirm" = "y" ] || { info "Aborted."; exit 0; }
  info "Stopping and removing all containers + volumes..."
  $COMPOSE down -v --remove-orphans 2>/dev/null || true
  ok "Reset complete"
}

# ── Wait for service health ───────────────────────────────────────────────
wait_healthy() {
  local service=$1
  local max_wait=${2:-120}
  local elapsed=0
  info "Waiting for $service to be healthy..."
  while [ $elapsed -lt $max_wait ]; do
    status=$($COMPOSE ps --format json "$service" 2>/dev/null | python3 -c "
import sys,json
data=[json.loads(l) for l in sys.stdin if l.strip()]
print(data[0].get('Health','unknown') if data else 'missing')
" 2>/dev/null || echo "unknown")

    case "$status" in
      healthy)  ok "$service is healthy"; return 0 ;;
      missing)  fail "$service container not found" ;;
    esac
    sleep 5; elapsed=$((elapsed + 5))
    echo -n "."
  done
  echo
  fail "$service did not become healthy within ${max_wait}s"
}

# ── Start infrastructure ──────────────────────────────────────────────────
start_infra() {
  info "Starting infrastructure services..."
  $COMPOSE up -d postgres redis zookeeper kafka opa

  wait_healthy postgres 120
  wait_healthy redis     60
  ok "Infrastructure ready"

  info "Starting Kafka (this takes ~30s)..."
  $COMPOSE up -d kafka-ui
  wait_healthy kafka 120
  ok "Kafka ready"

  info "Starting Ollama (model download may take several minutes on first run)..."
  $COMPOSE up -d ollama
  # Don't wait for Ollama on infra-only mode — it can take too long
}

# ── Run database migrations ───────────────────────────────────────────────
run_migrations() {
  info "Running database migrations via mdm-core..."
  info "mdm-core will automatically run all 6 migration files on startup"

  $COMPOSE up -d mdm-core

  info "Waiting for mdm-core to start and complete migrations (up to 120s)..."
  wait_healthy mdm-core 120

  ok "All database migrations complete"
  info "Verifying key tables exist..."

  # Quick sanity check
  docker exec azile-postgres psql -U postgres -d azile_mdm -c "
    SELECT schemaname, COUNT(*) as table_count
    FROM information_schema.tables
    WHERE schemaname IN ('core_mdm','event_store','ai','governance','platform','audit')
      AND table_type = 'BASE TABLE'
    GROUP BY schemaname
    ORDER BY schemaname;
  " 2>/dev/null && ok "Database tables verified" || warn "Could not verify tables (non-fatal)"
}

# ── Start all application services ────────────────────────────────────────
start_services() {
  info "Starting all application services..."
  $COMPOSE up -d \
    api-gateway \
    ai-service \
    ingest-service \
    policy-service \
    search-service \
    notification-service \
    distribution-service \
    enrichment-service \
    tenant-service \
    kafka-event-service

  info "Waiting for api-gateway (all services chain through it)..."
  wait_healthy api-gateway 120
  ok "All application services started"
}

# ── Start observability ───────────────────────────────────────────────────
start_observability() {
  info "Starting observability (Prometheus + Grafana)..."
  $COMPOSE up -d prometheus grafana pgadmin
  ok "Observability started"
}

# ── Pull LLM models ───────────────────────────────────────────────────────
pull_models() {
  info "Pulling LLM models (llama3.2:8b + nomic-embed-text)..."
  info "This may take 5-15 minutes on first run..."
  $COMPOSE up -d ollama-init
  ok "Model pull initiated (runs in background)"
}

# ── Print status ──────────────────────────────────────────────────────────
print_status() {
  echo
  echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}  Azile AI MDM — Service Status${NC}"
  echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
  $COMPOSE ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || \
  $COMPOSE ps
}

# ── Print access info ─────────────────────────────────────────────────────
print_access_info() {
  echo
  echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}  Azile AI MDM is ready!${NC}"
  echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
  echo
  echo "  🌐 Web UI:         http://localhost:3000"
  echo "  🔌 API Gateway:    http://localhost:8080"
  echo "  📊 Grafana:        http://localhost:3001   (admin / AZILE_grafana_dev)"
  echo "  🗄️  PgAdmin:       http://localhost:5050   (admin@nexus.ai / AZILE_pgadmin_dev)"
  echo "  📨 Kafka UI:       http://localhost:9000"
  echo "  📈 Prometheus:     http://localhost:9090"
  echo
  echo "  Backend services:"
  echo "    api-gateway:      http://localhost:8080/health"
  echo "    mdm-core:         http://localhost:8081/health"
  echo "    ai-service:       http://localhost:8082/health"
  echo "    ingest-service:   http://localhost:8083/health"
  echo "    policy-service:   http://localhost:8084/health"
  echo "    search-service:   http://localhost:8085/health"
  echo "    notification:     http://localhost:8086/health"
  echo "    enrichment:       http://localhost:8088/health"
  echo "    distribution:     http://localhost:8089/health"
  echo "    tenant-service:   http://localhost:8090/health"
  echo
  echo "  📋 Default login (UI):   any email + any password (AUTH_DISABLED=false uses JWT)"
  echo "  🔑 API Token:           nexus-local-dev-token"
  echo "  🏢 Default Tenant ID:   00000000-0000-0000-0000-000000000001"
  echo
  echo "  To onboard a new organisation:"
  echo "  curl -s -X POST http://localhost:8090/tenants/onboard \\"
  echo "    -H 'Content-Type: application/json' \\"
  echo "    -d '{\"tenant_code\":\"my-org\",\"display_name\":\"My Org\",\"admin_email\":\"admin@myorg.com\",\"admin_password\":\"Pass123!\",\"admin_name\":\"Admin User\"}'"
  echo
  echo "  To generate a dev license:"
  echo "  curl -s -X POST http://localhost:8090/license/generate-dev \\"
  echo "    -H 'Content-Type: application/json' \\"
  echo "    -d '{\"organization\":\"My Org\",\"tier\":\"Enterprise\",\"days_valid\":365}'"
  echo
}

# ── Main ──────────────────────────────────────────────────────────────────
main() {
  echo -e "${CYAN}"
  echo "  ███╗   ██╗███████╗██╗  ██╗██╗   ██╗███████╗"
  echo "  ████╗  ██║██╔════╝╚██╗██╔╝██║   ██║██╔════╝"
  echo "  ██╔██╗ ██║█████╗   ╚███╔╝ ██║   ██║███████╗"
  echo "  ██║╚██╗██║██╔══╝   ██╔██╗ ██║   ██║╚════██║"
  echo "  ██║ ╚████║███████╗██╔╝ ██╗╚██████╔╝███████║"
  echo "  ╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝"
  echo "  AI MDM Platform — Setup"
  echo -e "${NC}"

  check_deps
  setup_env

  case "$MODE" in
    reset)
      do_reset
      start_infra
      run_migrations
      start_services
      start_observability
      pull_models
      print_status
      print_access_info
      ;;
    infra)
      start_infra
      start_observability
      info "Infrastructure ready. Run services locally:"
      info "  DATABASE_URL=postgres://postgres:azile_dev_2024@localhost:5433/azile_mdm \\"
      info "  REDIS_URL=redis://:azile_redis_pass@localhost:6379 \\"
      info "  AUTH_DISABLED=true JWT_SECRET=nexus-local-dev-jwt-secret-min-32-chars!! \\"
      info "  cargo run -p mdm-core"
      ;;
    migrate)
      run_migrations
      ;;
    status)
      print_status
      ;;
    full)
      start_infra
      run_migrations
      start_services
      start_observability
      pull_models
      print_status
      print_access_info
      ;;
  esac
}

main "$@"
