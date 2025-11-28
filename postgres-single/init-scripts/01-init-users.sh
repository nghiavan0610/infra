#!/bin/bash
# =============================================================================
# PostgreSQL Initialization Script
# Creates application user with proper permissions
# =============================================================================

set -e

echo "=== PostgreSQL Initialization Starting ==="

# -----------------------------------------------------------------------------
# Create Non-Root User for Application Access
# -----------------------------------------------------------------------------
if [ -n "${POSTGRES_NON_ROOT_USER:-}" ] && [ -n "${POSTGRES_NON_ROOT_PASSWORD:-}" ]; then
    echo "Creating application user: ${POSTGRES_NON_ROOT_USER}"

    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
        -- Create the application user
        DO \$\$
        BEGIN
            IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${POSTGRES_NON_ROOT_USER}') THEN
                CREATE USER ${POSTGRES_NON_ROOT_USER} WITH PASSWORD '${POSTGRES_NON_ROOT_PASSWORD}';
                RAISE NOTICE 'User ${POSTGRES_NON_ROOT_USER} created';
            ELSE
                RAISE NOTICE 'User ${POSTGRES_NON_ROOT_USER} already exists';
            END IF;
        END
        \$\$;

        -- Grant permissions on database
        GRANT CONNECT ON DATABASE ${POSTGRES_DB} TO ${POSTGRES_NON_ROOT_USER};
        GRANT USAGE ON SCHEMA public TO ${POSTGRES_NON_ROOT_USER};

        -- Grant permissions on existing tables/sequences
        GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO ${POSTGRES_NON_ROOT_USER};
        GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO ${POSTGRES_NON_ROOT_USER};

        -- Grant permissions on future tables/sequences (IMPORTANT!)
        ALTER DEFAULT PRIVILEGES IN SCHEMA public
            GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${POSTGRES_NON_ROOT_USER};
        ALTER DEFAULT PRIVILEGES IN SCHEMA public
            GRANT USAGE, SELECT ON SEQUENCES TO ${POSTGRES_NON_ROOT_USER};

        -- Allow creating tables (for migrations)
        GRANT CREATE ON SCHEMA public TO ${POSTGRES_NON_ROOT_USER};
EOSQL

    echo "Application user ${POSTGRES_NON_ROOT_USER} configured successfully"
else
    echo "WARNING: POSTGRES_NON_ROOT_USER or POSTGRES_NON_ROOT_PASSWORD not set"
    echo "Skipping application user creation"
fi

echo "=== PostgreSQL Initialization Complete ==="
