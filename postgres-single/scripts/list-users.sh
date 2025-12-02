#!/bin/bash
# =============================================================================
# List PostgreSQL Users & Schemas
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../.env" ]; then
    source "$SCRIPT_DIR/../.env"
fi

DB_ADMIN="${POSTGRES_USER:-postgres}"
DB_NAME="${POSTGRES_DB:-postgres}"
DB_PASSWORD="${POSTGRES_PASSWORD:-}"

echo "=== Users ==="
docker exec -e PGPASSWORD="$DB_PASSWORD" postgres psql -h localhost -U "$DB_ADMIN" -d "$DB_NAME" -c "
SELECT rolname AS user, rolsuper AS superuser, rolcreatedb AS can_create_db
FROM pg_roles
WHERE rolname NOT LIKE 'pg_%'
ORDER BY rolname;
"

echo ""
echo "=== Schemas ==="
docker exec -e PGPASSWORD="$DB_PASSWORD" postgres psql -h localhost -U "$DB_ADMIN" -d "$DB_NAME" -c "
SELECT schema_name, schema_owner
FROM information_schema.schemata
WHERE schema_name NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
ORDER BY schema_name;
"

echo ""
echo "=== Schema Permissions ==="
docker exec -e PGPASSWORD="$DB_PASSWORD" postgres psql -h localhost -U "$DB_ADMIN" -d "$DB_NAME" -c "
SELECT nspname AS schema, pg_get_userbyid(nspowner) AS owner
FROM pg_namespace
WHERE nspname NOT LIKE 'pg_%' AND nspname != 'information_schema';
"
