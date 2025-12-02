#!/bin/sh
# =============================================================================
# PostgreSQL Initialization Script
# Creates application user with proper permissions
# =============================================================================

set -e

echo "=== PostgreSQL Initialization Starting ==="

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
APP_SCHEMA="${POSTGRES_APP_SCHEMA:-public}"

# -----------------------------------------------------------------------------
# Create Non-Root User for Application Access
# -----------------------------------------------------------------------------
if [ -n "${POSTGRES_NON_ROOT_USER:-}" ] && [ -n "${POSTGRES_NON_ROOT_PASSWORD:-}" ]; then
    echo "Creating application user: ${POSTGRES_NON_ROOT_USER}"
    echo "Using schema: ${APP_SCHEMA}"

    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
        -- Create the application user
        DO \$\$
        BEGIN
            IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${POSTGRES_NON_ROOT_USER}') THEN
                CREATE USER ${POSTGRES_NON_ROOT_USER} WITH PASSWORD '${POSTGRES_NON_ROOT_PASSWORD}';
                RAISE NOTICE 'User ${POSTGRES_NON_ROOT_USER} created';
            ELSE
                ALTER USER ${POSTGRES_NON_ROOT_USER} WITH PASSWORD '${POSTGRES_NON_ROOT_PASSWORD}';
                RAISE NOTICE 'User ${POSTGRES_NON_ROOT_USER} already exists, password updated';
            END IF;
        END
        \$\$;

        -- Create custom schema if not public
        DO \$\$
        BEGIN
            IF '${APP_SCHEMA}' != 'public' THEN
                IF NOT EXISTS (SELECT FROM information_schema.schemata WHERE schema_name = '${APP_SCHEMA}') THEN
                    EXECUTE 'CREATE SCHEMA ${APP_SCHEMA}';
                    RAISE NOTICE 'Schema ${APP_SCHEMA} created';
                ELSE
                    RAISE NOTICE 'Schema ${APP_SCHEMA} already exists';
                END IF;
            END IF;
        END
        \$\$;

        -- Grant connect on database
        GRANT CONNECT ON DATABASE ${POSTGRES_DB} TO ${POSTGRES_NON_ROOT_USER};

        -- Make user owner of the schema (full control for migrations)
        ALTER SCHEMA ${APP_SCHEMA} OWNER TO ${POSTGRES_NON_ROOT_USER};

        -- Grant permissions on existing objects
        GRANT ALL ON ALL TABLES IN SCHEMA ${APP_SCHEMA} TO ${POSTGRES_NON_ROOT_USER};
        GRANT ALL ON ALL SEQUENCES IN SCHEMA ${APP_SCHEMA} TO ${POSTGRES_NON_ROOT_USER};
        GRANT ALL ON ALL FUNCTIONS IN SCHEMA ${APP_SCHEMA} TO ${POSTGRES_NON_ROOT_USER};

        -- Grant permissions on future objects
        ALTER DEFAULT PRIVILEGES IN SCHEMA ${APP_SCHEMA}
            GRANT ALL ON TABLES TO ${POSTGRES_NON_ROOT_USER};
        ALTER DEFAULT PRIVILEGES IN SCHEMA ${APP_SCHEMA}
            GRANT ALL ON SEQUENCES TO ${POSTGRES_NON_ROOT_USER};
        ALTER DEFAULT PRIVILEGES IN SCHEMA ${APP_SCHEMA}
            GRANT ALL ON FUNCTIONS TO ${POSTGRES_NON_ROOT_USER};
EOSQL

    echo "Application user ${POSTGRES_NON_ROOT_USER} configured successfully"
else
    echo "WARNING: POSTGRES_NON_ROOT_USER or POSTGRES_NON_ROOT_PASSWORD not set"
    echo "Skipping application user creation"
fi

echo "=== PostgreSQL Initialization Complete ==="
