#!/bin/bash
# =============================================================================
# Common Library for Backup Scripts
# =============================================================================
# Provides shared functions for multi-mode backup support
# Modes: docker, kubectl, network, path
# =============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_debug() { [[ "${DEBUG:-false}" == "true" ]] && echo -e "${BLUE}[DEBUG]${NC} $1"; }

# -----------------------------------------------------------------------------
# Read JSON config file and return targets array
# Usage: read_targets "postgres"
# -----------------------------------------------------------------------------
read_targets() {
    local service="$1"
    local config_file="${BACKUP_ROOT}/config/${service}.json"

    if [[ ! -f "$config_file" ]]; then
        log_warn "Config file not found: $config_file"
        echo "[]"
        return
    fi

    # Return only enabled targets (filter out _examples)
    jq -c '.targets[]? | select(.enabled == true)' "$config_file" 2>/dev/null
}

# -----------------------------------------------------------------------------
# Get environment variable value by name
# Usage: get_env_value "POSTGRES_PASSWORD"
# -----------------------------------------------------------------------------
get_env_value() {
    local var_name="$1"
    echo "${!var_name:-}"
}

# -----------------------------------------------------------------------------
# Execute command in Docker container
# Usage: docker_exec "container_name" "command"
# -----------------------------------------------------------------------------
docker_exec() {
    local container="$1"
    shift
    docker exec "$container" "$@"
}

# -----------------------------------------------------------------------------
# Execute command in Kubernetes pod
# Usage: kubectl_exec "namespace" "pod" "command"
# -----------------------------------------------------------------------------
kubectl_exec() {
    local namespace="$1"
    local pod="$2"
    shift 2
    kubectl exec -n "$namespace" "$pod" -- "$@"
}

# -----------------------------------------------------------------------------
# Copy file from Docker container
# Usage: docker_cp "container:/path" "local_path"
# -----------------------------------------------------------------------------
docker_cp_from() {
    local src="$1"
    local dst="$2"
    docker cp "$src" "$dst"
}

# -----------------------------------------------------------------------------
# Copy file from Kubernetes pod
# Usage: kubectl_cp "namespace" "pod:/path" "local_path"
# -----------------------------------------------------------------------------
kubectl_cp_from() {
    local namespace="$1"
    local src="$2"
    local dst="$3"
    kubectl cp -n "$namespace" "$src" "$dst"
}

