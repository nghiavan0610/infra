#!/bin/bash
# =============================================================================
# Backup Script - Production
# =============================================================================
# Backs up all enabled targets from config/*.json and uploads to Restic
#
# Usage:
#   ./backup.sh              # Full backup (all enabled targets)
#   ./backup.sh databases    # Databases only
#   ./backup.sh volumes      # Volumes only
#   ./backup.sh postgres     # PostgreSQL only
#   ./backup.sh mysql        # MySQL only
#   ./backup.sh redis        # Redis only
#   ./backup.sh mongo        # MongoDB only
#   ./backup.sh nats         # NATS only
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment (skip if running in Docker with env vars already set)
if [[ -z "${RESTIC_PASSWORD:-}" ]]; then
    if [[ -f "${BACKUP_ROOT}/.env" ]]; then
        set -a
        source "${BACKUP_ROOT}/.env"
        set +a
    else
        echo "ERROR: RESTIC_PASSWORD not set and ${BACKUP_ROOT}/.env not found"
        exit 1
    fi
fi

# Load common library
source "${SCRIPT_DIR}/lib-common.sh"

# Defaults
BACKUP_DIR="${BACKUP_DIR:-/tmp/backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${BACKUP_ROOT}/logs/backup_${TIMESTAMP}.log"

# Logging to file
mkdir -p "$(dirname "$LOG_FILE")"
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

log_section() { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }

# Track status
BACKUP_STATUS="success"
FAILED_COMPONENTS=()

# -----------------------------------------------------------------------------
# Check Prerequisites
# -----------------------------------------------------------------------------
check_prerequisites() {
    log_section "Checking Prerequisites"

    if ! command -v restic &>/dev/null; then
        log_error "Restic is not installed"
        exit 1
    fi
    log_info "Restic: $(restic version | head -1)"

    if ! command -v jq &>/dev/null; then
        log_error "jq is not installed"
        exit 1
    fi
    log_info "jq: found"

    if command -v docker &>/dev/null; then
        log_info "Docker: found"
    fi

    if command -v kubectl &>/dev/null; then
        log_info "kubectl: found"
    fi

    if [[ -z "${RESTIC_REPOSITORY:-}" ]]; then
        log_error "RESTIC_REPOSITORY not set"
        exit 1
    fi
    log_info "Repository: ${RESTIC_REPOSITORY}"

    # Initialize repository if needed
    if ! restic snapshots &>/dev/null 2>&1; then
        log_info "Initializing Restic repository..."
        restic init
    fi
}

# -----------------------------------------------------------------------------
# Backup PostgreSQL
# -----------------------------------------------------------------------------
backup_postgres() {
    local filter="${1:-}"
    local dump_dir="${BACKUP_DIR}/postgres"
    mkdir -p "$dump_dir"

    while IFS= read -r target; do
        [[ -z "$target" ]] && continue

        local name=$(echo "$target" | jq -r '.name')
        [[ -n "$filter" && "$name" != "$filter" ]] && continue

        local mode=$(echo "$target" | jq -r '.mode')
        local databases=$(echo "$target" | jq -r '.databases[]?' 2>/dev/null)
        local is_timescaledb=$(echo "$target" | jq -r '.is_timescaledb // false')

        log_info "PostgreSQL: $name (mode: $mode)"

        [[ -z "$databases" ]] && databases="postgres"

        for db in $databases; do
            local ext="sql.gz"
            [[ "$is_timescaledb" == "true" ]] && ext="dump.gz"
            local dump_file="${dump_dir}/${name}_${db}_${TIMESTAMP}.${ext}"

            if run_pg_dump "$target" "$db" "$dump_file" && [[ -s "$dump_file" ]]; then
                log_info "  $db: $(du -h "$dump_file" | cut -f1)"
            else
                rm -f "$dump_file"
                log_error "  $db: failed"
                return 1
            fi
        done
    done < <(read_targets "postgres")
}

# -----------------------------------------------------------------------------
# Backup Redis
# -----------------------------------------------------------------------------
backup_redis() {
    local filter="${1:-}"
    local dump_dir="${BACKUP_DIR}/redis"
    mkdir -p "$dump_dir"

    while IFS= read -r target; do
        [[ -z "$target" ]] && continue

        local name=$(echo "$target" | jq -r '.name')
        [[ -n "$filter" && "$name" != "$filter" ]] && continue

        local mode=$(echo "$target" | jq -r '.mode')
        log_info "Redis: $name (mode: $mode)"

        local dump_file="${dump_dir}/${name}_${TIMESTAMP}.rdb.gz"

        if run_redis_backup "$target" "$dump_file" && [[ -s "$dump_file" ]]; then
            log_info "  dump: $(du -h "$dump_file" | cut -f1)"
        else
            rm -f "$dump_file"
            log_error "  dump: failed"
            return 1
        fi
    done < <(read_targets "redis")
}

