#!/bin/bash
# =============================================================================
# Database Management Library
# =============================================================================
# Unified functions for database user/schema management across:
#   - PostgreSQL (single, replica, timescaledb)
#   - MySQL
#   - MongoDB
#   - ClickHouse
#
# Source this file:
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/database.sh"
# =============================================================================

# Prevent multiple sourcing
[[ -n "${_LIB_DATABASE_LOADED:-}" ]] && return 0
_LIB_DATABASE_LOADED=1

# Load common library
SCRIPT_DIR_DB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR_DB/common.sh"

# =============================================================================
# PostgreSQL Functions
# =============================================================================

# Wait for PostgreSQL to be ready
pg_wait_ready() {
    local container=${1:-postgres}
    local admin_user=${2:-postgres}
    local timeout=${3:-60}
    local count=0

    log_step "Waiting for PostgreSQL to be ready..."

    while [[ $count -lt $timeout ]]; do
        if docker exec "$container" pg_isready -U "$admin_user" -q 2>/dev/null; then
            log_info "PostgreSQL is ready"
            return 0
        fi
        sleep 1
        ((count++))
    done

    log_error "PostgreSQL not ready after ${timeout}s"
    return 1
}

# Execute SQL in PostgreSQL container
pg_exec() {
    local container=$1
    local admin_user=$2
    local admin_pass=$3
    local database=$4
    shift 4

    docker exec -i -e PGPASSWORD="$admin_pass" "$container" \
        psql -h localhost -U "$admin_user" -d "$database" "$@"
}

# Create or update PostgreSQL user
pg_create_user() {
    local container=$1
    local admin_user=$2
    local admin_pass=$3
    local new_user=$4
    local new_pass=$5

    log_step "Creating/updating user: $new_user"

    pg_exec "$container" "$admin_user" "$admin_pass" "postgres" <<-EOSQL
        DO \$\$
        BEGIN
            IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${new_user}') THEN
                CREATE USER ${new_user} WITH PASSWORD '${new_pass}';
                RAISE NOTICE 'User ${new_user} created';
            ELSE
                ALTER USER ${new_user} WITH PASSWORD '${new_pass}';
                RAISE NOTICE 'User ${new_user} password updated';
            END IF;
        END
        \$\$;
EOSQL
}

# Create PostgreSQL database
pg_create_database() {
    local container=$1
    local admin_user=$2
    local admin_pass=$3
    local db_name=$4
    local owner=$5

    log_step "Creating database: $db_name"

    pg_exec "$container" "$admin_user" "$admin_pass" "postgres" <<-EOSQL
        SELECT 'CREATE DATABASE ${db_name} OWNER ${owner}'
        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${db_name}')\gexec

        DO \$\$
        BEGIN
            IF EXISTS (SELECT FROM pg_database WHERE datname = '${db_name}') THEN
                EXECUTE 'ALTER DATABASE ${db_name} OWNER TO ${owner}';
            END IF;
        END
        \$\$;
EOSQL
}

# Create PostgreSQL schema
pg_create_schema() {
    local container=$1
    local admin_user=$2
    local admin_pass=$3
    local database=$4
    local schema=$5
    local owner=$6

    if [[ "$schema" == "public" ]]; then
        return 0
    fi

    log_step "Creating schema: $schema"

    pg_exec "$container" "$admin_user" "$admin_pass" "$database" <<-EOSQL
        DO \$\$
        BEGIN
            IF NOT EXISTS (SELECT FROM information_schema.schemata WHERE schema_name = '${schema}') THEN
                EXECUTE 'CREATE SCHEMA ${schema}';
                RAISE NOTICE 'Schema ${schema} created';
            END IF;
            EXECUTE 'ALTER SCHEMA ${schema} OWNER TO ${owner}';
        END
        \$\$;
EOSQL
}

