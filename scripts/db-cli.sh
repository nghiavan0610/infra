#!/bin/bash
# =============================================================================
# Unified Database CLI
# =============================================================================
# Manage users, databases, and schemas across all database types.
#
# Usage:
#   ./scripts/db-cli.sh <database-type> <command> [args...]
#
# Database Types:
#   postgres, postgres-single, postgres-replica, timescaledb
#   mysql, mongo, clickhouse
#
# Commands:
#   create-user <username> <password> [database] [schema]
#   delete-user <username> [--drop-schema]
#   list-users
#
# Examples:
#   ./scripts/db-cli.sh postgres create-user app_user secret123 myapp
#   ./scripts/db-cli.sh mysql create-user app_user secret123 myapp
#   ./scripts/db-cli.sh mongo create-user app_user secret123 myapp
#   ./scripts/db-cli.sh postgres delete-user app_user --drop-schema
#   ./scripts/db-cli.sh postgres list-users
# =============================================================================

set -e

# Resolve symlinks to get actual script location
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
INFRA_ROOT="$(dirname "$SCRIPT_DIR")"

source "$INFRA_ROOT/lib/common.sh"
source "$INFRA_ROOT/lib/database.sh"

# Require authentication
require_auth

# =============================================================================
# Configuration Loaders
# =============================================================================

load_postgres_config() {
    local variant=${1:-postgres}
    local env_file

    case "$variant" in
        postgres|single)
            env_file="$INFRA_ROOT/services/postgres/.env"
            CONTAINER="postgres"
            ;;
        postgres-ha|replica)
            env_file="$INFRA_ROOT/services/postgres-ha/.env"
            CONTAINER="postgres-master"
            ;;
        timescaledb)
            env_file="$INFRA_ROOT/services/timescaledb/.env"
            CONTAINER="timescaledb"
            ;;
        *)
            log_error "Unknown PostgreSQL variant: $variant"
            exit 1
            ;;
    esac

    if [[ -f "$env_file" ]]; then
        source "$env_file"
    fi

    DB_ADMIN="${POSTGRES_USER:-postgres}"
    DB_PASSWORD="${POSTGRES_PASSWORD:-}"
    DB_HOST="${POSTGRES_HOST:-localhost}"
    DB_PORT="${POSTGRES_PORT:-5432}"
    DB_NAME="${POSTGRES_DB:-postgres}"
}

load_mysql_config() {
    local env_file="$INFRA_ROOT/services/mysql/.env"

    if [[ -f "$env_file" ]]; then
        source "$env_file"
    fi

    CONTAINER="mysql"
    DB_PASSWORD="${MYSQL_ROOT_PASSWORD:-}"
    DB_HOST="${MYSQL_HOST:-localhost}"
    DB_PORT="${MYSQL_PORT:-3306}"
}

load_mongo_config() {
    local env_file="$INFRA_ROOT/services/mongo/.env"

    if [[ -f "$env_file" ]]; then
        source "$env_file"
    fi

    CONTAINER="mongo"
    DB_ADMIN="${MONGO_ROOT_USER:-admin}"
    DB_PASSWORD="${MONGO_ROOT_PASSWORD:-}"
    DB_HOST="${MONGO_HOST:-localhost}"
    DB_PORT="${MONGO_PORT:-27017}"
}

# =============================================================================
# PostgreSQL Commands
# =============================================================================

cmd_postgres_create_user() {
    local variant=$1
    local new_user=$2
    local new_pass=$3
    local database=${4:-}
    local schema=${5:-public}

    load_postgres_config "$variant"

    log_header "PostgreSQL User Setup"
    echo "Container: $CONTAINER"
    echo "User:      $new_user"
    echo "Database:  ${database:-$DB_NAME} (${database:+create}${database:-existing})"
    echo "Schema:    $schema"
    echo ""

    pg_setup_user "$CONTAINER" "$DB_ADMIN" "$DB_PASSWORD" \
        "$new_user" "$new_pass" "$database" "$schema"

    # Enable TimescaleDB if variant is timescaledb
    if [[ "$variant" == "timescaledb" ]] && [[ -n "$database" ]]; then
        tsdb_enable_extension "$CONTAINER" "$DB_ADMIN" "$DB_PASSWORD" "$database"
    fi

    log_header "Connection Details"
    echo "Host:     $DB_HOST"
    echo "Port:     $DB_PORT"
    echo "Database: ${database:-$DB_NAME}"
    echo "User:     $new_user"
    echo "Schema:   $schema"
    echo ""
    echo "Connection string:"
    echo "  $(pg_connection_string "$new_user" "****" "$DB_HOST" "$DB_PORT" "${database:-$DB_NAME}")"
    echo ""
}

