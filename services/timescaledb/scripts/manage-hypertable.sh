#!/bin/bash
# =============================================================================
# Manage TimescaleDB Hypertable Policies
# =============================================================================
# Usage:
#   ./scripts/manage-hypertable.sh <action> <schema.table> [options]
#
# Actions:
#   compress <schema.table> <interval>    - Enable compression (e.g., "7 days")
#   retention <schema.table> <interval>   - Enable retention policy (e.g., "90 days")
#   stats <schema.table>                  - Show hypertable statistics
#   chunks <schema.table>                 - List all chunks
#
# Examples:
#   ./scripts/manage-hypertable.sh compress metrics.readings "7 days"
#   ./scripts/manage-hypertable.sh retention metrics.readings "90 days"
#   ./scripts/manage-hypertable.sh stats metrics.readings
#   ./scripts/manage-hypertable.sh chunks metrics.readings
# =============================================================================

set -e

# Load environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../.env" ]; then
    source "$SCRIPT_DIR/../.env"
fi

# Arguments
ACTION="${1:?Usage: $0 <action> <schema.table> [options]}"
TABLE="${2:?Usage: $0 <action> <schema.table> [options]}"
OPTION="${3:-}"

# Database config
DB_NAME="${POSTGRES_DB:-timeseries}"
DB_ADMIN="${POSTGRES_USER:-postgres}"
DB_PASSWORD="${POSTGRES_PASSWORD:-}"

case "$ACTION" in
    compress)
        INTERVAL="${OPTION:?Usage: $0 compress <schema.table> <interval>}"
        echo "=== Enabling Compression on $TABLE ==="
        echo "Compress data older than: $INTERVAL"
        docker exec -i -e PGPASSWORD="$DB_PASSWORD" timescaledb psql -h localhost -U "$DB_ADMIN" -d "$DB_NAME" <<-EOSQL
            -- Enable compression on the hypertable
            ALTER TABLE ${TABLE} SET (
                timescaledb.compress,
                timescaledb.compress_segmentby = ''
            );

            -- Add compression policy
            SELECT add_compression_policy('${TABLE}', INTERVAL '${INTERVAL}');

            \echo 'Compression policy added: compress data older than ${INTERVAL}'
EOSQL
        ;;

    retention)
        INTERVAL="${OPTION:?Usage: $0 retention <schema.table> <interval>}"
        echo "=== Enabling Retention Policy on $TABLE ==="
        echo "Drop data older than: $INTERVAL"
        docker exec -i -e PGPASSWORD="$DB_PASSWORD" timescaledb psql -h localhost -U "$DB_ADMIN" -d "$DB_NAME" <<-EOSQL
            -- Add retention policy
            SELECT add_retention_policy('${TABLE}', INTERVAL '${INTERVAL}');

            \echo 'Retention policy added: drop data older than ${INTERVAL}'
EOSQL
        ;;

    stats)
        echo "=== Hypertable Statistics: $TABLE ==="
        docker exec -i -e PGPASSWORD="$DB_PASSWORD" timescaledb psql -h localhost -U "$DB_ADMIN" -d "$DB_NAME" <<-EOSQL
            -- Basic info
            SELECT
                hypertable_schema,
                hypertable_name,
                num_chunks,
                compression_enabled,
                pg_size_pretty(hypertable_size('${TABLE}'::regclass)) as total_size,
                pg_size_pretty(hypertable_index_size('${TABLE}'::regclass)) as index_size
            FROM timescaledb_information.hypertables
            WHERE format('%I.%I', hypertable_schema, hypertable_name) = '${TABLE}';

            -- Compression stats
            \echo ''
            \echo '=== Compression Stats ==='
            SELECT
                pg_size_pretty(before_compression_total_bytes) as before,
                pg_size_pretty(after_compression_total_bytes) as after,
                round((1 - after_compression_total_bytes::numeric / before_compression_total_bytes::numeric) * 100, 1) as compression_ratio
            FROM hypertable_compression_stats('${TABLE}');

            -- Chunk stats
            \echo ''
            \echo '=== Recent Chunks ==='
            SELECT
                chunk_name,
                pg_size_pretty(chunk_size) as size,
                is_compressed
            FROM timescaledb_information.chunks
            WHERE format('%I.%I', hypertable_schema, hypertable_name) = '${TABLE}'
            ORDER BY chunk_name DESC
            LIMIT 10;
EOSQL
        ;;

    chunks)
        echo "=== Chunks for $TABLE ==="
        docker exec -i -e PGPASSWORD="$DB_PASSWORD" timescaledb psql -h localhost -U "$DB_ADMIN" -d "$DB_NAME" <<-EOSQL
            SELECT
                chunk_schema,
                chunk_name,
                range_start,
                range_end,
                pg_size_pretty(chunk_size) as size,
                is_compressed
            FROM timescaledb_information.chunks
            WHERE format('%I.%I', hypertable_schema, hypertable_name) = '${TABLE}'
            ORDER BY range_start DESC;
EOSQL
        ;;

    *)
        echo "Unknown action: $ACTION"
        echo "Available actions: compress, retention, stats, chunks"
        exit 1
        ;;
esac

echo ""
echo "=== Done ==="