# Grant PostgreSQL permissions
pg_grant_permissions() {
    local container=$1
    local admin_user=$2
    local admin_pass=$3
    local database=$4
    local schema=$5
    local target_user=$6

    log_step "Granting permissions to: $target_user"

    pg_exec "$container" "$admin_user" "$admin_pass" "$database" <<-EOSQL
        -- Database permissions
        GRANT CONNECT ON DATABASE ${database} TO ${target_user};
        GRANT CREATE ON DATABASE ${database} TO ${target_user};

        -- Schema permissions
        GRANT USAGE ON SCHEMA ${schema} TO ${target_user};
        GRANT ALL ON SCHEMA ${schema} TO ${target_user};

        -- Table permissions (existing)
        GRANT ALL ON ALL TABLES IN SCHEMA ${schema} TO ${target_user};
        GRANT ALL ON ALL SEQUENCES IN SCHEMA ${schema} TO ${target_user};
        GRANT ALL ON ALL FUNCTIONS IN SCHEMA ${schema} TO ${target_user};

        -- Future objects
        ALTER DEFAULT PRIVILEGES IN SCHEMA ${schema}
            GRANT ALL ON TABLES TO ${target_user};
        ALTER DEFAULT PRIVILEGES IN SCHEMA ${schema}
            GRANT ALL ON SEQUENCES TO ${target_user};
        ALTER DEFAULT PRIVILEGES IN SCHEMA ${schema}
            GRANT ALL ON FUNCTIONS TO ${target_user};
EOSQL
}

# Delete PostgreSQL user
pg_delete_user() {
    local container=$1
    local admin_user=$2
    local admin_pass=$3
    local database=$4
    local del_user=$5
    local drop_schema=${6:-false}

    log_step "Deleting user: $del_user"

    # First, drop all databases owned by this user
    # DROP DATABASE cannot run inside a transaction, so we handle it separately
    local owned_dbs
    owned_dbs=$(docker exec -e PGPASSWORD="$admin_pass" "$container" \
        psql -h localhost -U "$admin_user" -d postgres -t -A -c \
        "SELECT datname FROM pg_database WHERE datdba = (SELECT usesysid FROM pg_user WHERE usename = '${del_user}') AND datname NOT LIKE 'template%';" 2>/dev/null || echo "")

    if [[ -n "$owned_dbs" ]]; then
        log_step "Dropping databases owned by $del_user"
        while IFS= read -r db; do
            if [[ -n "$db" ]]; then
                log_info "Dropping database: $db"
                docker exec -e PGPASSWORD="$admin_pass" "$container" \
                    psql -h localhost -U "$admin_user" -d postgres -c "DROP DATABASE IF EXISTS \"$db\";" 2>/dev/null || true
            fi
        done <<< "$owned_dbs"
    fi

    # Drop schemas if requested
    if [[ "$drop_schema" == "true" ]]; then
        log_step "Dropping schemas owned by $del_user"
        pg_exec "$container" "$admin_user" "$admin_pass" "$database" <<-EOSQL
            DO \$\$
            DECLARE
                schema_rec RECORD;
            BEGIN
                FOR schema_rec IN
                    SELECT nspname FROM pg_namespace
                    WHERE pg_get_userbyid(nspowner) = '${del_user}'
                    AND nspname NOT IN ('public', 'pg_catalog', 'information_schema')
                LOOP
                    EXECUTE 'DROP SCHEMA ' || quote_ident(schema_rec.nspname) || ' CASCADE';
                    RAISE NOTICE 'Dropped schema: %', schema_rec.nspname;
                END LOOP;
            END
            \$\$;
EOSQL
    fi

    # Reassign remaining owned objects and drop the user
    log_step "Removing user: $del_user"
    pg_exec "$container" "$admin_user" "$admin_pass" "$database" <<-EOSQL
        REASSIGN OWNED BY ${del_user} TO ${admin_user};
        DROP OWNED BY ${del_user};
        DROP USER IF EXISTS ${del_user};
EOSQL
}

# List PostgreSQL users
pg_list_users() {
    local container=$1
    local admin_user=$2
    local admin_pass=$3

    pg_exec "$container" "$admin_user" "$admin_pass" "postgres" <<-EOSQL
        SELECT
            u.usename AS "User",
            CASE WHEN u.usesuper THEN 'Yes' ELSE 'No' END AS "Superuser",
            CASE WHEN u.usecreatedb THEN 'Yes' ELSE 'No' END AS "Create DB",
            COALESCE(string_agg(d.datname, ', '), '-') AS "Databases"
        FROM pg_user u
        LEFT JOIN pg_database d ON d.datdba = u.usesysid
        WHERE u.usename NOT LIKE 'pg_%'
        GROUP BY u.usename, u.usesuper, u.usecreatedb
        ORDER BY u.usename;
EOSQL
}

