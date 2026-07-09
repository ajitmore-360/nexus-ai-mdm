#!/usr/bin/env bash
# ============================================================================
# Azile AI MDM â€” Database Seeder (Linux/Mac)
# Usage: ./seed.sh          # load sample data
#        ./seed.sh --reset  # wipe and re-seed
# ============================================================================
set -euo pipefail

CONTAINER="azile-postgres"
DB_USER="postgres"
DB_NAME="azile_mdm"
SEED_FILE="$(dirname "$0")/postgres/seeds/001_sample_data.sql"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}âœ“${NC} $*"; }
info() { echo -e "${CYAN}â†’${NC} $*"; }
warn() { echo -e "${YELLOW}âš ${NC}  $*"; }
fail() { echo -e "${RED}âœ—${NC} $*"; exit 1; }

echo ""
echo -e "${CYAN}  Azile AI MDM â€” Database Seeder${NC}"
echo ""

info "Checking database container..."
docker ps --filter "name=$CONTAINER" --filter "status=running" --format "{{.Names}}" | grep -q "$CONTAINER" \
  || fail "Container '$CONTAINER' is not running. Start it: docker compose up -d postgres"
ok "Container is running"

info "Waiting for PostgreSQL to be ready..."
for i in $(seq 1 20); do
  docker exec "$CONTAINER" pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1 && break
  sleep 3
done
ok "PostgreSQL is ready"

info "Ensuring pgcrypto extension is enabled..."
docker exec "$CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" \
  -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;" >/dev/null 2>&1
ok "pgcrypto available"

if [[ "${1:-}" == "--reset" ]]; then
  warn "Reset mode â€” removing existing seed data..."
  docker exec "$CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "
    DELETE FROM core_mdm.match_candidates  WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
    DELETE FROM core_mdm.golden_records    WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
    DELETE FROM core_mdm.entity_attributes WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
    DELETE FROM core_mdm.entities          WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
    DELETE FROM core_mdm.source_systems    WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
    DELETE FROM core_mdm.users             WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
    DELETE FROM governance.policy_rules    WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
    DELETE FROM ai.rag_documents           WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
  " >/dev/null 2>&1
  ok "Existing seed data removed"
fi

info "Loading sample data..."
docker exec -i "$CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" < "$SEED_FILE"

echo ""
echo -e "${GREEN}â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•${NC}"
echo -e "${GREEN}  Seed complete! Log in at:${NC}"
echo "    http://localhost:3000"
echo ""
echo -e "${GREEN}  Credentials:${NC}"
echo "    admin@nexus.ai   /  Admin@123456   (full access)"
echo "    steward@nexus.ai /  Steward@123    (merge reviews)"
echo "    analyst@nexus.ai /  Analyst@123    (read + reports)"
echo "    viewer@nexus.ai  /  Viewer@123     (read only)"
echo -e "${GREEN}â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•${NC}"
echo ""
