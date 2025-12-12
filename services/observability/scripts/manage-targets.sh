#!/bin/bash
# =============================================================================
# Manage Prometheus Scrape Targets
# =============================================================================
# Dynamically add/remove monitoring targets for all services.
# Changes take effect within 30 seconds (no restart needed).
#
# Supported services:
#   - postgres    PostgreSQL databases
#   - redis       Redis instances
#   - rabbitmq    RabbitMQ servers
#   - nats        NATS servers
#   - app         Application services
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGETS_DIR="$SCRIPT_DIR/../targets"

# Require authentication
INFRA_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$INFRA_ROOT/lib/common.sh"
require_auth

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Service configurations
# Format: "file:label_key:default_port:service_label"
# Note: Most services are monitored directly by Alloy (no file_sd_configs needed)
# Configure via .env: REDIS_*, POSTGRES_DSN, MONGODB_URI, MYSQL_DSN, etc.
#
# Only these services still use file_sd_configs:
#   - garage: requires bearer token authentication
#   - langfuse: custom /api/public/metrics endpoint
#   - applications: user-defined custom apps
declare -A SERVICES=(
    ["garage"]="garage.json:instance:3903:garage"
    ["langfuse"]="langfuse.json:instance:3000:langfuse"
    ["app"]="applications.json:app:9090:application"
    ["application"]="applications.json:app:9090:application"
)

usage() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Prometheus Target Manager${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BLUE}Usage:${NC}"
    echo "  $0 <command> <service> [options]"
    echo ""
    echo -e "${BLUE}Commands:${NC}"
    echo "  add       Add a new target"
    echo "  remove    Remove a target"
    echo "  list      List all targets for a service"
    echo "  list-all  List all targets for all services"
    echo ""
    echo -e "${BLUE}Services:${NC}"
    echo "  postgres    PostgreSQL exporter (default port: 9187)"
    echo "  timescaledb TimescaleDB exporter (default port: 9187, uses postgres alerts)"
    echo "  redis       Redis instance (default port: 6379)"
    echo "  rabbitmq    RabbitMQ server (default port: 15692)"
    echo "  nats        NATS server (default port: 8222)"
    echo "  mongodb     MongoDB exporter (default port: 9216)"
    echo "  traefik     Traefik metrics (default port: 8080)"
    echo "  garage      Garage S3 storage (default port: 3903)"
    echo "  app         Application metrics (default port: 9090)"
    echo ""
    echo -e "${BLUE}Options:${NC}"
    echo "  --name     Target name (required)"
    echo "  --host     Target host (default: host.docker.internal)"
    echo "  --port     Target port (uses service default if not specified)"
    echo "  --type     Instance type label (optional, e.g., primary, replica, cache)"
    echo ""
    echo -e "${BLUE}Examples:${NC}"
    echo -e "  ${GREEN}# PostgreSQL${NC}"
    echo "  $0 add postgres --name prod-db --host 10.0.0.1 --port 9187 --type primary"
    echo "  $0 add postgres --name replica-db --host 10.0.0.2 --type replica"
    echo ""
    echo -e "  ${GREEN}# Redis${NC}"
    echo "  $0 add redis --name redis-cache --host 10.0.0.3 --port 6379 --type cache"
    echo "  $0 add redis --name redis-queue --port 6380 --type queue"
    echo ""
    echo -e "  ${GREEN}# RabbitMQ${NC}"
    echo "  $0 add rabbitmq --name rabbit-main --host 10.0.0.4 --port 15692"
    echo ""
    echo -e "  ${GREEN}# NATS${NC}"
    echo "  $0 add nats --name nats-main --host 10.0.0.5 --port 8222"
    echo ""
    echo -e "  ${GREEN}# MongoDB${NC}"
    echo "  $0 add mongodb --name mongo-main --host 10.0.0.6 --port 9216"
    echo ""
    echo -e "  ${GREEN}# Traefik${NC}"
    echo "  $0 add traefik --name traefik-main --host 10.0.0.7 --port 8080"
    echo ""
    echo -e "  ${GREEN}# Garage (S3 storage)${NC}"
    echo "  $0 add garage --name garage-main --host 10.0.0.8 --port 3903"
    echo ""
    echo -e "  ${GREEN}# TimescaleDB (uses PostgreSQL exporter)${NC}"
    echo "  $0 add timescaledb --name tsdb-main --host 10.0.0.9 --port 9187"
    echo ""
    echo -e "  ${GREEN}# Application${NC}"
    echo "  $0 add app --name my-api --host 10.0.0.10 --port 9090"
    echo ""
    echo -e "  ${GREEN}# List & Remove${NC}"
    echo "  $0 list postgres"
    echo "  $0 list-all"
    echo "  $0 remove redis --name redis-cache"
    echo ""
    exit 1
}

get_service_config() {
    local service=$1
    local config="${SERVICES[$service]}"

    if [[ -z "$config" ]]; then
        echo -e "${RED}Error: Unknown service '$service'${NC}"
        echo "Supported services: postgres, redis, rabbitmq, nats, app"
        exit 1
    fi

    echo "$config"
}

