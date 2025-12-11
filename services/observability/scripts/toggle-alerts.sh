#!/bin/bash
# =============================================================================
# Toggle Alert Rules
# =============================================================================
# Enable/disable alert categories by renaming files or using .env variables.
#
# Usage:
#   ./toggle-alerts.sh list                    # Show current status
#   ./toggle-alerts.sh enable postgres         # Enable PostgreSQL alerts
#   ./toggle-alerts.sh disable nats            # Disable NATS alerts
#   ./toggle-alerts.sh apply                   # Apply settings from .env
#   ./toggle-alerts.sh enable-all              # Enable all alerts
#   ./toggle-alerts.sh disable-all             # Disable all alerts
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES_DIR="$SCRIPT_DIR/../config/alerting-rules"
ENV_FILE="$SCRIPT_DIR/../.env"

# Require authentication
INFRA_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$INFRA_ROOT/lib/common.sh"
require_auth

# Alert categories mapping
declare -A ALERTS=(
    ["infrastructure"]="01-infrastructure.yml"
    ["containers"]="02-containers.yml"
    ["observability"]="03-observability.yml"
    ["postgresql"]="04-postgresql.yml"
    ["postgres"]="04-postgresql.yml"
    ["timescaledb"]="04-postgresql.yml"
    ["redis"]="05-redis.yml"
    ["nats"]="06-nats.yml"
    ["task-queue"]="07-task-queue.yml"
    ["taskqueue"]="07-task-queue.yml"
    ["asynq"]="07-task-queue.yml"
    ["bullmq"]="07-task-queue.yml"
    ["application"]="08-application.yml"
    ["app"]="08-application.yml"
    ["rabbitmq"]="09-rabbitmq.yml"
    ["rabbit"]="09-rabbitmq.yml"
    ["mongodb"]="10-mongodb.yml"
    ["mongo"]="10-mongodb.yml"
    ["traefik"]="11-traefik.yml"
    ["garage"]="12-garage.yml"
)

# Environment variable mapping
declare -A ENV_VARS=(
    ["01-infrastructure.yml"]="ALERTS_INFRASTRUCTURE"
    ["02-containers.yml"]="ALERTS_CONTAINERS"
    ["03-observability.yml"]="ALERTS_OBSERVABILITY"
    ["04-postgresql.yml"]="ALERTS_POSTGRESQL"
    ["05-redis.yml"]="ALERTS_REDIS"
    ["06-nats.yml"]="ALERTS_NATS"
    ["07-task-queue.yml"]="ALERTS_TASK_QUEUE"
    ["08-application.yml"]="ALERTS_APPLICATION"
    ["09-rabbitmq.yml"]="ALERTS_RABBITMQ"
    ["10-mongodb.yml"]="ALERTS_MONGODB"
    ["11-traefik.yml"]="ALERTS_TRAEFIK"
    ["12-garage.yml"]="ALERTS_GARAGE"
)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    local file=$1
    local name="${file%.yml}"
    name="${name#[0-9][0-9]-}"

    if [[ -f "$RULES_DIR/$file" ]]; then
        echo -e "  ${GREEN}[enabled]${NC}  $name"
    elif [[ -f "$RULES_DIR/$file.disabled" ]]; then
        echo -e "  ${RED}[disabled]${NC} $name"
    else
        echo -e "  ${YELLOW}[missing]${NC}  $name"
    fi
}

