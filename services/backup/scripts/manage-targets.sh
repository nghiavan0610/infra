#!/bin/bash
# =============================================================================
# Backup Targets Management Script
# =============================================================================
# Manage backup targets in config/*.json files
#
# Usage:
#   ./manage-targets.sh list [service]           # List all targets
#   ./manage-targets.sh enable <service> <name>  # Enable a target
#   ./manage-targets.sh disable <service> <name> # Disable a target
#   ./manage-targets.sh add <service> [options]  # Add new target
#   ./manage-targets.sh remove <service> <name>  # Remove a target
#   ./manage-targets.sh show <service> <name>    # Show target details
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="${BACKUP_ROOT}/config"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Services
SERVICES=("postgres" "redis" "mongo" "nats" "volumes")

# -----------------------------------------------------------------------------
# List targets
# -----------------------------------------------------------------------------
list_targets() {
    local service="$1"

    if [[ -n "$service" ]]; then
        list_service_targets "$service"
    else
        for svc in "${SERVICES[@]}"; do
            list_service_targets "$svc"
        done
    fi
}

list_service_targets() {
    local service="$1"
    local config_file="${CONFIG_DIR}/${service}.json"

    if [[ ! -f "$config_file" ]]; then
        return
    fi

    echo -e "\n${BLUE}=== ${service^^} ===${NC}"

    local targets=$(jq -c '.targets[]?' "$config_file" 2>/dev/null)

    if [[ -z "$targets" ]]; then
        echo "  No targets configured"
        return
    fi

    while IFS= read -r target; do
        local name=$(echo "$target" | jq -r '.name')
        local enabled=$(echo "$target" | jq -r '.enabled')
        local mode=$(echo "$target" | jq -r '.mode')

        if [[ "$enabled" == "true" ]]; then
            echo -e "  ${GREEN}[✓]${NC} $name (mode: $mode)"
        else
            echo -e "  ${RED}[✗]${NC} $name (mode: $mode)"
        fi
    done <<< "$targets"
}

# -----------------------------------------------------------------------------
# Enable/Disable target
# -----------------------------------------------------------------------------
toggle_target() {
    local action="$1"
    local service="$2"
    local name="$3"
    local config_file="${CONFIG_DIR}/${service}.json"

    if [[ ! -f "$config_file" ]]; then
        echo -e "${RED}Config not found: $config_file${NC}"
        exit 1
    fi

    local enabled="true"
    [[ "$action" == "disable" ]] && enabled="false"

    # Check if target exists
    local exists=$(jq --arg name "$name" '.targets[] | select(.name == $name)' "$config_file")
    if [[ -z "$exists" ]]; then
        echo -e "${RED}Target not found: $name${NC}"
        exit 1
    fi

    # Update enabled status
    local tmp=$(mktemp)
    jq --arg name "$name" --argjson enabled "$enabled" \
        '(.targets[] | select(.name == $name)).enabled = $enabled' \
        "$config_file" > "$tmp" && mv "$tmp" "$config_file"

    if [[ "$enabled" == "true" ]]; then
        echo -e "${GREEN}Enabled${NC} $service target: $name"
    else
        echo -e "${YELLOW}Disabled${NC} $service target: $name"
    fi
}

