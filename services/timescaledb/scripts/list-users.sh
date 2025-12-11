#!/bin/bash
# =============================================================================
# List TimescaleDB Users & Schemas
# =============================================================================
# Usage: ./scripts/list-users.sh
# =============================================================================

set -e

# Load environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../.env" ]; then
    source "$SCRIPT_DIR/../.env"
fi

# Require authentication
INFRA_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$INFRA_ROOT/lib/common.sh"
require_auth

# Database config
DB_NAME="${POSTGRES_DB:-timeseries}"
DB_ADMIN="${POSTGRES_USER:-postgres}"
DB_PASSWORD="${POSTGRES_PASSWORD:-}"

echo "=== TimescaleDB Users & Schemas ==="
echo ""

docker exec -i -e PGPASSWORD="$DB_PASSWORD" timescaledb psql -h localhost -U "$DB_ADMIN" -d "$DB_NAME" <<-'EOSQL'
    -- List users
    \echo '=== Users ==='
    SELECT
        rolname AS "User",
        rolsuper AS "Superuser",
        rolcreatedb AS "Create DB",
        rolcanlogin AS "Can Login"
    FROM pg_roles
    WHERE rolname NOT LIKE 'pg_%'
    ORDER BY rolname;

    -- List schemas
    \echo ''
    \echo '=== Schemas ==='
    SELECT
        schema_name AS "Schema",
        schema_owner AS "Owner"
    FROM information_schema.schemata
    WHERE schema_name NOT IN ('pg_catalog', 'information_schema', 'pg_toast', 'timescaledb_information', 'timescaledb_experimental', 'timescaledb_internal', '_timescaledb_catalog', '_timescaledb_internal', '_timescaledb_config', '_timescaledb_cache', '_timescaledb_functions')
    ORDER BY schema_name;

    -- List hypertables
    \echo ''
    \echo '=== Hypertables ==='
    SELECT
        hypertable_schema AS "Schema",
        hypertable_name AS "Table",
        num_chunks AS "Chunks",
        pg_size_pretty(hypertable_size(format('%I.%I', hypertable_schema, hypertable_name)::regclass)) AS "Size",
        compression_enabled AS "Compressed"
    FROM timescaledb_information.hypertables
    ORDER BY hypertable_schema, hypertable_name;

    -- List compression policies
    \echo ''
    \echo '=== Compression Policies ==='
    SELECT
        hypertable_schema AS "Schema",
        hypertable_name AS "Table",
        compress_after AS "Compress After"
    FROM timescaledb_information.jobs
    WHERE proc_name = 'policy_compression'
    ORDER BY hypertable_schema, hypertable_name;

    -- List retention policies
    \echo ''
    \echo '=== Retention Policies ==='
    SELECT
        hypertable_schema AS "Schema",
        hypertable_name AS "Table",
        drop_after AS "Drop After"
    FROM timescaledb_information.jobs
    WHERE proc_name = 'policy_retention'
    ORDER BY hypertable_schema, hypertable_name;
EOSQL
