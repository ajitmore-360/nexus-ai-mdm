#!/bin/bash

set -e

export PGPASSWORD=postgres

echo "Resetting database..."

psql \
  -h localhost \
  -U postgres \
  -d postgres \
<<EOF

DROP DATABASE IF EXISTS nexus_mdm;

CREATE DATABASE nexus_mdm;

EOF

echo "Database reset complete."