#!/bin/bash
# =============================================================================
# Restore Script - Production
# =============================================================================
# Restores backups from Restic repository using config/*.json targets
# Usage:
#   ./restore.sh list                                    # List available snapshots
#   ./restore.sh show <snapshot-id>                      # Show snapshot contents
#   ./restore.sh postgres <snapshot-id> <target> <db>    # Restore PostgreSQL
#   ./restore.sh redis <snapshot-id> <target>            # Restore Redis
#   ./restore.sh mongo <snapshot-id> <target> <db>       # Restore MongoDB
#   ./restore.sh nats <snapshot-id> <target>             # Restore NATS
#   ./restore.sh volume <snapshot-id> <target>           # Restore volume
#   ./restore.sh files <snapshot-id> <path>              # Restore specific files
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment
if [[ -f "${BACKUP_ROOT}/.env" ]]; then
    set -a
    source "${BACKUP_ROOT}/.env"
    set +a
else
    echo "ERROR: ${BACKUP_ROOT}/.env not found"
    exit 1
fi

# Load common library
source "${SCRIPT_DIR}/lib-common.sh"

# Defaults
RESTORE_DIR="${RESTORE_DIR:-/tmp/restore}"

# -----------------------------------------------------------------------------
# Get target config from JSON
# Usage: get_target "postgres" "target-name"
# -----------------------------------------------------------------------------
get_target() {
    local service="$1"
    local target_name="$2"
    local config_file="${BACKUP_ROOT}/config/${service}.json"

    if [[ ! -f "$config_file" ]]; then
        log_error "Config file not found: $config_file"
        return 1
    fi

    local target=$(jq -c --arg name "$target_name" '.targets[] | select(.name == $name)' "$config_file" 2>/dev/null)

    if [[ -z "$target" ]]; then
        log_error "Target not found: $target_name"
        return 1
    fi

    echo "$target"
}

# -----------------------------------------------------------------------------
# List available targets
# -----------------------------------------------------------------------------
list_targets() {
    local service="$1"
    local config_file="${BACKUP_ROOT}/config/${service}.json"

    if [[ ! -f "$config_file" ]]; then
        return
    fi

    echo "  Available targets:"
    jq -r '.targets[].name' "$config_file" 2>/dev/null | while read -r name; do
        echo "    - $name"
    done
}

# -----------------------------------------------------------------------------
# List Snapshots
# -----------------------------------------------------------------------------
list_snapshots() {
    log_info "Available snapshots:"
    echo ""
    restic snapshots
}

# -----------------------------------------------------------------------------
# Show Snapshot Contents
# -----------------------------------------------------------------------------
show_snapshot() {
    local snapshot_id="$1"

    log_info "Contents of snapshot: $snapshot_id"
    echo ""
    restic ls "$snapshot_id" | head -100

    echo ""
    log_info "Showing first 100 entries. Use 'restic ls $snapshot_id' for full list."
}

# -----------------------------------------------------------------------------
# Restore from Restic
# -----------------------------------------------------------------------------
restore_from_restic() {
    local snapshot_id="$1"
    local include_path="${2:-}"

    mkdir -p "$RESTORE_DIR"

    log_info "Restoring from snapshot: $snapshot_id"

    if [[ -n "$include_path" ]]; then
        restic restore "$snapshot_id" --target "$RESTORE_DIR" --include "$include_path"
    else
        restic restore "$snapshot_id" --target "$RESTORE_DIR"
    fi

    log_info "Files restored to: $RESTORE_DIR"
}

