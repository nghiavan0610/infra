#!/bin/bash
# =============================================================================
# Delete PostgreSQL User
# =============================================================================
# Usage:
#   ./scripts/delete-user.sh <username> [--drop-schema]
#
# Examples:
#   ./scripts/delete-user.sh app_user                # Delete user only
#   ./scripts/delete-user.sh app_user --drop-schema  # Delete user + owned schema
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../.env" ]; then
    source "$SCRIPT_DIR/../.env"
fi

DEL_USER="${1:?Usage: $0 <username> [--drop-schema]}"
DROP_SCHEMA="${2:-}"

DB_ADMIN="${POSTGRES_USER:-postgres}"
DB_NAME="${POSTGRES_DB:-postgres}"
DB_PASSWORD="${POSTGRES_PASSWORD:-}"

echo "=== Deleting PostgreSQL User ==="
echo "User: $DEL_USER"

if [ "$DROP_SCHEMA" == "--drop-schema" ]; then
    echo "Also dropping owned schemas..."
    docker exec -i -e PGPASSWORD="$DB_PASSWORD" postgres psql -h localhost -U "$DB_ADMIN" -d "$DB_NAME" <<-EOSQL
        -- Drop owned schemas
        DO \$\$
        DECLARE
            schema_rec RECORD;
        BEGIN
            FOR schema_rec IN
                SELECT nspname FROM pg_namespace
                WHERE pg_get_userbyid(nspowner) = '${DEL_USER}'
                AND nspname NOT IN ('public', 'pg_catalog', 'information_schema')
            LOOP
                EXECUTE 'DROP SCHEMA ' || schema_rec.nspname || ' CASCADE';
                RAISE NOTICE 'Dropped schema: %', schema_rec.nspname;
            END LOOP;
        END
        \$\$;

        -- Drop user
        DROP USER IF EXISTS ${DEL_USER};
EOSQL
else
    docker exec -i -e PGPASSWORD="$DB_PASSWORD" postgres psql -h localhost -U "$DB_ADMIN" -d "$DB_NAME" <<-EOSQL
        -- Reassign owned objects to postgres
        REASSIGN OWNED BY ${DEL_USER} TO ${DB_ADMIN};

        -- Drop user
        DROP USER IF EXISTS ${DEL_USER};
EOSQL
fi

echo "=== Done ==="
