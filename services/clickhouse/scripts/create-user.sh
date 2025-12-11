#!/bin/bash
# =============================================================================
# Create/Update ClickHouse User & Database
# =============================================================================
# Usage:
#   ./scripts/create-user.sh <username> <password> [database]
#
# Examples:
#   ./scripts/create-user.sh analytics_user secret123
#       -> Creates user with access to default database
#
#   ./scripts/create-user.sh analytics_user secret123 analytics
#       -> Creates user and 'analytics' database
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

# Arguments
NEW_USER="${1:?Usage: $0 <username> <password> [database]}"
NEW_PASSWORD="${2:?Usage: $0 <username> <password> [database]}"
NEW_DATABASE="${3:-}"

# Config
ADMIN_PASSWORD="${CLICKHOUSE_PASSWORD:-}"
HTTP_PORT="${CLICKHOUSE_HTTP_PORT:-8123}"

# If no database specified, use default
if [ -z "$NEW_DATABASE" ]; then
    NEW_DATABASE="${CLICKHOUSE_DB:-default}"
    CREATE_DB=false
else
    CREATE_DB=true
fi

echo "=== ClickHouse User & Database Setup ==="
echo "User:     $NEW_USER"
echo "Database: $NEW_DATABASE (create: $CREATE_DB)"
echo ""

# Wait for ClickHouse to be ready
echo "Waiting for ClickHouse to be ready..."
until curl -s "http://localhost:$HTTP_PORT/ping" > /dev/null; do
    sleep 1
done
echo "ClickHouse is ready"
echo ""

# Step 1: Create database if requested
if [ "$CREATE_DB" = true ]; then
    echo "[1/3] Creating database..."
    curl -s "http://localhost:$HTTP_PORT/?user=default&password=$ADMIN_PASSWORD" \
        --data "CREATE DATABASE IF NOT EXISTS ${NEW_DATABASE}"
else
    echo "[1/3] Using existing database: $NEW_DATABASE"
fi

# Step 2: Create/update user
echo "[2/3] Creating/updating user..."
# Drop user if exists and recreate (ClickHouse doesn't have ALTER USER for password easily)
curl -s "http://localhost:$HTTP_PORT/?user=default&password=$ADMIN_PASSWORD" \
    --data "DROP USER IF EXISTS ${NEW_USER}"
curl -s "http://localhost:$HTTP_PORT/?user=default&password=$ADMIN_PASSWORD" \
    --data "CREATE USER ${NEW_USER} IDENTIFIED BY '${NEW_PASSWORD}'"

# Step 3: Grant permissions
echo "[3/3] Granting permissions..."
curl -s "http://localhost:$HTTP_PORT/?user=default&password=$ADMIN_PASSWORD" \
    --data "GRANT ALL ON ${NEW_DATABASE}.* TO ${NEW_USER}"

echo ""
echo "=== Done ==="
echo ""
echo "Connection details:"
echo "  HTTP:   http://localhost:${HTTP_PORT}"
echo "  Native: localhost:${CLICKHOUSE_NATIVE_PORT:-9000}"
echo "  Database: $NEW_DATABASE"
echo "  User:     $NEW_USER"
echo ""
echo "Connection strings:"
echo "  HTTP:   http://${NEW_USER}:****@localhost:${HTTP_PORT}/${NEW_DATABASE}"
echo "  Native: clickhouse://${NEW_USER}:****@localhost:${CLICKHOUSE_NATIVE_PORT:-9000}/${NEW_DATABASE}"
echo ""