# -----------------------------------------------------------------------------
# Backup MongoDB
# -----------------------------------------------------------------------------
backup_mongo() {
    local filter="${1:-}"
    local dump_dir="${BACKUP_DIR}/mongo"
    mkdir -p "$dump_dir"

    while IFS= read -r target; do
        [[ -z "$target" ]] && continue

        local name=$(echo "$target" | jq -r '.name')
        [[ -n "$filter" && "$name" != "$filter" ]] && continue

        local mode=$(echo "$target" | jq -r '.mode')
        local databases=$(echo "$target" | jq -r '.databases[]?' 2>/dev/null)

        log_info "MongoDB: $name (mode: $mode)"

        [[ -z "$databases" ]] && databases="all"

        for db in $databases; do
            [[ "$db" == "admin" || "$db" == "local" || "$db" == "config" ]] && continue

            local dump_file="${dump_dir}/${name}_${db}_${TIMESTAMP}.archive.gz"

            if run_mongodump "$target" "$db" "$dump_file" && [[ -s "$dump_file" ]]; then
                log_info "  $db: $(du -h "$dump_file" | cut -f1)"
            else
                rm -f "$dump_file"
                log_error "  $db: failed"
                return 1
            fi
        done
    done < <(read_targets "mongo")
}

# -----------------------------------------------------------------------------
# Backup MySQL
# -----------------------------------------------------------------------------
backup_mysql() {
    local filter="${1:-}"
    local dump_dir="${BACKUP_DIR}/mysql"
    mkdir -p "$dump_dir"

    while IFS= read -r target; do
        [[ -z "$target" ]] && continue

        local name=$(echo "$target" | jq -r '.name')
        [[ -n "$filter" && "$name" != "$filter" ]] && continue

        local mode=$(echo "$target" | jq -r '.mode')
        local databases=$(echo "$target" | jq -r '.databases[]?' 2>/dev/null)

        log_info "MySQL: $name (mode: $mode)"

        [[ -z "$databases" ]] && databases="--all-databases"

        for db in $databases; do
            local dump_file="${dump_dir}/${name}_${db}_${TIMESTAMP}.sql.gz"

            if run_mysqldump "$target" "$db" "$dump_file" && [[ -s "$dump_file" ]]; then
                log_info "  $db: $(du -h "$dump_file" | cut -f1)"
            else
                rm -f "$dump_file"
                log_error "  $db: failed"
                return 1
            fi
        done
    done < <(read_targets "mysql")
}

# -----------------------------------------------------------------------------
# Backup NATS
# -----------------------------------------------------------------------------
backup_nats() {
    local filter="${1:-}"
    local dump_dir="${BACKUP_DIR}/nats"
    mkdir -p "$dump_dir"

    while IFS= read -r target; do
        [[ -z "$target" ]] && continue

        local name=$(echo "$target" | jq -r '.name')
        [[ -n "$filter" && "$name" != "$filter" ]] && continue

        local mode=$(echo "$target" | jq -r '.mode')
        local data_dir=$(echo "$target" | jq -r '.data_dir // "/data/jetstream"')

        log_info "NATS: $name (mode: $mode)"

        local dump_file="${dump_dir}/${name}_${TIMESTAMP}.tar.gz"

        case "$mode" in
            docker)
                local container=$(echo "$target" | jq -r '.container')
                if docker_exec "$container" test -d "$data_dir" 2>/dev/null; then
                    docker_exec "$container" tar -czf - -C "$(dirname "$data_dir")" "$(basename "$data_dir")" > "$dump_file" 2>/dev/null
                fi
                ;;
            kubectl)
                local namespace=$(echo "$target" | jq -r '.namespace')
                local pod=$(echo "$target" | jq -r '.pod')
                if kubectl_exec "$namespace" "$pod" test -d "$data_dir" 2>/dev/null; then
                    kubectl_exec "$namespace" "$pod" tar -czf - -C "$(dirname "$data_dir")" "$(basename "$data_dir")" > "$dump_file" 2>/dev/null
                fi
                ;;
        esac

        if [[ -s "$dump_file" ]]; then
            log_info "  jetstream: $(du -h "$dump_file" | cut -f1)"
        else
            rm -f "$dump_file"
            log_warn "  jetstream: empty or not found"
        fi
    done < <(read_targets "nats")
}

