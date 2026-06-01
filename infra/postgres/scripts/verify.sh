#!/bin/bash

set -e

export PGPASSWORD=postgres

DB_HOST=localhost
DB_PORT=5432
DB_NAME=nexus_mdm
DB_USER=postgres

VERIFY_DIR="../verify"

echo "===================================="
echo "Running verification scripts"
echo "===================================="

for file in $(ls $VERIFY_DIR/*.sql | sort)
do

    echo "Executing: $file"

    psql \
      -h $DB_HOST \
      -p $DB_PORT \
      -U $DB_USER \
      -d $DB_NAME \
      -f "$file"

done

echo "===================================="
echo "Verification completed"
echo "===================================="