# -----------------------------------------------------------------------------
# Restore PostgreSQL
# -----------------------------------------------------------------------------
restore_postgres() {
    local snapshot_id="$1"
    local target_name="$2"
    local database="$3"

    local target=$(get_target "postgres" "$target_name") || exit 1

    local mode=$(echo "$target" | jq -r '.mode')
    local user=$(echo "$target" | jq -r '.user // "postgres"')
    local password_env=$(echo "$target" | jq -r '.password_env // ""')
    local password=$(get_env_value "$password_env")

    log_info "Restoring PostgreSQL database: $database (target: $target_name)"

    # Restore dump from Restic
    local include_path="*/postgres/${target_name}_${database}_*"
    restore_from_restic "$snapshot_id" "$include_path"

    # Find the dump file
    local dump_file=$(find "$RESTORE_DIR" -name "${target_name}_${database}_*.sql.gz" -o -name "${target_name}_${database}_*.dump.gz" | head -1)

    if [[ -z "$dump_file" ]]; then
        log_error "No dump file found for database: $database"
        exit 1
    fi

    log_info "Found dump: $dump_file"

    # Confirm restore
    echo ""
    log_warn "⚠️  WARNING: This will OVERWRITE the existing database '$database'"
    read -p "Are you sure you want to continue? (yes/no): " confirm

    if [[ "$confirm" != "yes" ]]; then
        log_info "Restore cancelled"
        exit 0
    fi

    export PGPASSWORD="$password"

    case "$mode" in
        docker)
            local container=$(echo "$target" | jq -r '.container')
            log_info "Restoring to Docker container: $container"

            if [[ "$dump_file" == *".dump.gz" ]]; then
                # TimescaleDB custom format
                gunzip -c "$dump_file" | docker exec -i "$container" pg_restore -U "$user" -d "$database" --no-owner --clean --if-exists
            else
                # Plain SQL format
                gunzip -c "$dump_file" | docker exec -i "$container" psql -U "$user" -d "$database"
            fi
            ;;

        kubectl)
            local namespace=$(echo "$target" | jq -r '.namespace')
            local pod=$(echo "$target" | jq -r '.pod')
            log_info "Restoring to Kubernetes pod: $namespace/$pod"

            if [[ "$dump_file" == *".dump.gz" ]]; then
                gunzip -c "$dump_file" | kubectl exec -i -n "$namespace" "$pod" -- pg_restore -U "$user" -d "$database" --no-owner --clean --if-exists
            else
                gunzip -c "$dump_file" | kubectl exec -i -n "$namespace" "$pod" -- psql -U "$user" -d "$database"
            fi
            ;;

        network)
            local host=$(echo "$target" | jq -r '.host')
            local port=$(echo "$target" | jq -r '.port // 5432')
            log_info "Restoring to external database: $host:$port"

            if [[ "$dump_file" == *".dump.gz" ]]; then
                gunzip -c "$dump_file" | pg_restore -h "$host" -p "$port" -U "$user" -d "$database" --no-owner --clean --if-exists
            else
                gunzip -c "$dump_file" | psql -h "$host" -p "$port" -U "$user" -d "$database"
            fi
            ;;
    esac

    unset PGPASSWORD

    log_info "✓ PostgreSQL database '$database' restored successfully"

    # Cleanup
    rm -rf "$RESTORE_DIR"
}

# -----------------------------------------------------------------------------
# Restore Redis
# -----------------------------------------------------------------------------
restore_redis() {
    local snapshot_id="$1"
    local target_name="$2"

    local target=$(get_target "redis" "$target_name") || exit 1

    local mode=$(echo "$target" | jq -r '.mode')

    log_info "Restoring Redis target: $target_name"

    # Restore dump from Restic
    restore_from_restic "$snapshot_id" "*/redis/${target_name}_*"

    # Find the dump file
    local dump_file=$(find "$RESTORE_DIR" -name "${target_name}_*.rdb.gz" | head -1)

    if [[ -z "$dump_file" ]]; then
        log_error "No Redis dump file found for target: $target_name"
        exit 1
    fi

    log_info "Found dump: $dump_file"

    # Confirm restore
    echo ""
    log_warn "⚠️  WARNING: This will STOP Redis and REPLACE all data"
    read -p "Are you sure you want to continue? (yes/no): " confirm

    if [[ "$confirm" != "yes" ]]; then
        log_info "Restore cancelled"
        exit 0
    fi

    case "$mode" in
        docker)
            local container=$(echo "$target" | jq -r '.container')

            # Stop Redis
            log_info "Stopping Redis container: $container..."
            docker stop "$container" || true

            # Decompress and copy
            local temp_rdb="/tmp/restore_dump.rdb"
            gunzip -c "$dump_file" > "$temp_rdb"

            # Copy to Redis data directory
            docker cp "$temp_rdb" "${container}:/data/dump.rdb"

            # Start Redis
            log_info "Starting Redis container..."
            docker start "$container"

            rm -f "$temp_rdb"
            ;;

        kubectl)
            local namespace=$(echo "$target" | jq -r '.namespace')
            local pod=$(echo "$target" | jq -r '.pod')

            log_warn "Kubernetes Redis restore requires manual steps:"
            echo "  1. Scale down the Redis deployment"
            echo "  2. Copy dump.rdb to the PVC"
            echo "  3. Scale up the Redis deployment"
            echo ""
            echo "Dump file: $dump_file"
            exit 1
            ;;
    esac

    log_info "✓ Redis restored successfully"

    # Cleanup
    rm -rf "$RESTORE_DIR"
}