# Full PostgreSQL user setup (convenience function)
pg_setup_user() {
    local container=$1
    local admin_user=$2
    local admin_pass=$3
    local new_user=$4
    local new_pass=$5
    local database=${6:-}
    local schema=${7:-public}

    pg_wait_ready "$container" "$admin_user" || return 1

    pg_create_user "$container" "$admin_user" "$admin_pass" "$new_user" "$new_pass"

    if [[ -n "$database" ]]; then
        pg_create_database "$container" "$admin_user" "$admin_pass" "$database" "$new_user"
        pg_create_schema "$container" "$admin_user" "$admin_pass" "$database" "$schema" "$new_user"
        pg_grant_permissions "$container" "$admin_user" "$admin_pass" "$database" "$schema" "$new_user"
    fi

    log_info "User setup complete: $new_user"
}

# =============================================================================
# TimescaleDB Functions (extends PostgreSQL)
# =============================================================================

# Enable TimescaleDB extension
tsdb_enable_extension() {
    local container=$1
    local admin_user=$2
    local admin_pass=$3
    local database=$4

    log_step "Enabling TimescaleDB extension"

    pg_exec "$container" "$admin_user" "$admin_pass" "$database" <<-EOSQL
        CREATE EXTENSION IF NOT EXISTS timescaledb;
EOSQL
}

# Create hypertable
tsdb_create_hypertable() {
    local container=$1
    local admin_user=$2
    local admin_pass=$3
    local database=$4
    local table=$5
    local time_column=${6:-created_at}

    log_step "Converting $table to hypertable"

    pg_exec "$container" "$admin_user" "$admin_pass" "$database" <<-EOSQL
        SELECT create_hypertable('${table}', '${time_column}', if_not_exists => TRUE);
EOSQL
}

# =============================================================================
# MySQL Functions
# =============================================================================

# Wait for MySQL to be ready
mysql_wait_ready() {
    local container=${1:-mysql}
    local timeout=${2:-60}
    local count=0

    log_step "Waiting for MySQL to be ready..."

    while [[ $count -lt $timeout ]]; do
        if docker exec "$container" mysqladmin ping -h localhost --silent 2>/dev/null; then
            log_info "MySQL is ready"
            return 0
        fi
        sleep 1
        ((count++))
    done

    log_error "MySQL not ready after ${timeout}s"
    return 1
}

# Execute SQL in MySQL container
mysql_exec() {
    local container=$1
    local admin_pass=$2
    shift 2

    docker exec -i "$container" mysql -uroot -p"$admin_pass" "$@"
}

# Create MySQL user
mysql_create_user() {
    local container=$1
    local admin_pass=$2
    local new_user=$3
    local new_pass=$4
    local host=${5:-%}

    log_step "Creating user: $new_user"

    mysql_exec "$container" "$admin_pass" <<-EOSQL
        CREATE USER IF NOT EXISTS '${new_user}'@'${host}' IDENTIFIED BY '${new_pass}';
        ALTER USER '${new_user}'@'${host}' IDENTIFIED BY '${new_pass}';
EOSQL
}

