#!/bin/bash
# =============================================================================
# Create/Update MySQL User & Database
# =============================================================================
# Usage:
#   ./scripts/create-user.sh <username> <password> [database]
#
# Examples:
#   ./scripts/create-user.sh app_user secret123
#       -> Creates user with access to default database
#
#   ./scripts/create-user.sh app_user secret123 myapp
#       -> Creates user and 'myapp' database
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

# Database config
ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-}"

# If no database specified, use default
if [ -z "$NEW_DATABASE" ]; then
    NEW_DATABASE="${MYSQL_DATABASE:-default}"
    CREATE_DB=false
else
    CREATE_DB=true
fi

echo "=== MySQL User & Database Setup ==="
echo "User:     $NEW_USER"
echo "Database: $NEW_DATABASE (create: $CREATE_DB)"
echo ""

# Wait for MySQL to be ready
echo "Waiting for MySQL to be ready..."
until docker exec mysql mysqladmin ping -h localhost -u root -p"$ROOT_PASSWORD" --silent; do
    sleep 1
done
echo "MySQL is ready"
echo ""

# Step 1: Create database if requested
if [ "$CREATE_DB" = true ]; then
    echo "[1/3] Creating database..."
    docker exec -i mysql mysql -u root -p"$ROOT_PASSWORD" <<-EOSQL
        CREATE DATABASE IF NOT EXISTS \`${NEW_DATABASE}\`
        CHARACTER SET utf8mb4
        COLLATE utf8mb4_unicode_ci;
EOSQL
else
    echo "[1/3] Using existing database: $NEW_DATABASE"
fi

# Step 2: Create/update user
echo "[2/3] Creating/updating user..."
docker exec -i mysql mysql -u root -p"$ROOT_PASSWORD" <<-EOSQL
    CREATE USER IF NOT EXISTS '${NEW_USER}'@'%' IDENTIFIED BY '${NEW_PASSWORD}';
    ALTER USER '${NEW_USER}'@'%' IDENTIFIED BY '${NEW_PASSWORD}';
EOSQL

# Step 3: Grant permissions
echo "[3/3] Granting permissions..."
docker exec -i mysql mysql -u root -p"$ROOT_PASSWORD" <<-EOSQL
    GRANT ALL PRIVILEGES ON \`${NEW_DATABASE}\`.* TO '${NEW_USER}'@'%';
    FLUSH PRIVILEGES;
EOSQL

echo ""
echo "=== Done ==="
echo ""
echo "Connection details:"
echo "  Host:     localhost"
echo "  Port:     ${MYSQL_PORT:-3306}"
echo "  Database: $NEW_DATABASE"
echo "  User:     $NEW_USER"
echo ""
echo "Connection string:"
echo "  mysql://${NEW_USER}:****@localhost:${MYSQL_PORT:-3306}/${NEW_DATABASE}"
echo ""