# -----------------------------------------------------------------------------
# Backup Qdrant (via snapshots API)
# -----------------------------------------------------------------------------
backup_qdrant() {
    local filter="${1:-}"
    local dump_dir="${BACKUP_DIR}/qdrant"
    mkdir -p "$dump_dir"

    while IFS= read -r target; do
        [[ -z "$target" ]] && continue

        local name=$(echo "$target" | jq -r '.name')
        [[ -n "$filter" && "$name" != "$filter" ]] && continue

        local mode=$(echo "$target" | jq -r '.mode')
        local host=$(echo "$target" | jq -r '.host // "qdrant"')
        local port=$(echo "$target" | jq -r '.port // "6333"')
        local api_key=$(echo "$target" | jq -r '.api_key // ""')

        log_info "Qdrant: $name (mode: $mode)"

        # Get all collections
        local auth_header=""
        [[ -n "$api_key" ]] && auth_header="-H 'api-key: ${api_key}'"

        local collections=$(curl -s ${auth_header} "http://${host}:${port}/collections" | jq -r '.result.collections[].name' 2>/dev/null)

        for collection in $collections; do
            [[ -z "$collection" ]] && continue

            local snapshot_name="${collection}_${TIMESTAMP}"
            local dump_file="${dump_dir}/${name}_${collection}_${TIMESTAMP}.snapshot"

            log_info "  Creating snapshot: $collection"

            # Create snapshot via API
            local snapshot_result=$(curl -s -X POST ${auth_header} "http://${host}:${port}/collections/${collection}/snapshots")
            local snapshot_file=$(echo "$snapshot_result" | jq -r '.result.name' 2>/dev/null)

            if [[ -n "$snapshot_file" && "$snapshot_file" != "null" ]]; then
                # Download snapshot
                curl -s ${auth_header} "http://${host}:${port}/collections/${collection}/snapshots/${snapshot_file}" -o "$dump_file"

                if [[ -s "$dump_file" ]]; then
                    gzip "$dump_file"
                    log_info "    $collection: $(du -h "${dump_file}.gz" | cut -f1)"
                else
                    rm -f "$dump_file"
                    log_warn "    $collection: empty snapshot"
                fi
            else
                log_error "    $collection: snapshot failed"
            fi
        done
    done < <(read_targets "qdrant")
}

# -----------------------------------------------------------------------------
# Backup Volumes
# -----------------------------------------------------------------------------
backup_volumes() {
    local filter="${1:-}"
    local dump_dir="${BACKUP_DIR}/volumes"
    mkdir -p "$dump_dir"

    while IFS= read -r target; do
        [[ -z "$target" ]] && continue

        local name=$(echo "$target" | jq -r '.name')
        [[ -n "$filter" && "$name" != "$filter" ]] && continue

        local mode=$(echo "$target" | jq -r '.mode')
        log_info "Volume: $name (mode: $mode)"

        local dump_file="${dump_dir}/${name}_${TIMESTAMP}.tar.gz"

        if run_volume_backup "$target" "$dump_file" && [[ -s "$dump_file" ]]; then
            log_info "  data: $(du -h "$dump_file" | cut -f1)"
        else
            rm -f "$dump_file"
            log_error "  data: failed"
            return 1
        fi
    done < <(read_targets "volumes")
}

# -----------------------------------------------------------------------------
# Run backup for a service type
# -----------------------------------------------------------------------------
run_service_backup() {
    local service="$1"
    local config_file="${BACKUP_ROOT}/config/${service}.json"

    if [[ ! -f "$config_file" ]]; then
        return 0
    fi

    local count=$(jq '[.targets[]? | select(.enabled == true)] | length' "$config_file" 2>/dev/null || echo 0)
    if [[ "$count" -eq 0 ]]; then
        return 0
    fi

    log_info "Backing up ${service} ($count targets)..."

    case "$service" in
        postgres) backup_postgres ;;
        mysql) backup_mysql ;;
        redis) backup_redis ;;
        mongo) backup_mongo ;;
        nats) backup_nats ;;
        qdrant) backup_qdrant ;;
        volumes) backup_volumes ;;
    esac
}

# -----------------------------------------------------------------------------
# Upload to Restic
# -----------------------------------------------------------------------------
upload_to_restic() {
    log_section "Uploading to Restic"

    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
        log_warn "No backup files to upload"
        return 0
    fi

    if restic backup --tag "automated" --tag "$(date +%Y-%m-%d)" --host "$(hostname)" "${BACKUP_DIR}"; then
        log_info "Snapshot created"
        restic snapshots --last 3
    else
        log_error "Failed to create snapshot"
        BACKUP_STATUS="failed"
        FAILED_COMPONENTS+=("Restic")
    fi
}