# Create MySQL database
mysql_create_database() {
    local container=$1
    local admin_pass=$2
    local db_name=$3
    local charset=${4:-utf8mb4}
    local collation=${5:-utf8mb4_unicode_ci}

    log_step "Creating database: $db_name"

    mysql_exec "$container" "$admin_pass" <<-EOSQL
        CREATE DATABASE IF NOT EXISTS \`${db_name}\`
        CHARACTER SET ${charset}
        COLLATE ${collation};
EOSQL
}

# Grant MySQL permissions
mysql_grant_permissions() {
    local container=$1
    local admin_pass=$2
    local database=$3
    local user=$4
    local host=${5:-%}

    log_step "Granting permissions to: $user"

    mysql_exec "$container" "$admin_pass" <<-EOSQL
        GRANT ALL PRIVILEGES ON \`${database}\`.* TO '${user}'@'${host}';
        FLUSH PRIVILEGES;
EOSQL
}

# Delete MySQL user
mysql_delete_user() {
    local container=$1
    local admin_pass=$2
    local del_user=$3
    local host=${4:-%}

    log_step "Deleting user: $del_user"

    mysql_exec "$container" "$admin_pass" <<-EOSQL
        DROP USER IF EXISTS '${del_user}'@'${host}';
EOSQL
}

# =============================================================================
# MongoDB Functions
# =============================================================================

# Wait for MongoDB to be ready
mongo_wait_ready() {
    local container=${1:-mongo}
    local timeout=${2:-60}
    local count=0

    log_step "Waiting for MongoDB to be ready..."

    while [[ $count -lt $timeout ]]; do
        if docker exec "$container" mongosh --quiet --eval "db.adminCommand('ping')" 2>/dev/null | grep -q "ok"; then
            log_info "MongoDB is ready"
            return 0
        fi
        sleep 1
        ((count++))
    done

    log_error "MongoDB not ready after ${timeout}s"
    return 1
}

# Execute command in MongoDB
mongo_exec() {
    local container=$1
    local admin_user=$2
    local admin_pass=$3
    local database=$4
    shift 4

    docker exec -i "$container" mongosh \
        --username "$admin_user" \
        --password "$admin_pass" \
        --authenticationDatabase admin \
        "$database" "$@"
}

# Create MongoDB user
mongo_create_user() {
    local container=$1
    local admin_user=$2
    local admin_pass=$3
    local database=$4
    local new_user=$5
    local new_pass=$6
    local roles=${7:-readWrite}

    log_step "Creating user: $new_user on $database"

    mongo_exec "$container" "$admin_user" "$admin_pass" "$database" --eval "
        if (db.getUser('${new_user}')) {
            db.updateUser('${new_user}', { pwd: '${new_pass}' });
            print('User ${new_user} password updated');
        } else {
            db.createUser({
                user: '${new_user}',
                pwd: '${new_pass}',
                roles: ['${roles}']
            });
            print('User ${new_user} created');
        }
    "
}

# Delete MongoDB user
mongo_delete_user() {
    local container=$1
    local admin_user=$2
    local admin_pass=$3
    local database=$4
    local del_user=$5

    log_step "Deleting user: $del_user"

    mongo_exec "$container" "$admin_user" "$admin_pass" "$database" --eval "
        db.dropUser('${del_user}');
    " 2>/dev/null || true
}

# =============================================================================
# Connection String Generators
# =============================================================================

pg_connection_string() {
    local user=$1
    local pass=$2
    local host=$3
    local port=$4
    local database=$5

    echo "postgresql://${user}:${pass}@${host}:${port}/${database}"
}

mysql_connection_string() {
    local user=$1
    local pass=$2
    local host=$3
    local port=$4
    local database=$5
    # URL-encode password to handle special characters
    local pass_encoded=$(url_encode "$pass")
    echo "mysql://${user}:${pass_encoded}@${host}:${port}/${database}"
}

mongo_connection_string() {
    local user=$1
    local pass=$2
    local host=$3
    local port=$4
    local database=$5
    # URL-encode password to handle special characters
    local pass_encoded=$(url_encode "$pass")
    echo "mongodb://${user}:${pass_encoded}@${host}:${port}/${database}?authSource=admin"
}

redis_connection_string() {
    local pass=$1
    local host=$2
    local port=$3
    local db=${4:-0}
    # URL-encode password to handle special characters
    local pass_encoded=$(url_encode "$pass")
    echo "redis://:${pass_encoded}@${host}:${port}/${db}"
}

postgres_connection_string() {
    local user=$1
    local pass=$2
    local host=$3
    local port=$4
    local database=$5
    local sslmode=${6:-disable}
    # URL-encode password to handle special characters
    local pass_encoded=$(url_encode "$pass")
    echo "postgresql://${user}:${pass_encoded}@${host}:${port}/${database}?sslmode=${sslmode}"
}
