#!/bin/bash
# =============================================================================
# Check PostgreSQL Replication Status
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../.env" ]; then
    source "$SCRIPT_DIR/../.env"
fi

# Require authentication
INFRA_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$INFRA_ROOT/lib/common.sh"
require_auth

MASTER_CONTAINER="${MASTER_CONTAINER:-postgres-master}"
REPLICA_CONTAINER="${REPLICA_CONTAINER:-postgres-replica}"
ADMIN_PASSWORD="${POSTGRES_ADMIN_PASSWORD:-}"

echo "=== Master Replication Status ==="
docker exec -i -e PGPASSWORD="$ADMIN_PASSWORD" "$MASTER_CONTAINER" \
    psql -h localhost -U postgres -d postgres -c "
SELECT
    client_addr,
    state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) as replication_lag
FROM pg_stat_replication;
"

echo ""
echo "=== Replication Slots ==="
docker exec -i -e PGPASSWORD="$ADMIN_PASSWORD" "$MASTER_CONTAINER" \
    psql -h localhost -U postgres -d postgres -c "
SELECT slot_name, slot_type, active, restart_lsn
FROM pg_replication_slots;
"

if docker ps --format '{{.Names}}' | grep -q "^${REPLICA_CONTAINER}$"; then
    echo ""
    echo "=== Replica Status ==="
    docker exec -i -e PGPASSWORD="$ADMIN_PASSWORD" "$REPLICA_CONTAINER" \
        psql -h localhost -U postgres -d postgres -c "
SELECT
    pg_is_in_recovery() as is_replica,
    pg_last_wal_receive_lsn() as receive_lsn,
    pg_last_wal_replay_lsn() as replay_lsn,
    pg_last_xact_replay_timestamp() as last_replay_time;
"
fi
