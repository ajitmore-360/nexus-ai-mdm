Write-Host "===================================="
Write-Host "NEXUS AI MDM BOOTSTRAP"
Write-Host "===================================="

$env:PGPASSWORD="postgres"

Write-Host "Resetting database..."

psql -h localhost `
     -U postgres `
     -d postgres `
     -c "DROP DATABASE IF EXISTS nexus_mdm;"

psql -h localhost `
     -U postgres `
     -d postgres `
     -c "CREATE DATABASE nexus_mdm;"

Write-Host "Running migrations..."

Get-ChildItem ../migrations/*.sql |
Sort-Object Name |
ForEach-Object {

    Write-Host "Applying $($_.Name)"

    psql -h localhost `
         -U postgres `
         -d nexus_mdm `
         -f $_.FullName
}

Write-Host "Running verification..."

Get-ChildItem ../verify/*.sql |
Sort-Object Name |
ForEach-Object {

    Write-Host "Executing $($_.Name)"

    psql -h localhost `
         -U postgres `
         -d nexus_mdm `
         -f $_.FullName
}

Write-Host "===================================="
Write-Host "Bootstrap completed"
Write-Host "===================================="