# -----------------------------------------------------------------------------
# Run pg_dump based on mode
# Usage: run_pg_dump "$target_json" "database" "output_file"
# -----------------------------------------------------------------------------
run_pg_dump() {
    local target="$1"
    local database="$2"
    local output="$3"

    local mode=$(echo "$target" | jq -r '.mode')
    local user=$(echo "$target" | jq -r '.user // "postgres"')
    local password_env=$(echo "$target" | jq -r '.password_env // ""')
    local password=$(get_env_value "$password_env")
    local is_timescaledb=$(echo "$target" | jq -r '.is_timescaledb // false')
    local ssl=$(echo "$target" | jq -r '.ssl // false')

    # pg_dump options
    local pg_opts="--no-owner --no-acl --clean --if-exists"
    [[ "$is_timescaledb" == "true" ]] && pg_opts="$pg_opts -Fc"

    case "$mode" in
        docker)
            local container=$(echo "$target" | jq -r '.container')
            export PGPASSWORD="$password"
            docker_exec "$container" pg_dump -h localhost -U "$user" -d "$database" $pg_opts 2>/dev/null | gzip > "$output"
            unset PGPASSWORD
            ;;

        kubectl)
            local namespace=$(echo "$target" | jq -r '.namespace')
            local pod=$(echo "$target" | jq -r '.pod')
            export PGPASSWORD="$password"
            kubectl_exec "$namespace" "$pod" pg_dump -h localhost -U "$user" -d "$database" $pg_opts 2>/dev/null | gzip > "$output"
            unset PGPASSWORD
            ;;

        network)
            local host=$(echo "$target" | jq -r '.host')
            local port=$(echo "$target" | jq -r '.port // 5432')
            local ssl_opt=""
            [[ "$ssl" == "true" ]] && ssl_opt="sslmode=require"

            export PGPASSWORD="$password"
            pg_dump -h "$host" -p "$port" -U "$user" -d "$database" $pg_opts 2>/dev/null | gzip > "$output"
            unset PGPASSWORD
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Run mysqldump based on mode
# Usage: run_mysqldump "$target_json" "database" "output_file"
# -----------------------------------------------------------------------------
run_mysqldump() {
    local target="$1"
    local database="$2"
    local output="$3"

    local mode=$(echo "$target" | jq -r '.mode')
    local user=$(echo "$target" | jq -r '.user // "root"')
    local password_env=$(echo "$target" | jq -r '.password_env // ""')
    local password=$(get_env_value "$password_env")

    # mysqldump options
    local mysql_opts="--single-transaction --routines --triggers --events"

    case "$mode" in
        docker)
            local container=$(echo "$target" | jq -r '.container')
            if [[ "$database" == "--all-databases" ]]; then
                docker_exec "$container" mysqldump -u "$user" -p"$password" --all-databases $mysql_opts 2>/dev/null | gzip > "$output"
            else
                docker_exec "$container" mysqldump -u "$user" -p"$password" "$database" $mysql_opts 2>/dev/null | gzip > "$output"
            fi
            ;;

        kubectl)
            local namespace=$(echo "$target" | jq -r '.namespace')
            local pod=$(echo "$target" | jq -r '.pod')
            if [[ "$database" == "--all-databases" ]]; then
                kubectl_exec "$namespace" "$pod" mysqldump -u "$user" -p"$password" --all-databases $mysql_opts 2>/dev/null | gzip > "$output"
            else
                kubectl_exec "$namespace" "$pod" mysqldump -u "$user" -p"$password" "$database" $mysql_opts 2>/dev/null | gzip > "$output"
            fi
            ;;

        network)
            local host=$(echo "$target" | jq -r '.host')
            local port=$(echo "$target" | jq -r '.port // 3306')
            if [[ "$database" == "--all-databases" ]]; then
                mysqldump -h "$host" -P "$port" -u "$user" -p"$password" --all-databases $mysql_opts 2>/dev/null | gzip > "$output"
            else
                mysqldump -h "$host" -P "$port" -u "$user" -p"$password" "$database" $mysql_opts 2>/dev/null | gzip > "$output"
            fi
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Run mongodump based on mode
# Usage: run_mongodump "$target_json" "database" "output_file"
# -----------------------------------------------------------------------------
run_mongodump() {
    local target="$1"
    local database="$2"
    local output="$3"

    local mode=$(echo "$target" | jq -r '.mode')
    local user=$(echo "$target" | jq -r '.user // ""')
    local password_env=$(echo "$target" | jq -r '.password_env // ""')
    local password=$(get_env_value "$password_env")
    local auth_db=$(echo "$target" | jq -r '.auth_db // "admin"')
    local replica_set=$(echo "$target" | jq -r '.replica_set // ""')

    # TLS options
    local tls_enabled=$(echo "$target" | jq -r '.tls.enabled // false')
    local tls_opts=""
    if [[ "$tls_enabled" == "true" ]]; then
        tls_opts="--ssl"
        local ca_file=$(echo "$target" | jq -r '.tls.ca_file // ""')
        [[ -n "$ca_file" ]] && tls_opts="$tls_opts --sslCAFile=$ca_file"
        local allow_invalid=$(echo "$target" | jq -r '.tls.allow_invalid // false')
        [[ "$allow_invalid" == "true" ]] && tls_opts="$tls_opts --sslAllowInvalidCertificates --sslAllowInvalidHostnames"
    fi

    # Auth options
    local auth_opts=""
    if [[ -n "$user" && -n "$password" ]]; then
        auth_opts="-u '$user' -p '$password' --authenticationDatabase '$auth_db'"
    fi

    # Replica set options
    local rs_opts=""
    [[ -n "$replica_set" ]] && rs_opts="--readPreference=secondaryPreferred"

    case "$mode" in
        docker)
            local container=$(echo "$target" | jq -r '.container')
            if [[ -n "$database" && "$database" != "all" ]]; then
                docker_exec "$container" bash -c "mongodump $auth_opts $tls_opts $rs_opts --db '$database' --archive --gzip" > "$output" 2>/dev/null
            else
                docker_exec "$container" bash -c "mongodump $auth_opts $tls_opts $rs_opts --archive --gzip" > "$output" 2>/dev/null
            fi
            ;;

        kubectl)
            local namespace=$(echo "$target" | jq -r '.namespace')
            local pod=$(echo "$target" | jq -r '.pod')
            if [[ -n "$database" && "$database" != "all" ]]; then
                kubectl_exec "$namespace" "$pod" bash -c "mongodump $auth_opts $tls_opts $rs_opts --db '$database' --archive --gzip" > "$output" 2>/dev/null
            else
                kubectl_exec "$namespace" "$pod" bash -c "mongodump $auth_opts $tls_opts $rs_opts --archive --gzip" > "$output" 2>/dev/null
            fi
            ;;

        network)
            local uri_env=$(echo "$target" | jq -r '.uri_env // ""')
            local uri=$(get_env_value "$uri_env")
            if [[ -n "$uri" ]]; then
                if [[ -n "$database" && "$database" != "all" ]]; then
                    mongodump --uri="$uri" --db="$database" --archive --gzip > "$output" 2>/dev/null
                else
                    mongodump --uri="$uri" --archive --gzip > "$output" 2>/dev/null
                fi
            fi
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Run Redis BGSAVE and copy dump based on mode
# Usage: run_redis_backup "$target_json" "output_file"
# -----------------------------------------------------------------------------
run_redis_backup() {
    local target="$1"
    local output="$2"

    local mode=$(echo "$target" | jq -r '.mode')
    local password_env=$(echo "$target" | jq -r '.password_env // ""')
    local password=$(get_env_value "$password_env")
    local auth_arg=""
    [[ -n "$password" ]] && auth_arg="--pass $password"

    case "$mode" in
        docker)
            local container=$(echo "$target" | jq -r '.container')

            # Trigger BGSAVE
            docker_exec "$container" redis-cli $auth_arg BGSAVE >/dev/null 2>&1
            sleep 3

            # Copy dump.rdb
            docker_cp_from "${container}:/data/dump.rdb" "${output%.gz}" 2>/dev/null
            gzip -f "${output%.gz}"
            ;;

        kubectl)
            local namespace=$(echo "$target" | jq -r '.namespace')
            local pod=$(echo "$target" | jq -r '.pod')

            kubectl_exec "$namespace" "$pod" redis-cli $auth_arg BGSAVE >/dev/null 2>&1
            sleep 3

            kubectl_cp_from "$namespace" "${pod}:/data/dump.rdb" "${output%.gz}"
            gzip -f "${output%.gz}"
            ;;

        network)
            local host=$(echo "$target" | jq -r '.host')
            local port=$(echo "$target" | jq -r '.port // 6379')
            local tls=$(echo "$target" | jq -r '.tls // false')
            local tls_opt=""
            [[ "$tls" == "true" ]] && tls_opt="--tls"

            redis-cli -h "$host" -p "$port" $auth_arg $tls_opt BGSAVE >/dev/null 2>&1
            log_warn "Network Redis backup: BGSAVE triggered, but cannot copy dump file remotely"
            log_warn "Use Redis replication or RDB file access for network backups"
            return 1
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Backup Docker volume or K8s PVC
# Usage: run_volume_backup "$target_json" "output_file"
# -----------------------------------------------------------------------------
run_volume_backup() {
    local target="$1"
    local output="$2"

    local mode=$(echo "$target" | jq -r '.mode')
    local name=$(echo "$target" | jq -r '.name')

    case "$mode" in
        docker)
            local volume=$(echo "$target" | jq -r '.volume')
            docker run --rm \
                -v "${volume}:/source:ro" \
                -v "$(dirname "$output"):/backup" \
                alpine tar -czf "/backup/$(basename "$output")" -C /source . 2>/dev/null
            ;;

        kubectl)
            local namespace=$(echo "$target" | jq -r '.namespace')
            local pod=$(echo "$target" | jq -r '.pod')
            local mount_path=$(echo "$target" | jq -r '.mount_path')

            kubectl_exec "$namespace" "$pod" tar -czf - -C "$mount_path" . > "$output" 2>/dev/null
            ;;

        path)
            local path=$(echo "$target" | jq -r '.path')
            tar -czf "$output" -C "$(dirname "$path")" "$(basename "$path")" 2>/dev/null
            ;;
    esac
}
