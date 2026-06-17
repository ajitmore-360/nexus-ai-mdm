# =============================================================================
# Nexus AI MDM — Windows PowerShell Setup Script
# =============================================================================
# Usage:
#   .\setup.ps1              Full setup (infra + build all services)
#   .\setup.ps1 -InfraOnly  Start infrastructure only
#   .\setup.ps1 -Reset      Wipe volumes and start fresh
#   .\setup.ps1 -Migrate    Run database migrations only
#   .\setup.ps1 -Status     Show service health status
# =============================================================================

param(
    [switch]$InfraOnly,
    [switch]$Reset,
    [switch]$Migrate,
    [switch]$Status
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

function Write-Ok($msg)   { Write-Host "✓ $msg" -ForegroundColor Green }
function Write-Info($msg) { Write-Host "→ $msg" -ForegroundColor Cyan }
function Write-Warn($msg) { Write-Host "⚠  $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "✗ $msg" -ForegroundColor Red; exit 1 }

# ── Check Docker ────────────────────────────────────────────────────────────
function Check-Docker {
    try { docker compose version | Out-Null; Write-Ok "Docker available" }
    catch { Write-Fail "Docker not found. Install Docker Desktop." }
}

# ── Setup .env ──────────────────────────────────────────────────────────────
function Setup-Env {
    if (-not (Test-Path ".env")) {
        Write-Warn ".env not found — creating with development defaults"
        @'
POSTGRES_USER=postgres
POSTGRES_PASSWORD=nexus_dev_2024
POSTGRES_PORT=5433
REDIS_PASSWORD=nexus_redis_pass
PGADMIN_EMAIL=admin@nexus.ai
PGADMIN_PASSWORD=nexus_pgadmin_dev
AUTH_DISABLED=false
JWT_SECRET=nexus-local-dev-jwt-secret-min-32-chars!!
API_BEARER_TOKEN=nexus-local-dev-token
GRAFANA_PASSWORD=nexus_grafana_dev
RUST_LOG=info
APP_ENV=development
'@ | Out-File -FilePath ".env" -Encoding utf8
        Write-Ok ".env created"
    } else {
        Write-Ok ".env found"
    }
}

# ── Wait for service ─────────────────────────────────────────────────────────
function Wait-Healthy($service, $maxSeconds = 120) {
    Write-Info "Waiting for $service to be healthy..."
    $elapsed = 0
    while ($elapsed -lt $maxSeconds) {
        $health = docker inspect "nexus-$service" --format='{{.State.Health.Status}}' 2>$null
        if ($health -eq "healthy") { Write-Ok "$service is healthy"; return }
        Start-Sleep 5; $elapsed += 5; Write-Host -NoNewline "."
    }
    Write-Host ""
    Write-Fail "$service did not become healthy within ${maxSeconds}s. Check: docker logs nexus-$service"
}

# ── Start infrastructure ─────────────────────────────────────────────────────
function Start-Infra {
    Write-Info "Starting infrastructure (postgres, redis, zookeeper, kafka, opa)..."
    docker compose up -d postgres redis zookeeper kafka opa
    Wait-Healthy "postgres" 120
    Wait-Healthy "redis" 60
    Write-Info "Waiting for Kafka..."
    Wait-Healthy "kafka" 120
    docker compose up -d kafka-ui
    Write-Ok "Infrastructure ready"
}

# ── Run migrations ───────────────────────────────────────────────────────────
function Run-Migrations {
    Write-Info "Starting mdm-core to run database migrations..."
    docker compose up -d mdm-core
    Wait-Healthy "mdm-core" 180
    Write-Ok "Database migrations complete"

    Write-Info "Verifying tables..."
    docker exec nexus-postgres psql -U postgres -d nexus_mdm -c "
        SELECT schemaname, COUNT(*) as tables
        FROM information_schema.tables
        WHERE schemaname IN ('core_mdm','event_store','ai','governance','platform','audit')
          AND table_type = 'BASE TABLE'
        GROUP BY schemaname ORDER BY schemaname;
    " 2>&1 | Write-Host
    Write-Ok "Table verification complete"
}

# ── Start all services ───────────────────────────────────────────────────────
function Start-Services {
    Write-Info "Starting all application services..."
    docker compose up -d `
        api-gateway `
        ai-service `
        ingest-service `
        policy-service `
        search-service `
        notification-service `
        distribution-service `
        enrichment-service `
        tenant-service `
        kafka-event-service
    Wait-Healthy "api-gateway" 120
    Write-Ok "All services started"
}

function Start-Observability {
    Write-Info "Starting observability and admin UIs..."
    docker compose up -d prometheus grafana pgadmin
    Write-Ok "Observability started"
}

function Print-Status {
    docker compose ps
}

function Print-Access {
    Write-Host ""
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  Nexus AI MDM is ready!" -ForegroundColor Green
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Web UI:         http://localhost:3000"
    Write-Host "  API Gateway:    http://localhost:8080"
    Write-Host "  Grafana:        http://localhost:3001  (admin / nexus_grafana_dev)"
    Write-Host "  PgAdmin:        http://localhost:5050  (admin@nexus.ai / nexus_pgadmin_dev)"
    Write-Host "  Kafka UI:       http://localhost:9000"
    Write-Host "  Prometheus:     http://localhost:9090"
    Write-Host ""
    Write-Host "  Service health endpoints:"
    Write-Host "    http://localhost:8081/health  (mdm-core)"
    Write-Host "    http://localhost:8082/health  (ai-service)"
    Write-Host "    http://localhost:8085/health  (search)"
    Write-Host "    http://localhost:8088/health  (enrichment)"
    Write-Host "    http://localhost:8090/health  (tenant)"
    Write-Host ""
    Write-Host "  Onboard a new organisation:" -ForegroundColor Cyan
    Write-Host '  Invoke-RestMethod -Method Post -Uri "http://localhost:8090/tenants/onboard" `'
    Write-Host '    -ContentType "application/json" `'
    Write-Host '    -Body '"'"'{"tenant_code":"my-org","display_name":"My Org","admin_email":"admin@myorg.com","admin_password":"Pass123!","admin_name":"Admin User"}'"'"
    Write-Host ""
}

# ── Main ─────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  NEXUS AI MDM — Setup" -ForegroundColor Cyan
Write-Host ""

Check-Docker
Setup-Env

if ($Status) {
    Print-Status
} elseif ($Reset) {
    Write-Warn "This will DESTROY all data volumes. Continue? (y/N)"
    $confirm = Read-Host
    if ($confirm -ne "y") { Write-Info "Aborted."; exit 0 }
    docker compose down -v --remove-orphans 2>&1 | Out-Null
    Write-Ok "Reset complete"
    Start-Infra
    Run-Migrations
    Start-Services
    Start-Observability
    Print-Status
    Print-Access
} elseif ($Migrate) {
    Run-Migrations
} elseif ($InfraOnly) {
    Start-Infra
    Start-Observability
    Write-Info "Infrastructure ready. Run services locally:"
    Write-Host '$env:DATABASE_URL="postgres://postgres:nexus_dev_2024@localhost:5433/nexus_mdm"'
    Write-Host '$env:REDIS_URL="redis://:nexus_redis_pass@localhost:6379"'
    Write-Host '$env:AUTH_DISABLED="true"'
    Write-Host '$env:JWT_SECRET="nexus-local-dev-jwt-secret-min-32-chars!!"'
    Write-Host "cargo run -p mdm-core"
} else {
    Start-Infra
    Run-Migrations
    Start-Services
    Start-Observability
    Print-Status
    Print-Access
}