# -----------------------------------------------------------------------------
# Apply Retention
# -----------------------------------------------------------------------------
apply_retention() {
    log_section "Applying Retention"

    restic forget \
        --keep-hourly "${RETENTION_HOURLY:-24}" \
        --keep-daily "${RETENTION_DAILY:-7}" \
        --keep-weekly "${RETENTION_WEEKLY:-4}" \
        --keep-monthly "${RETENTION_MONTHLY:-6}" \
        --keep-yearly "${RETENTION_YEARLY:-2}" \
        --prune || log_warn "Retention policy failed"
}

# -----------------------------------------------------------------------------
# Cleanup
# -----------------------------------------------------------------------------
cleanup() {
    log_section "Cleanup"
    rm -rf "${BACKUP_DIR:?}"/*
    find "${BACKUP_ROOT}/logs" -name "backup_*.log" -mtime +30 -delete 2>/dev/null || true
    log_info "Done"
}

# -----------------------------------------------------------------------------
# Notification
# -----------------------------------------------------------------------------
send_notification() {
    local duration=$1
    local message

    if [[ "$BACKUP_STATUS" == "success" ]]; then
        message="Backup completed in ${duration}s"
    else
        message="Backup failed after ${duration}s: ${FAILED_COMPONENTS[*]}"
    fi

    log_info "$message"

    # Ntfy notification (primary)
    if [[ -n "${NTFY_URL:-}" ]]; then
        local priority="default"
        local title="Backup Completed"
        local tags="white_check_mark"

        if [[ "$BACKUP_STATUS" == "failed" ]]; then
            priority="urgent"
            title="Backup Failed"
            tags="x"
        fi

        curl -s -X POST "$NTFY_URL" \
            -H "Title: $title" \
            -H "Priority: $priority" \
            -H "Tags: $tags" \
            -d "$message" || true
    fi

    # Slack notification
    [[ -n "${SLACK_WEBHOOK_URL:-}" ]] && \
        curl -s -X POST -H 'Content-type: application/json' --data "{\"text\":\"$message\"}" "$SLACK_WEBHOOK_URL" || true

    # Discord notification
    [[ -n "${DISCORD_WEBHOOK_URL:-}" ]] && \
        curl -s -X POST -H 'Content-type: application/json' --data "{\"content\":\"$message\"}" "$DISCORD_WEBHOOK_URL" || true
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    local start_time=$(date +%s)
    local target="${1:-all}"

    echo ""
    echo "=============================================="
    echo "  Backup: $(date)"
    echo "  Target: $target"
    echo "=============================================="

    mkdir -p "$BACKUP_DIR"
    check_prerequisites

    case "$target" in
        all)
            log_section "Databases"
            run_service_backup "postgres"
            run_service_backup "mysql"
            run_service_backup "redis"
            run_service_backup "mongo"
            run_service_backup "nats"
            log_section "Vector"
            run_service_backup "qdrant"
            log_section "Volumes"
            run_service_backup "volumes"
            ;;
        databases|db)
            log_section "Databases"
            run_service_backup "postgres"
            run_service_backup "mysql"
            run_service_backup "redis"
            run_service_backup "mongo"
            run_service_backup "nats"
            ;;
        volumes|vol)
            log_section "Volumes"
            run_service_backup "volumes"
            ;;
        postgres|pg)
            log_section "PostgreSQL"
            backup_postgres
            ;;
        mysql)
            log_section "MySQL"
            backup_mysql
            ;;
        redis)
            log_section "Redis"
            backup_redis
            ;;
        mongo|mongodb)
            log_section "MongoDB"
            backup_mongo
            ;;
        nats)
            log_section "NATS"
            backup_nats
            ;;
        qdrant)
            log_section "Qdrant"
            backup_qdrant
            ;;
        *)
            echo "Usage: $0 [all|databases|volumes|postgres|mysql|redis|mongo|nats|qdrant]"
            exit 1
            ;;
    esac

    upload_to_restic
    apply_retention
    cleanup

    local duration=$(($(date +%s) - start_time))
    send_notification "$duration"

    echo ""
    echo "=============================================="
    echo "  Completed: ${duration}s | Status: ${BACKUP_STATUS}"
    echo "  Log: ${LOG_FILE}"
    echo "=============================================="

    [[ "$BACKUP_STATUS" == "failed" ]] && exit 1
    exit 0
}

trap 'log_error "Failed at line $LINENO"' ERR
main "$@"
