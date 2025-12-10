#!/bin/sh
# =============================================================================
# TimescaleDB Initialization Script
# =============================================================================
# Runs once on first container start
# Creates TimescaleDB extension and helper functions
# =============================================================================

set -e

echo "=== Initializing TimescaleDB ==="

# Create TimescaleDB extension
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Enable TimescaleDB extension
    CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;

    -- Enable additional useful extensions
    CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

    -- Verify TimescaleDB is installed
    SELECT extname, extversion FROM pg_extension WHERE extname = 'timescaledb';

    -- Show TimescaleDB version
    SELECT timescaledb_information.hypertables;
EOSQL

echo "=== TimescaleDB Initialized Successfully ==="
echo "Extension: timescaledb"
echo "Database: $POSTGRES_DB"