# -----------------------------------------------------------------------------
# Add target
# -----------------------------------------------------------------------------
add_target() {
    local service="$1"
    shift

    local config_file="${CONFIG_DIR}/${service}.json"

    # Parse options
    local name="" mode="docker" container="" host="" port="" user="" password_env=""
    local databases="" namespace="" pod="" replica_set="" tls="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name) name="$2"; shift 2 ;;
            --mode) mode="$2"; shift 2 ;;
            --container) container="$2"; shift 2 ;;
            --host) host="$2"; shift 2 ;;
            --port) port="$2"; shift 2 ;;
            --user) user="$2"; shift 2 ;;
            --password-env) password_env="$2"; shift 2 ;;
            --databases) databases="$2"; shift 2 ;;
            --namespace) namespace="$2"; shift 2 ;;
            --pod) pod="$2"; shift 2 ;;
            --replica-set) replica_set="$2"; shift 2 ;;
            --tls) tls="true"; shift ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
    done

    if [[ -z "$name" ]]; then
        echo "Error: --name is required"
        exit 1
    fi

    # Create config file if not exists
    if [[ ! -f "$config_file" ]]; then
        echo '{"targets": []}' > "$config_file"
    fi

    # Check if target already exists
    local exists=$(jq --arg name "$name" '.targets[] | select(.name == $name)' "$config_file")
    if [[ -n "$exists" ]]; then
        echo -e "${YELLOW}Target already exists: $name${NC}"
        exit 1
    fi

    # Build target JSON based on service type
    local target_json=""

    case "$service" in
        postgres)
            local dbs_json="[]"
            if [[ -n "$databases" ]]; then
                dbs_json=$(echo "$databases" | jq -R 'split(",")')
            fi

            case "$mode" in
                docker)
                    target_json=$(jq -n \
                        --arg name "$name" \
                        --arg container "${container:-postgres}" \
                        --argjson databases "$dbs_json" \
                        --arg user "${user:-postgres}" \
                        --arg password_env "$password_env" \
                        '{name: $name, enabled: true, mode: "docker", container: $container, databases: $databases, user: $user, password_env: $password_env}')
                    ;;
                kubectl)
                    target_json=$(jq -n \
                        --arg name "$name" \
                        --arg namespace "$namespace" \
                        --arg pod "$pod" \
                        --argjson databases "$dbs_json" \
                        --arg user "${user:-postgres}" \
                        --arg password_env "$password_env" \
                        '{name: $name, enabled: true, mode: "kubectl", namespace: $namespace, pod: $pod, databases: $databases, user: $user, password_env: $password_env}')
                    ;;
                network)
                    target_json=$(jq -n \
                        --arg name "$name" \
                        --arg host "$host" \
                        --argjson port "${port:-5432}" \
                        --argjson databases "$dbs_json" \
                        --arg user "${user:-postgres}" \
                        --arg password_env "$password_env" \
                        --argjson ssl "$tls" \
                        '{name: $name, enabled: true, mode: "network", host: $host, port: $port, databases: $databases, user: $user, password_env: $password_env, ssl: $ssl}')
                    ;;
            esac
            ;;

        redis)
            case "$mode" in
                docker)
                    target_json=$(jq -n \
                        --arg name "$name" \
                        --arg container "${container:-redis}" \
                        --arg password_env "$password_env" \
                        '{name: $name, enabled: true, mode: "docker", container: $container, password_env: $password_env}')
                    ;;
                kubectl)
                    target_json=$(jq -n \
                        --arg name "$name" \
                        --arg namespace "$namespace" \
                        --arg pod "$pod" \
                        --arg password_env "$password_env" \
                        '{name: $name, enabled: true, mode: "kubectl", namespace: $namespace, pod: $pod, password_env: $password_env}')
                    ;;
            esac
            ;;

        mongo)
            local dbs_json="[]"
            if [[ -n "$databases" ]]; then
                dbs_json=$(echo "$databases" | jq -R 'split(",")')
            fi

            case "$mode" in
                docker)
                    target_json=$(jq -n \
                        --arg name "$name" \
                        --arg container "${container:-mongo-primary}" \
                        --argjson databases "$dbs_json" \
                        --arg user "${user:-admin}" \
                        --arg password_env "$password_env" \
                        --arg replica_set "$replica_set" \
                        --argjson tls_enabled "$tls" \
                        '{name: $name, enabled: true, mode: "docker", container: $container, databases: $databases, user: $user, password_env: $password_env, auth_db: "admin", replica_set: $replica_set, tls: {enabled: $tls_enabled}}')
                    ;;
            esac
            ;;

        volumes)
            case "$mode" in
                docker)
                    target_json=$(jq -n \
                        --arg name "$name" \
                        --arg volume "${container}" \
                        '{name: $name, enabled: true, mode: "docker", volume: $volume}')
                    ;;
                path)
                    target_json=$(jq -n \
                        --arg name "$name" \
                        --arg path "$host" \
                        '{name: $name, enabled: true, mode: "path", path: $path}')
                    ;;
            esac
            ;;
    esac

    if [[ -z "$target_json" ]]; then
        echo "Error: Could not create target configuration"
        exit 1
    fi

    # Add target to config
    local tmp=$(mktemp)
    jq --argjson target "$target_json" '.targets += [$target]' "$config_file" > "$tmp" && mv "$tmp" "$config_file"

    echo -e "${GREEN}Added${NC} $service target: $name"
}