list_targets() {
    local service=$1
    local config=$(get_service_config "$service")
    local file=$(echo "$config" | cut -d: -f1)
    local label_key=$(echo "$config" | cut -d: -f2)
    local filepath="$TARGETS_DIR/$file"

    if [[ ! -f "$filepath" ]] || [[ $(cat "$filepath") == "[]" ]]; then
        echo -e "${YELLOW}No targets configured for ${service}${NC}"
        return
    fi

    echo -e "${CYAN}=== ${service^} Targets ===${NC}"
    echo ""

    if command -v jq &> /dev/null; then
        jq -r ".[] | \"  \(.labels.$label_key // .labels.instance // .labels.app // .labels.database): \(.targets[0]) [\(.labels.instance_type // \"default\")]\"" "$filepath" 2>/dev/null || cat "$filepath"
    else
        cat "$filepath"
    fi
    echo ""
}

list_all_targets() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  All Monitoring Targets${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    for service in postgres redis rabbitmq nats mongodb traefik garage app; do
        list_targets "$service"
    done
}

add_target() {
    local service=$1
    shift

    local config=$(get_service_config "$service")
    local file=$(echo "$config" | cut -d: -f1)
    local label_key=$(echo "$config" | cut -d: -f2)
    local default_port=$(echo "$config" | cut -d: -f3)
    local service_label=$(echo "$config" | cut -d: -f4)

    local name=""
    local host="host.docker.internal"
    local port="$default_port"
    local instance_type=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --name) name="$2"; shift 2 ;;
            --host) host="$2"; shift 2 ;;
            --port) port="$2"; shift 2 ;;
            --type) instance_type="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$name" ]]; then
        echo -e "${RED}Error: --name is required${NC}"
        exit 1
    fi

    local filepath="$TARGETS_DIR/$file"
    local target="${host}:${port}"

    # Create file if doesn't exist
    if [[ ! -f "$filepath" ]]; then
        echo "[]" > "$filepath"
    fi

    if ! command -v jq &> /dev/null; then
        echo -e "${RED}Error: jq is required for this operation${NC}"
        echo "Install with: apt install jq (Linux) or brew install jq (macOS)"
        exit 1
    fi

    # Check if target already exists
    if jq -e ".[] | select(.labels.$label_key == \"$name\" or .labels.instance == \"$name\" or .labels.app == \"$name\" or .labels.database == \"$name\")" "$filepath" > /dev/null 2>&1; then
        echo -e "${YELLOW}Target '$name' already exists${NC}"
        exit 1
    fi

    # Build labels JSON
    local labels_json="{\"$label_key\": \"$name\", \"service\": \"$service_label\""
    if [[ -n "$instance_type" ]]; then
        labels_json="$labels_json, \"instance_type\": \"$instance_type\""
    fi
    labels_json="$labels_json}"

    # Add new target
    local new_target="{\"targets\": [\"$target\"], \"labels\": $labels_json}"
    jq ". += [$new_target]" "$filepath" > "$filepath.tmp" && mv "$filepath.tmp" "$filepath"

    echo -e "${GREEN}Added ${service} target:${NC} $name -> $target"
    if [[ -n "$instance_type" ]]; then
        echo -e "  Type: $instance_type"
    fi
}

remove_target() {
    local service=$1
    shift

    local config=$(get_service_config "$service")
    local file=$(echo "$config" | cut -d: -f1)
    local label_key=$(echo "$config" | cut -d: -f2)

    local name=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --name) name="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$name" ]]; then
        echo -e "${RED}Error: --name is required${NC}"
        exit 1
    fi

    local filepath="$TARGETS_DIR/$file"

    if [[ ! -f "$filepath" ]]; then
        echo -e "${RED}No targets file found for ${service}${NC}"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        echo -e "${RED}Error: jq is required for this operation${NC}"
        exit 1
    fi

    # Check if target exists (check multiple label keys for compatibility)
    if ! jq -e ".[] | select(.labels.$label_key == \"$name\" or .labels.instance == \"$name\" or .labels.app == \"$name\" or .labels.database == \"$name\")" "$filepath" > /dev/null 2>&1; then
        echo -e "${YELLOW}Target '$name' not found${NC}"
        exit 1
    fi

    # Remove target (check multiple label keys)
    jq "del(.[] | select(.labels.$label_key == \"$name\" or .labels.instance == \"$name\" or .labels.app == \"$name\" or .labels.database == \"$name\"))" "$filepath" > "$filepath.tmp" && mv "$filepath.tmp" "$filepath"
    echo -e "${GREEN}Removed ${service} target:${NC} $name"
}

# =============================================================================
# Main
# =============================================================================

if [[ $# -lt 1 ]]; then
    usage
fi

COMMAND=$1

case $COMMAND in
    list-all)
        list_all_targets
        ;;
    list)
        if [[ -z "$2" ]]; then
            echo -e "${RED}Error: service type required${NC}"
            echo "Usage: $0 list <service>"
            exit 1
        fi
        list_targets "$2"
        ;;
    add)
        if [[ -z "$2" ]]; then
            echo -e "${RED}Error: service type required${NC}"
            echo "Usage: $0 add <service> --name <name> [--host <host>] [--port <port>]"
            exit 1
        fi
        shift
        add_target "$@"
        ;;
    remove)
        if [[ -z "$2" ]]; then
            echo -e "${RED}Error: service type required${NC}"
            echo "Usage: $0 remove <service> --name <name>"
            exit 1
        fi
        shift
        remove_target "$@"
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        echo -e "${RED}Unknown command: $COMMAND${NC}"
        usage
        ;;
esac

echo ""
echo -e "${BLUE}Changes will be picked up by Prometheus within 30 seconds${NC}"