# -----------------------------------------------------------------------------
# Restore MongoDB
# -----------------------------------------------------------------------------
restore_mongo() {
    local snapshot_id="$1"
    local target_name="$2"
    local database="$3"

    local target=$(get_target "mongo" "$target_name") || exit 1

    local mode=$(echo "$target" | jq -r '.mode')
    local user=$(echo "$target" | jq -r '.user // ""')
    local password_env=$(echo "$target" | jq -r '.password_env // ""')
    local password=$(get_env_value "$password_env")
    local auth_db=$(echo "$target" | jq -r '.auth_db // "admin"')

    # TLS options
    local tls_enabled=$(echo "$target" | jq -r '.tls.enabled // false')
    local tls_opts=""
    if [[ "$tls_enabled" == "true" ]]; then
        tls_opts="--ssl"
        local allow_invalid=$(echo "$target" | jq -r '.tls.allow_invalid // false')
        [[ "$allow_invalid" == "true" ]] && tls_opts="$tls_opts --sslAllowInvalidCertificates --sslAllowInvalidHostnames"
    fi

    # Auth options
    local auth_opts=""
    if [[ -n "$user" && -n "$password" ]]; then
        auth_opts="-u $user -p $password --authenticationDatabase $auth_db"
    fi

    log_info "Restoring MongoDB database: $database (target: $target_name)"

    # Restore dump from Restic
    restore_from_restic "$snapshot_id" "*/mongo/${target_name}_${database}_*"

    # Find the dump file
    local dump_file=$(find "$RESTORE_DIR" -name "${target_name}_${database}_*.archive.gz" | head -1)

    if [[ -z "$dump_file" ]]; then
        log_error "No MongoDB dump file found for: $database"
        exit 1
    fi

    log_info "Found dump: $dump_file"

    # Confirm restore
    echo ""
    log_warn "⚠️  WARNING: This will OVERWRITE the existing database '$database'"
    read -p "Are you sure you want to continue? (yes/no): " confirm

    if [[ "$confirm" != "yes" ]]; then
        log_info "Restore cancelled"
        exit 0
    fi

    case "$mode" in
        docker)
            local container=$(echo "$target" | jq -r '.container')
            log_info "Restoring to Docker container: $container"

            # Use mongorestore with archive
            docker exec -i "$container" mongorestore \
                $auth_opts \
                $tls_opts \
                --drop \
                --archive --gzip < "$dump_file"
            ;;

        kubectl)
            local namespace=$(echo "$target" | jq -r '.namespace')
            local pod=$(echo "$target" | jq -r '.pod')
            log_info "Restoring to Kubernetes pod: $namespace/$pod"

            kubectl exec -i -n "$namespace" "$pod" -- mongorestore \
                $auth_opts \
                $tls_opts \
                --drop \
                --archive --gzip < "$dump_file"
            ;;

        network)
            local uri_env=$(echo "$target" | jq -r '.uri_env // ""')
            local uri=$(get_env_value "$uri_env")

            if [[ -n "$uri" ]]; then
                log_info "Restoring to external MongoDB..."
                mongorestore --uri="$uri" --drop --archive --gzip < "$dump_file"
            else
                log_error "No URI configured for network mode target"
                exit 1
            fi
            ;;
    esac

    log_info "✓ MongoDB database '$database' restored successfully"

    # Cleanup
    rm -rf "$RESTORE_DIR"
}