# -----------------------------------------------------------------------------
# Remove target
# -----------------------------------------------------------------------------
remove_target() {
    local service="$1"
    local name="$2"
    local config_file="${CONFIG_DIR}/${service}.json"

    if [[ ! -f "$config_file" ]]; then
        echo -e "${RED}Config not found: $config_file${NC}"
        exit 1
    fi

    local tmp=$(mktemp)
    jq --arg name "$name" '.targets = [.targets[] | select(.name != $name)]' "$config_file" > "$tmp" && mv "$tmp" "$config_file"

    echo -e "${YELLOW}Removed${NC} $service target: $name"
}

# -----------------------------------------------------------------------------
# Show target details
# -----------------------------------------------------------------------------
show_target() {
    local service="$1"
    local name="$2"
    local config_file="${CONFIG_DIR}/${service}.json"

    if [[ ! -f "$config_file" ]]; then
        echo -e "${RED}Config not found: $config_file${NC}"
        exit 1
    fi

    jq --arg name "$name" '.targets[] | select(.name == $name)' "$config_file"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    local command="${1:-list}"

    case "$command" in
        list|ls)
            list_targets "${2:-}"
            ;;
        enable)
            if [[ -z "${2:-}" || -z "${3:-}" ]]; then
                echo "Usage: $0 enable <service> <name>"
                exit 1
            fi
            toggle_target "enable" "$2" "$3"
            ;;
        disable)
            if [[ -z "${2:-}" || -z "${3:-}" ]]; then
                echo "Usage: $0 disable <service> <name>"
                exit 1
            fi
            toggle_target "disable" "$2" "$3"
            ;;
        add)
            if [[ -z "${2:-}" ]]; then
                echo "Usage: $0 add <service> --name <name> [options]"
                echo ""
                echo "Services: postgres, redis, mongo, nats, volumes"
                echo ""
                echo "Options:"
                echo "  --name         Target name (required)"
                echo "  --mode         Connection mode: docker, kubectl, network, path"
                echo "  --container    Docker container name"
                echo "  --host         Hostname for network mode"
                echo "  --port         Port number"
                echo "  --user         Database username"
                echo "  --password-env Environment variable name for password"
                echo "  --databases    Comma-separated list of databases"
                echo "  --namespace    Kubernetes namespace"
                echo "  --pod          Kubernetes pod name"
                echo "  --replica-set  MongoDB replica set name"
                echo "  --tls          Enable TLS"
                echo ""
                echo "Examples:"
                echo "  $0 add postgres --name pg-main --container postgres --databases mydb --password-env PG_PASSWORD"
                echo "  $0 add redis --name redis-cache --container redis-cache --password-env REDIS_PASSWORD"
                echo "  $0 add mongo --name mongo-rs --container mongo-primary --databases app --replica-set rs0 --tls"
                echo "  $0 add volumes --name grafana --mode docker --container grafana_data"
                exit 1
            fi
            shift
            add_target "$@"
            ;;
        remove|rm)
            if [[ -z "${2:-}" || -z "${3:-}" ]]; then
                echo "Usage: $0 remove <service> <name>"
                exit 1
            fi
            remove_target "$2" "$3"
            ;;
        show)
            if [[ -z "${2:-}" || -z "${3:-}" ]]; then
                echo "Usage: $0 show <service> <name>"
                exit 1
            fi
            show_target "$2" "$3"
            ;;
        *)
            echo "Backup Targets Manager"
            echo ""
            echo "Usage: $0 <command> [options]"
            echo ""
            echo "Commands:"
            echo "  list [service]            List all targets"
            echo "  enable <service> <name>   Enable a target"
            echo "  disable <service> <name>  Disable a target"
            echo "  add <service> [options]   Add new target"
            echo "  remove <service> <name>   Remove a target"
            echo "  show <service> <name>     Show target details"
            echo ""
            echo "Services: postgres, redis, mongo, nats, volumes"
            ;;
    esac
}

main "$@"