list_alerts() {
    echo "Alert Categories:"
    echo ""
    for file in $(ls "$RULES_DIR"/*.yml "$RULES_DIR"/*.yml.disabled 2>/dev/null | xargs -n1 basename | sed 's/.disabled$//' | sort -u); do
        print_status "$file"
    done
    echo ""
    echo "Usage: $0 enable|disable <category>"
    echo "Categories: infrastructure, containers, observability, postgresql, redis, nats, task-queue, application, rabbitmq, mongodb, traefik, garage"
}

enable_alert() {
    local category=$1
    local file="${ALERTS[$category]}"

    if [[ -z "$file" ]]; then
        echo "Unknown category: $category"
        echo "Available: ${!ALERTS[@]}"
        exit 1
    fi

    if [[ -f "$RULES_DIR/$file.disabled" ]]; then
        mv "$RULES_DIR/$file.disabled" "$RULES_DIR/$file"
        echo -e "${GREEN}Enabled${NC} $category alerts"
    elif [[ -f "$RULES_DIR/$file" ]]; then
        echo "$category alerts already enabled"
    else
        echo -e "${RED}Alert file not found${NC}: $file"
        exit 1
    fi
}

disable_alert() {
    local category=$1
    local file="${ALERTS[$category]}"

    if [[ -z "$file" ]]; then
        echo "Unknown category: $category"
        echo "Available: ${!ALERTS[@]}"
        exit 1
    fi

    if [[ -f "$RULES_DIR/$file" ]]; then
        mv "$RULES_DIR/$file" "$RULES_DIR/$file.disabled"
        echo -e "${RED}Disabled${NC} $category alerts"
    elif [[ -f "$RULES_DIR/$file.disabled" ]]; then
        echo "$category alerts already disabled"
    else
        echo -e "${RED}Alert file not found${NC}: $file"
        exit 1
    fi
}

enable_all() {
    echo "Enabling all alerts..."
    for file in "$RULES_DIR"/*.yml.disabled; do
        if [[ -f "$file" ]]; then
            mv "$file" "${file%.disabled}"
            echo -e "${GREEN}Enabled${NC} $(basename "${file%.disabled}")"
        fi
    done
}

disable_all() {
    echo "Disabling all alerts..."
    for file in "$RULES_DIR"/*.yml; do
        if [[ -f "$file" ]]; then
            mv "$file" "$file.disabled"
            echo -e "${RED}Disabled${NC} $(basename "$file")"
        fi
    done
}

apply_from_env() {
    if [[ ! -f "$ENV_FILE" ]]; then
        echo "No .env file found. Using defaults (all enabled)."
        return
    fi

    echo "Applying alert settings from .env..."
    echo ""

    # Source the env file
    set -a
    source "$ENV_FILE"
    set +a

    for file in "${!ENV_VARS[@]}"; do
        local var="${ENV_VARS[$file]}"
        local value="${!var:-true}"
        local name="${file%.yml}"
        name="${name#[0-9][0-9]-}"

        if [[ "$value" == "true" || "$value" == "1" || "$value" == "yes" ]]; then
            if [[ -f "$RULES_DIR/$file.disabled" ]]; then
                mv "$RULES_DIR/$file.disabled" "$RULES_DIR/$file"
                echo -e "${GREEN}Enabled${NC}  $name (${var}=true)"
            else
                echo -e "${GREEN}Enabled${NC}  $name (already)"
            fi
        else
            if [[ -f "$RULES_DIR/$file" ]]; then
                mv "$RULES_DIR/$file" "$RULES_DIR/$file.disabled"
                echo -e "${RED}Disabled${NC} $name (${var}=false)"
            else
                echo -e "${RED}Disabled${NC} $name (already)"
            fi
        fi
    done
}

reload_prometheus() {
    echo ""
    echo "Reloading Prometheus configuration..."
    if curl -s -X POST http://localhost:9090/-/reload > /dev/null 2>&1; then
        echo -e "${GREEN}Prometheus reloaded successfully${NC}"
    else
        echo -e "${YELLOW}Could not reload Prometheus. Restart manually or ensure it's running.${NC}"
        echo "  docker compose restart prometheus"
    fi
}

# Main
case "${1:-list}" in
    list|status)
        list_alerts
        ;;
    enable)
        if [[ -z "$2" ]]; then
            echo "Usage: $0 enable <category>"
            exit 1
        fi
        enable_alert "$2"
        reload_prometheus
        ;;
    disable)
        if [[ -z "$2" ]]; then
            echo "Usage: $0 disable <category>"
            exit 1
        fi
        disable_alert "$2"
        reload_prometheus
        ;;
    enable-all)
        enable_all
        reload_prometheus
        ;;
    disable-all)
        disable_all
        reload_prometheus
        ;;
    apply)
        apply_from_env
        reload_prometheus
        ;;
    *)
        echo "Usage: $0 {list|enable|disable|enable-all|disable-all|apply} [category]"
        echo ""
        echo "Commands:"
        echo "  list         Show current alert status"
        echo "  enable       Enable a category (e.g., postgres, redis)"
        echo "  disable      Disable a category"
        echo "  enable-all   Enable all alert categories"
        echo "  disable-all  Disable all alert categories"
        echo "  apply        Apply settings from .env file"
        exit 1
        ;;
esac