# -----------------------------------------------------------------------------
# Restore NATS JetStream
# -----------------------------------------------------------------------------
restore_nats() {
    local snapshot_id="$1"
    local target_name="$2"

    local target=$(get_target "nats" "$target_name") || exit 1

    local mode=$(echo "$target" | jq -r '.mode')

    log_info "Restoring NATS JetStream target: $target_name"

    # Restore from Restic
    restore_from_restic "$snapshot_id" "*/nats/${target_name}_*"

    # Find the backup file
    local backup_file=$(find "$RESTORE_DIR" -name "${target_name}_*.tar.gz" | head -1)

    if [[ -z "$backup_file" ]]; then
        log_error "No NATS backup file found for target: $target_name"
        exit 1
    fi

    log_info "Found backup: $backup_file"

    # Confirm restore
    echo ""
    log_warn "⚠️  WARNING: This will STOP NATS and REPLACE all JetStream data"
    read -p "Are you sure you want to continue? (yes/no): " confirm

    if [[ "$confirm" != "yes" ]]; then
        log_info "Restore cancelled"
        exit 0
    fi

    case "$mode" in
        docker)
            local container=$(echo "$target" | jq -r '.container')
            local data_path=$(echo "$target" | jq -r '.data_path // "/data/jetstream"')

            # Stop NATS
            log_info "Stopping NATS container: $container..."
            docker stop "$container" || true

            # Extract backup
            local temp_dir="/tmp/nats_restore"
            mkdir -p "$temp_dir"
            tar -xzf "$backup_file" -C "$temp_dir"

            # Copy to container
            docker cp "$temp_dir/." "${container}:${data_path}"

            # Start NATS
            log_info "Starting NATS container..."
            docker start "$container"

            rm -rf "$temp_dir"
            ;;

        kubectl)
            local namespace=$(echo "$target" | jq -r '.namespace')
            local pod=$(echo "$target" | jq -r '.pod')

            log_warn "Kubernetes NATS restore requires manual steps:"
            echo "  1. Scale down the NATS deployment"
            echo "  2. Copy JetStream data to the PVC"
            echo "  3. Scale up the NATS deployment"
            echo ""
            echo "Backup file: $backup_file"
            exit 1
            ;;
    esac

    log_info "✓ NATS JetStream restored successfully"

    # Cleanup
    rm -rf "$RESTORE_DIR"
}

# -----------------------------------------------------------------------------
# Restore Volume
# -----------------------------------------------------------------------------
restore_volume() {
    local snapshot_id="$1"
    local target_name="$2"

    local target=$(get_target "volumes" "$target_name") || exit 1

    local mode=$(echo "$target" | jq -r '.mode')

    log_info "Restoring volume target: $target_name"

    # Restore from Restic
    restore_from_restic "$snapshot_id" "*/volumes/${target_name}_*"

    # Find the backup file
    local backup_file=$(find "$RESTORE_DIR" -name "${target_name}_*.tar.gz" | head -1)

    if [[ -z "$backup_file" ]]; then
        log_error "No backup file found for volume: $target_name"
        exit 1
    fi

    log_info "Found backup: $backup_file"

    # Confirm restore
    echo ""
    log_warn "⚠️  WARNING: This will REPLACE all data in target '$target_name'"
    read -p "Are you sure you want to continue? (yes/no): " confirm

    if [[ "$confirm" != "yes" ]]; then
        log_info "Restore cancelled"
        exit 0
    fi

    case "$mode" in
        docker)
            local volume=$(echo "$target" | jq -r '.volume')

            # Check if volume exists
            if ! docker volume inspect "$volume" &> /dev/null; then
                log_info "Creating volume: $volume"
                docker volume create "$volume"
            fi

            # Restore volume
            log_info "Restoring volume data..."
            docker run --rm \
                -v "${volume}:/target" \
                -v "$(dirname "$backup_file"):/backup:ro" \
                alpine sh -c "rm -rf /target/* && tar -xzf /backup/$(basename "$backup_file") -C /target"
            ;;

        path)
            local path=$(echo "$target" | jq -r '.path')

            log_info "Restoring to path: $path"
            mkdir -p "$path"
            tar -xzf "$backup_file" -C "$(dirname "$path")"
            ;;

        kubectl)
            local namespace=$(echo "$target" | jq -r '.namespace')
            local pod=$(echo "$target" | jq -r '.pod')
            local mount_path=$(echo "$target" | jq -r '.mount_path')

            log_warn "Kubernetes volume restore requires manual steps:"
            echo "  1. Scale down the deployment using this PVC"
            echo "  2. Copy data to the PVC"
            echo "  3. Scale up the deployment"
            echo ""
            echo "Backup file: $backup_file"
            exit 1
            ;;
    esac

    log_info "✓ Volume '$target_name' restored successfully"

    # Cleanup
    rm -rf "$RESTORE_DIR"
}

