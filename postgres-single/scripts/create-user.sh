#!/bin/bash
# =============================================================================
# Create PostgreSQL User & Schema
# =============================================================================
# Usage:
#   ./scripts/create-user.sh <username> <password> [schema]
#
# Examples:
#   ./scripts/create-user.sh app_user secret123              # Uses public schema
#   ./scripts/create-user.sh app_user secret123 app          # Creates 'app' schema
#   ./scripts/create-user.sh api_user secret123 api          # Creates 'api' schema
# =============================================================================

set -e

# Load environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../.env" ]; then
    source "$SCRIPT_DIR/../.env"
fi

# Arguments
NEW_USER="${1:?Usage: $0 <username> <password> [schema]}"
NEW_PASSWORD="${2:?Usage: $0 <username> <password> [schema]}"
NEW_SCHEMA="${3:-public}"

# Database config
DB_HOST="${POSTGRES_HOST:-localhost}"
DB_PORT="${POSTGRES_PORT:-5432}"
DB_NAME="${POSTGRES_DB:-postgres}"
DB_ADMIN="${POSTGRES_USER:-postgres}"
DB_PASSWORD="${POSTGRES_PASSWORD:-}"

echo "=== Creating PostgreSQL User ==="
echo "User: $NEW_USER"
echo "Schema: $NEW_SCHEMA"
echo "Database: $DB_NAME"
echo ""

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
until docker exec postgres pg_isready -U "$DB_ADMIN" -q; do
    sleep 1
done
echo "PostgreSQL is ready"
echo ""

# Run SQL (using PGPASSWORD for authentication, -h localhost forces TCP, -i for stdin)
docker exec -i -e PGPASSWORD="$DB_PASSWORD" postgres psql -h localhost -U "$DB_ADMIN" -d "$DB_NAME" <<-EOSQL
    -- Create user
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${NEW_USER}') THEN
            CREATE USER ${NEW_USER} WITH PASSWORD '${NEW_PASSWORD}';
            RAISE NOTICE 'User ${NEW_USER} created';
        ELSE
            ALTER USER ${NEW_USER} WITH PASSWORD '${NEW_PASSWORD}';
            RAISE NOTICE 'User ${NEW_USER} already exists, password updated';
        END IF;
    END
    \$\$;

    -- Create schema if not public
    DO \$\$
    BEGIN
        IF '${NEW_SCHEMA}' != 'public' THEN
            IF NOT EXISTS (SELECT FROM information_schema.schemata WHERE schema_name = '${NEW_SCHEMA}') THEN
                EXECUTE 'CREATE SCHEMA ${NEW_SCHEMA}';
                RAISE NOTICE 'Schema ${NEW_SCHEMA} created';
            ELSE
                RAISE NOTICE 'Schema ${NEW_SCHEMA} already exists';
            END IF;
        END IF;
    END
    \$\$;

    -- Grant permissions
    GRANT CONNECT ON DATABASE ${DB_NAME} TO ${NEW_USER};
    ALTER SCHEMA ${NEW_SCHEMA} OWNER TO ${NEW_USER};
    GRANT ALL ON ALL TABLES IN SCHEMA ${NEW_SCHEMA} TO ${NEW_USER};
    GRANT ALL ON ALL SEQUENCES IN SCHEMA ${NEW_SCHEMA} TO ${NEW_USER};
    GRANT ALL ON ALL FUNCTIONS IN SCHEMA ${NEW_SCHEMA} TO ${NEW_USER};

    -- Future objects
    ALTER DEFAULT PRIVILEGES IN SCHEMA ${NEW_SCHEMA}
        GRANT ALL ON TABLES TO ${NEW_USER};
    ALTER DEFAULT PRIVILEGES IN SCHEMA ${NEW_SCHEMA}
        GRANT ALL ON SEQUENCES TO ${NEW_USER};
EOSQL

echo ""
echo "=== Done ==="
echo "Connection string: postgresql://${NEW_USER}:****@${DB_HOST}:${DB_PORT}/${DB_NAME}?schema=${NEW_SCHEMA}"
