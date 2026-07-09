#!/bin/bash

set -e

export PGPASSWORD=postgres

echo "Resetting database..."

psql \
  -h localhost \
  -U postgres \
  -d postgres \
<<EOF

DROP DATABASE IF EXISTS azile_mdm;

CREATE DATABASE azile_mdm;

EOF

echo "Database reset complete."