# -----------------------------------------------------------------------------
# Restore Specific Files
# -----------------------------------------------------------------------------
restore_files() {
    local snapshot_id="$1"
    local file_path="$2"

    log_info "Restoring files matching: $file_path"

    restore_from_restic "$snapshot_id" "$file_path"

    log_info "Files restored to: $RESTORE_DIR"
    log_info "You can now manually copy the files to their destination"

    echo ""
    ls -la "$RESTORE_DIR"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    local command="${1:-help}"

    case "$command" in
        list)
            list_snapshots
            ;;
        show)
            if [[ -z "${2:-}" ]]; then
                log_error "Usage: $0 show <snapshot-id>"
                exit 1
            fi
            show_snapshot "$2"
            ;;
        postgres)
            if [[ -z "${2:-}" ]] || [[ -z "${3:-}" ]] || [[ -z "${4:-}" ]]; then
                log_error "Usage: $0 postgres <snapshot-id> <target-name> <database>"
                list_targets "postgres"
                exit 1
            fi
            restore_postgres "$2" "$3" "$4"
            ;;
        redis)
            if [[ -z "${2:-}" ]] || [[ -z "${3:-}" ]]; then
                log_error "Usage: $0 redis <snapshot-id> <target-name>"
                list_targets "redis"
                exit 1
            fi
            restore_redis "$2" "$3"
            ;;
        mongo)
            if [[ -z "${2:-}" ]] || [[ -z "${3:-}" ]] || [[ -z "${4:-}" ]]; then
                log_error "Usage: $0 mongo <snapshot-id> <target-name> <database>"
                list_targets "mongo"
                exit 1
            fi
            restore_mongo "$2" "$3" "$4"
            ;;
        nats)
            if [[ -z "${2:-}" ]] || [[ -z "${3:-}" ]]; then
                log_error "Usage: $0 nats <snapshot-id> <target-name>"
                list_targets "nats"
                exit 1
            fi
            restore_nats "$2" "$3"
            ;;
        volume)
            if [[ -z "${2:-}" ]] || [[ -z "${3:-}" ]]; then
                log_error "Usage: $0 volume <snapshot-id> <target-name>"
                list_targets "volumes"
                exit 1
            fi
            restore_volume "$2" "$3"
            ;;
        files)
            if [[ -z "${2:-}" ]] || [[ -z "${3:-}" ]]; then
                log_error "Usage: $0 files <snapshot-id> <path>"
                exit 1
            fi
            restore_files "$2" "$3"
            ;;
        help|*)
            echo ""
            echo "Restore Script - Usage:"
            echo ""
            echo "  $0 list                                    # List available snapshots"
            echo "  $0 show <snapshot-id>                      # Show snapshot contents"
            echo "  $0 postgres <snapshot-id> <target> <db>    # Restore PostgreSQL"
            echo "  $0 redis <snapshot-id> <target>            # Restore Redis"
            echo "  $0 mongo <snapshot-id> <target> <db>       # Restore MongoDB"
            echo "  $0 nats <snapshot-id> <target>             # Restore NATS JetStream"
            echo "  $0 volume <snapshot-id> <target>           # Restore volume"
            echo "  $0 files <snapshot-id> <path>              # Restore specific files"
            echo ""
            echo "Examples:"
            echo "  $0 list"
            echo "  $0 show latest"
            echo "  $0 postgres latest postgres-main mydb"
            echo "  $0 redis abc123 redis-main"
            echo "  $0 mongo latest mongo-rs app"
            echo "  $0 volume latest grafana-data"
            echo ""
            echo "Targets are defined in config/*.json files"
            echo "Use './manage-targets.sh list' to see available targets"
            echo ""
            ;;
    esac
}

main "$@"