cmd_postgres_delete_user() {
    local variant=$1
    local del_user=$2
    local drop_schema=${3:-}

    load_postgres_config "$variant"

    log_header "Delete PostgreSQL User"
    echo "User: $del_user"
    [[ "$drop_schema" == "--drop-schema" ]] && echo "Drop owned schemas: Yes"
    echo ""

    local drop_flag="false"
    [[ "$drop_schema" == "--drop-schema" ]] && drop_flag="true"

    pg_delete_user "$CONTAINER" "$DB_ADMIN" "$DB_PASSWORD" "$DB_NAME" "$del_user" "$drop_flag"

    log_info "User $del_user deleted"
}

cmd_postgres_list_users() {
    local variant=$1

    load_postgres_config "$variant"

    log_header "PostgreSQL Users"
    pg_list_users "$CONTAINER" "$DB_ADMIN" "$DB_PASSWORD"
}

# =============================================================================
# MySQL Commands
# =============================================================================

cmd_mysql_create_user() {
    local new_user=$1
    local new_pass=$2
    local database=${3:-}

    load_mysql_config

    log_header "MySQL User Setup"
    echo "User:     $new_user"
    echo "Database: ${database:-none}"
    echo ""

    mysql_wait_ready "$CONTAINER" || exit 1
    mysql_create_user "$CONTAINER" "$DB_PASSWORD" "$new_user" "$new_pass"

    if [[ -n "$database" ]]; then
        mysql_create_database "$CONTAINER" "$DB_PASSWORD" "$database"
        mysql_grant_permissions "$CONTAINER" "$DB_PASSWORD" "$database" "$new_user"
    fi

    log_header "Connection Details"
    echo "Host:     $DB_HOST"
    echo "Port:     $DB_PORT"
    echo "User:     $new_user"
    [[ -n "$database" ]] && echo "Database: $database"
    echo ""
    if [[ -n "$database" ]]; then
        echo "Connection string:"
        echo "  $(mysql_connection_string "$new_user" "****" "$DB_HOST" "$DB_PORT" "$database")"
    fi
    echo ""
}

cmd_mysql_delete_user() {
    local del_user=$1

    load_mysql_config

    log_header "Delete MySQL User"
    echo "User: $del_user"
    echo ""

    mysql_delete_user "$CONTAINER" "$DB_PASSWORD" "$del_user"

    log_info "User $del_user deleted"
}

# =============================================================================
# MongoDB Commands
# =============================================================================

cmd_mongo_create_user() {
    local new_user=$1
    local new_pass=$2
    local database=${3:-}

    load_mongo_config

    log_header "MongoDB User Setup"
    echo "User:     $new_user"
    echo "Database: ${database:-admin}"
    echo ""

    mongo_wait_ready "$CONTAINER" || exit 1
    mongo_create_user "$CONTAINER" "$DB_ADMIN" "$DB_PASSWORD" \
        "${database:-admin}" "$new_user" "$new_pass"

    log_header "Connection Details"
    echo "Host:     $DB_HOST"
    echo "Port:     $DB_PORT"
    echo "User:     $new_user"
    echo "Database: ${database:-admin}"
    echo ""
    echo "Connection string:"
    echo "  $(mongo_connection_string "$new_user" "****" "$DB_HOST" "$DB_PORT" "${database:-admin}")"
    echo ""
}

cmd_mongo_delete_user() {
    local del_user=$1
    local database=${2:-admin}

    load_mongo_config

    log_header "Delete MongoDB User"
    echo "User:     $del_user"
    echo "Database: $database"
    echo ""

    mongo_delete_user "$CONTAINER" "$DB_ADMIN" "$DB_PASSWORD" "$database" "$del_user"

    log_info "User $del_user deleted"
}

# =============================================================================
# Help & Usage
# =============================================================================

