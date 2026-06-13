# ============================================================================
# Nexus AI MDM — Database Seeder
# Loads sample users, entities, and match candidates into the running database.
# ============================================================================
# Usage (from the infra/ directory):
#   .\seed.ps1
#   .\seed.ps1 -Reset    # wipe existing seed data first, then re-seed
# ============================================================================

param([switch]$Reset)

$ErrorActionPreference = "Stop"

$POSTGRES_CONTAINER = "nexus-postgres"
$DB_USER            = "postgres"
$DB_NAME            = "nexus_mdm"
$SEED_FILE          = "$PSScriptRoot\postgres\seeds\001_sample_data.sql"

Write-Host ""
Write-Host "  Nexus AI MDM — Database Seeder" -ForegroundColor Cyan
Write-Host ""

# ── 1. Check container is running ──────────────────────────────────────────
Write-Host "→ Checking database container..." -ForegroundColor Cyan
$running = docker ps --filter "name=$POSTGRES_CONTAINER" --filter "status=running" --format "{{.Names}}" 2>&1
if (-not $running) {
    Write-Host "✗ Container '$POSTGRES_CONTAINER' is not running." -ForegroundColor Red
    Write-Host "  Start it first: cd infra && docker compose up -d postgres" -ForegroundColor Yellow
    exit 1
}
Write-Host "✓ Database container is running" -ForegroundColor Green

# ── 2. Wait for postgres to be ready ───────────────────────────────────────
Write-Host "→ Waiting for PostgreSQL to be ready..." -ForegroundColor Cyan
$attempts = 0
do {
    $ready = docker exec $POSTGRES_CONTAINER pg_isready -U $DB_USER -d $DB_NAME 2>&1
    if ($ready -match "accepting connections") { break }
    $attempts++
    if ($attempts -gt 20) {
        Write-Host "✗ PostgreSQL did not become ready after 20 attempts" -ForegroundColor Red
        exit 1
    }
    Start-Sleep 3
} while ($true)
Write-Host "✓ PostgreSQL is ready" -ForegroundColor Green

# ── 3. Check pgcrypto extension ────────────────────────────────────────────
Write-Host "→ Checking pgcrypto extension (needed for password hashing)..." -ForegroundColor Cyan
$crypto = docker exec $POSTGRES_CONTAINER psql -U $DB_USER -d $DB_NAME -tAc "SELECT 1 FROM pg_extension WHERE extname='pgcrypto'" 2>&1
if ($crypto -notmatch "1") {
    Write-Host "  pgcrypto not found — enabling it..." -ForegroundColor Yellow
    docker exec $POSTGRES_CONTAINER psql -U $DB_USER -d $DB_NAME -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;" 2>&1 | Out-Null
}
Write-Host "✓ pgcrypto is available" -ForegroundColor Green

# ── 4. Optional reset ──────────────────────────────────────────────────────
if ($Reset) {
    Write-Host ""
    Write-Host "→ [Reset mode] Removing existing seed data..." -ForegroundColor Yellow
    docker exec $POSTGRES_CONTAINER psql -U $DB_USER -d $DB_NAME -c "
        DELETE FROM core_mdm.match_candidates  WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
        DELETE FROM core_mdm.golden_records    WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
        DELETE FROM core_mdm.entity_attributes WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
        DELETE FROM core_mdm.entities          WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
        DELETE FROM core_mdm.source_systems    WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
        DELETE FROM core_mdm.users             WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
        DELETE FROM governance.policy_rules    WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
        DELETE FROM ai.rag_documents           WHERE tenant_id = '00000000-0000-0000-0000-000000000001';
    " 2>&1 | Out-Null
    Write-Host "✓ Existing seed data removed" -ForegroundColor Green
}

# ── 5. Run seed SQL ────────────────────────────────────────────────────────
Write-Host ""
Write-Host "→ Loading sample data..." -ForegroundColor Cyan
$result = Get-Content $SEED_FILE -Raw | docker exec -i $POSTGRES_CONTAINER psql -U $DB_USER -d $DB_NAME 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Seed failed:" -ForegroundColor Red
    Write-Host $result -ForegroundColor Red
    exit 1
}

# Print NOTICE lines from PostgreSQL (our summary)
$result -split "`n" | Where-Object { $_ -match "NOTICE|════" } | ForEach-Object {
    Write-Host $_ -ForegroundColor Cyan
}

Write-Host ""
Write-Host "════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  Seed complete! Log in at:" -ForegroundColor Green
Write-Host "    http://localhost:3000" -ForegroundColor White
Write-Host "" -ForegroundColor White
Write-Host "  Credentials:" -ForegroundColor Green
Write-Host "    admin@nexus.ai   /  Admin@123456   (full access)" -ForegroundColor White
Write-Host "    steward@nexus.ai /  Steward@123    (merge reviews)" -ForegroundColor White
Write-Host "    analyst@nexus.ai /  Analyst@123    (read + reports)" -ForegroundColor White
Write-Host "    viewer@nexus.ai  /  Viewer@123     (read only)" -ForegroundColor White
Write-Host "════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
