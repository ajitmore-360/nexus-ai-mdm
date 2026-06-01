#!/bin/bash

set -e

export PGPASSWORD=postgres

DB_HOST=localhost
DB_PORT=5432
DB_NAME=nexus_mdm
DB_USER=postgres

MIGRATION_DIR="../migrations"

echo "===================================="
echo "Running Nexus MDM migrations"
echo "===================================="

for file in $(ls $MIGRATION_DIR/*.sql | sort)
do

    echo "Applying migration: $file"

    start=$(date +%s%3N)

    psql \
      -h $DB_HOST \
      -p $DB_PORT \
      -U $DB_USER \
      -d $DB_NAME \
      -f "$file"

    end=$(date +%s%3N)

    runtime=$((end-start))

    filename=$(basename "$file")

    version=$(echo "$filename" | cut -d '_' -f1)

    psql \
      -h $DB_HOST \
      -p $DB_PORT \
      -U $DB_USER \
      -d $DB_NAME \
<<EOF

INSERT INTO platform.schema_migrations (
    version,
    migration_name,
    execution_time_ms,
    executed_by,
    success
)
VALUES (
    $version,
    '$filename',
    $runtime,
    current_user,
    true
)
ON CONFLICT (version)
DO NOTHING;

EOF

done

echo "===================================="
echo "Migrations completed"
echo "===================================="