show_help() {
    cat <<EOF
Unified Database CLI

Usage:
  $0 <database-type> <command> [args...]

Database Types:
  postgres          PostgreSQL (auto-detect: single or replica)
  postgres-single   PostgreSQL single node
  postgres-replica  PostgreSQL with replica
  timescaledb       TimescaleDB (PostgreSQL with time-series extension)
  mysql             MySQL 8.0
  mongo             MongoDB

Commands:
  create-user <username> <password> [database] [schema]
      Create or update a database user with optional database and schema.
      For PostgreSQL, schema defaults to 'public'.
      For MongoDB, database defaults to 'admin'.

  delete-user <username> [--drop-schema]
      Delete a user. Use --drop-schema to also drop owned schemas (PostgreSQL).

  list-users
      List all users (PostgreSQL only currently).

Examples:
  # PostgreSQL
  $0 postgres create-user app_user secret123 myapp
  $0 postgres create-user app_user secret123 myapp custom_schema
  $0 postgres delete-user app_user
  $0 postgres delete-user app_user --drop-schema
  $0 postgres list-users

  # TimescaleDB (same as postgres, but enables extension)
  $0 timescaledb create-user metrics_user secret123 metrics

  # MySQL
  $0 mysql create-user app_user secret123 myapp
  $0 mysql delete-user app_user

  # MongoDB
  $0 mongo create-user app_user secret123 myapp
  $0 mongo delete-user app_user myapp

EOF
}

# =============================================================================
# Main Entry Point
# =============================================================================

main() {
    local db_type=${1:-}
    local command=${2:-}

    if [[ -z "$db_type" ]] || [[ "$db_type" == "--help" ]] || [[ "$db_type" == "-h" ]]; then
        show_help
        exit 0
    fi

    if [[ -z "$command" ]]; then
        log_error "Command required"
        echo ""
        show_help
        exit 1
    fi

    shift 2

    case "$db_type" in
        postgres|postgres-single)
            case "$command" in
                create-user)
                    [[ $# -lt 2 ]] && { log_error "Usage: $0 postgres create-user <username> <password> [database] [schema]"; exit 1; }
                    cmd_postgres_create_user "single" "$@"
                    ;;
                delete-user)
                    [[ $# -lt 1 ]] && { log_error "Usage: $0 postgres delete-user <username> [--drop-schema]"; exit 1; }
                    cmd_postgres_delete_user "single" "$@"
                    ;;
                list-users)
                    cmd_postgres_list_users "single"
                    ;;
                *)
                    log_error "Unknown command: $command"
                    exit 1
                    ;;
            esac
            ;;

        postgres-replica|postgres-ha)
            case "$command" in
                create-user)
                    [[ $# -lt 2 ]] && { log_error "Usage: $0 postgres-ha create-user <username> <password> [database] [schema]"; exit 1; }
                    cmd_postgres_create_user "replica" "$@"
                    ;;
                delete-user)
                    [[ $# -lt 1 ]] && { log_error "Usage: $0 postgres-ha delete-user <username> [--drop-schema]"; exit 1; }
                    cmd_postgres_delete_user "replica" "$@"
                    ;;
                list-users)
                    cmd_postgres_list_users "replica"
                    ;;
                *)
                    log_error "Unknown command: $command"
                    exit 1
                    ;;
            esac
            ;;

        timescaledb)
            case "$command" in
                create-user)
                    [[ $# -lt 2 ]] && { log_error "Usage: $0 timescaledb create-user <username> <password> [database] [schema]"; exit 1; }
                    cmd_postgres_create_user "timescaledb" "$@"
                    ;;
                delete-user)
                    [[ $# -lt 1 ]] && { log_error "Usage: $0 timescaledb delete-user <username> [--drop-schema]"; exit 1; }
                    cmd_postgres_delete_user "timescaledb" "$@"
                    ;;
                list-users)
                    cmd_postgres_list_users "timescaledb"
                    ;;
                *)
                    log_error "Unknown command: $command"
                    exit 1
                    ;;
            esac
            ;;

        mysql)
            case "$command" in
                create-user)
                    [[ $# -lt 2 ]] && { log_error "Usage: $0 mysql create-user <username> <password> [database]"; exit 1; }
                    cmd_mysql_create_user "$@"
                    ;;
                delete-user)
                    [[ $# -lt 1 ]] && { log_error "Usage: $0 mysql delete-user <username>"; exit 1; }
                    cmd_mysql_delete_user "$@"
                    ;;
                *)
                    log_error "Unknown command: $command"
                    exit 1
                    ;;
            esac
            ;;

        mongo|mongodb)
            case "$command" in
                create-user)
                    [[ $# -lt 2 ]] && { log_error "Usage: $0 mongo create-user <username> <password> [database]"; exit 1; }
                    cmd_mongo_create_user "$@"
                    ;;
                delete-user)
                    [[ $# -lt 1 ]] && { log_error "Usage: $0 mongo delete-user <username> [database]"; exit 1; }
                    cmd_mongo_delete_user "$@"
                    ;;
                *)
                    log_error "Unknown command: $command"
                    exit 1
                    ;;
            esac
            ;;

        *)
            log_error "Unknown database type: $db_type"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
