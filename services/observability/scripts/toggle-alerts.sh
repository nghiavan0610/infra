#!/bin/bash
# =============================================================================
# Toggle Alert Rules
# =============================================================================
# Enable/disable alert categories by renaming files or syncing with services.conf.
#
# Usage:
#   ./toggle-alerts.sh list                    # Show current status
#   ./toggle-alerts.sh sync                    # Sync with services.conf (recommended)
#   ./toggle-alerts.sh enable postgres         # Enable PostgreSQL alerts
#   ./toggle-alerts.sh disable nats            # Disable NATS alerts
#   ./toggle-alerts.sh apply                   # Apply settings from .env (legacy)
#   ./toggle-alerts.sh enable-all              # Enable all alerts
#   ./toggle-alerts.sh disable-all             # Disable all alerts
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES_DIR="$SCRIPT_DIR/../config/alerting-rules"
ENV_FILE="$SCRIPT_DIR/../.env"
INFRA_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SERVICES_CONF="$INFRA_ROOT/services.conf"

# Require authentication
source "$INFRA_ROOT/lib/common.sh"
require_auth

# =============================================================================
# Alert categories mapping (category name -> alert file)
# =============================================================================
declare -A ALERTS=(
    ["infrastructure"]="01-infrastructure.yml"
    ["containers"]="02-containers.yml"
    ["observability"]="03-observability.yml"
    ["postgresql"]="04-postgresql.yml"
    ["postgres"]="04-postgresql.yml"
    ["postgres-ha"]="04-postgresql.yml"
    ["timescaledb"]="04-postgresql.yml"
    ["redis"]="05-redis.yml"
    ["nats"]="06-nats.yml"
    ["task-queue"]="07-task-queue.yml"
    ["taskqueue"]="07-task-queue.yml"
    ["asynq"]="07-task-queue.yml"
    ["bullmq"]="07-task-queue.yml"
    ["rabbitmq"]="09-rabbitmq.yml"
    ["rabbit"]="09-rabbitmq.yml"
    ["mongodb"]="10-mongodb.yml"
    ["mongo"]="10-mongodb.yml"
    ["traefik"]="11-traefik.yml"
    ["garage"]="12-garage.yml"
    ["security"]="13-security.yml"
    ["authentik"]="13-security.yml"
    ["vault"]="13-security.yml"
    ["mysql"]="14-mysql.yml"
    ["memcached"]="15-memcached.yml"
    ["clickhouse"]="16-clickhouse.yml"
    ["kafka"]="17-kafka.yml"
    ["minio"]="18-minio.yml"
)

# =============================================================================
# services.conf service -> alert file mapping
# Maps service names from services.conf to their corresponding alert files
# =============================================================================
declare -A SERVICE_TO_ALERT=(
    # Core (always enabled)
    # infrastructure, containers, observability are always on

    # Databases
    ["postgres"]="04-postgresql.yml"
    ["postgres-ha"]="04-postgresql.yml"
    ["timescaledb"]="04-postgresql.yml"
    ["redis"]="05-redis.yml"
    ["mongo"]="10-mongodb.yml"
    ["mysql"]="14-mysql.yml"
    ["memcached"]="15-memcached.yml"
    ["clickhouse"]="16-clickhouse.yml"

    # Message Queues
    ["nats"]="06-nats.yml"
    ["rabbitmq"]="09-rabbitmq.yml"
    ["kafka"]="17-kafka.yml"
    ["asynq"]="07-task-queue.yml"

    # Storage
    ["garage"]="12-garage.yml"
    ["minio"]="18-minio.yml"

    # Networking
    ["traefik"]="11-traefik.yml"

    # Security
    ["authentik"]="13-security.yml"
    ["vault"]="13-security.yml"
)

# =============================================================================
# Core alerts that are always enabled (don't depend on services.conf)
# =============================================================================
CORE_ALERTS=(
    "01-infrastructure.yml"
    "02-containers.yml"
    "03-observability.yml"
)

# =============================================================================
# Alerts that require application instrumentation (disabled by default)
# These need code changes in apps to expose metrics
# =============================================================================
APP_INSTRUMENTATION_ALERTS=(
    "07-task-queue.yml"
)
# Note: Application-specific alerts are created per-app via:
#   app-cli.sh connect <app-name> --alerts

# Environment variable mapping (legacy support)
declare -A ENV_VARS=(
    ["01-infrastructure.yml"]="ALERTS_INFRASTRUCTURE"
    ["02-containers.yml"]="ALERTS_CONTAINERS"
    ["03-observability.yml"]="ALERTS_OBSERVABILITY"
    ["04-postgresql.yml"]="ALERTS_POSTGRESQL"
    ["05-redis.yml"]="ALERTS_REDIS"
    ["06-nats.yml"]="ALERTS_NATS"
    ["07-task-queue.yml"]="ALERTS_TASK_QUEUE"
    ["09-rabbitmq.yml"]="ALERTS_RABBITMQ"
    ["10-mongodb.yml"]="ALERTS_MONGODB"
    ["11-traefik.yml"]="ALERTS_TRAEFIK"
    ["12-garage.yml"]="ALERTS_GARAGE"
    ["13-security.yml"]="ALERTS_SECURITY"
    ["14-mysql.yml"]="ALERTS_MYSQL"
    ["15-memcached.yml"]="ALERTS_MEMCACHED"
    ["16-clickhouse.yml"]="ALERTS_CLICKHOUSE"
    ["17-kafka.yml"]="ALERTS_KAFKA"
    ["18-minio.yml"]="ALERTS_MINIO"
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

# =============================================================================
# Sync alerts with services.conf (RECOMMENDED)
# =============================================================================
# This function reads services.conf and enables/disables alerts accordingly.
# - Core alerts (infrastructure, containers, observability) are always enabled
# - Service-specific alerts are enabled only if the service is enabled
# - App instrumentation alerts (task-queue, application) are disabled by default
# =============================================================================
sync_with_services_conf() {
    if [[ ! -f "$SERVICES_CONF" ]]; then
        echo -e "${RED}Error${NC}: services.conf not found at $SERVICES_CONF"
        echo "Run this from the infra directory or ensure services.conf exists."
        exit 1
    fi

    echo "Syncing alert rules with services.conf..."
    echo ""

    # Track which alert files should be enabled
    declare -A ALERTS_TO_ENABLE

    # Step 1: Enable core alerts (always on)
    for file in "${CORE_ALERTS[@]}"; do
        ALERTS_TO_ENABLE["$file"]=1
    done

    # Step 2: Parse services.conf and determine which alerts to enable
    while IFS='=' read -r service value; do
        # Skip comments and empty lines
        [[ "$service" =~ ^#.*$ || -z "$service" ]] && continue

        # Trim whitespace
        service=$(echo "$service" | xargs)
        value=$(echo "$value" | xargs)

        # Check if this service has an associated alert file
        local alert_file="${SERVICE_TO_ALERT[$service]}"
        if [[ -n "$alert_file" ]]; then
            if [[ "$value" == "true" ]]; then
                ALERTS_TO_ENABLE["$alert_file"]=1
            fi
        fi
    done < "$SERVICES_CONF"

    # Step 3: Get all alert files and enable/disable accordingly
    local all_alert_files=()
    for f in "$RULES_DIR"/*.yml "$RULES_DIR"/*.yml.disabled 2>/dev/null; do
        [[ -f "$f" ]] || continue
        local basename=$(basename "$f" .disabled)
        basename=$(basename "$basename")
        # Avoid duplicates
        if [[ ! " ${all_alert_files[*]} " =~ " ${basename} " ]]; then
            all_alert_files+=("$basename")
        fi
    done

    # Step 4: Apply changes
    local enabled_count=0
    local disabled_count=0

    for file in "${all_alert_files[@]}"; do
        local name="${file%.yml}"
        name="${name#[0-9][0-9]-}"

        # Check if this alert requires app instrumentation
        local requires_instrumentation=false
        for instr_alert in "${APP_INSTRUMENTATION_ALERTS[@]}"; do
            if [[ "$file" == "$instr_alert" ]]; then
                requires_instrumentation=true
                break
            fi
        done

        if [[ "${ALERTS_TO_ENABLE[$file]}" == "1" ]]; then
            # Should be enabled
            if [[ -f "$RULES_DIR/$file.disabled" ]]; then
                mv "$RULES_DIR/$file.disabled" "$RULES_DIR/$file"
                echo -e "  ${GREEN}[enabled]${NC}  $name"
                ((enabled_count++))
            elif [[ -f "$RULES_DIR/$file" ]]; then
                echo -e "  ${GREEN}[enabled]${NC}  $name (no change)"
            fi
        elif [[ "$requires_instrumentation" == "true" ]]; then
            # App instrumentation alerts - disable by default with note
            if [[ -f "$RULES_DIR/$file" ]]; then
                mv "$RULES_DIR/$file" "$RULES_DIR/$file.disabled"
                echo -e "  ${YELLOW}[disabled]${NC} $name (requires app instrumentation)"
                ((disabled_count++))
            elif [[ -f "$RULES_DIR/$file.disabled" ]]; then
                echo -e "  ${YELLOW}[disabled]${NC} $name (requires app instrumentation)"
            fi
        else
            # Service not enabled - disable alert
            if [[ -f "$RULES_DIR/$file" ]]; then
                mv "$RULES_DIR/$file" "$RULES_DIR/$file.disabled"
                echo -e "  ${RED}[disabled]${NC} $name (service not enabled)"
                ((disabled_count++))
            elif [[ -f "$RULES_DIR/$file.disabled" ]]; then
                echo -e "  ${RED}[disabled]${NC} $name (service not enabled)"
            fi
        fi
    done

    echo ""
    echo -e "Summary: ${GREEN}$enabled_count enabled${NC}, ${RED}$disabled_count disabled${NC}"

    # Show hint for app instrumentation alerts
    echo ""
    echo -e "${YELLOW}Note:${NC} To enable app instrumentation alerts (task-queue, application):"
    echo "  ./toggle-alerts.sh enable task-queue"
    echo "  ./toggle-alerts.sh enable application"
}

# =============================================================================
# Quick sync (silent mode for setup.sh)
# =============================================================================
sync_quiet() {
    if [[ ! -f "$SERVICES_CONF" ]]; then
        return 1
    fi

    # Track which alert files should be enabled
    declare -A ALERTS_TO_ENABLE

    # Enable core alerts
    for file in "${CORE_ALERTS[@]}"; do
        ALERTS_TO_ENABLE["$file"]=1
    done

    # Parse services.conf
    while IFS='=' read -r service value; do
        [[ "$service" =~ ^#.*$ || -z "$service" ]] && continue
        service=$(echo "$service" | xargs)
        value=$(echo "$value" | xargs)

        local alert_file="${SERVICE_TO_ALERT[$service]}"
        if [[ -n "$alert_file" && "$value" == "true" ]]; then
            ALERTS_TO_ENABLE["$alert_file"]=1
        fi
    done < "$SERVICES_CONF"

    # Get all alert files
    local all_alert_files=()
    for f in "$RULES_DIR"/*.yml "$RULES_DIR"/*.yml.disabled 2>/dev/null; do
        [[ -f "$f" ]] || continue
        local basename=$(basename "$f" .disabled)
        basename=$(basename "$basename")
        if [[ ! " ${all_alert_files[*]} " =~ " ${basename} " ]]; then
            all_alert_files+=("$basename")
        fi
    done

    # Apply changes silently
    for file in "${all_alert_files[@]}"; do
        local requires_instrumentation=false
        for instr_alert in "${APP_INSTRUMENTATION_ALERTS[@]}"; do
            [[ "$file" == "$instr_alert" ]] && requires_instrumentation=true && break
        done

        if [[ "${ALERTS_TO_ENABLE[$file]}" == "1" ]]; then
            [[ -f "$RULES_DIR/$file.disabled" ]] && mv "$RULES_DIR/$file.disabled" "$RULES_DIR/$file"
        elif [[ "$requires_instrumentation" == "true" ]]; then
            [[ -f "$RULES_DIR/$file" ]] && mv "$RULES_DIR/$file" "$RULES_DIR/$file.disabled"
        else
            [[ -f "$RULES_DIR/$file" ]] && mv "$RULES_DIR/$file" "$RULES_DIR/$file.disabled"
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
    sync)
        sync_with_services_conf
        reload_prometheus
        ;;
    sync-quiet)
        # Silent mode for setup.sh integration
        sync_quiet
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
        echo "Usage: $0 {list|sync|enable|disable|enable-all|disable-all|apply} [category]"
        echo ""
        echo "Commands:"
        echo "  list         Show current alert status"
        echo "  sync         Sync alerts with services.conf (recommended)"
        echo "  enable       Enable a category (e.g., postgres, redis)"
        echo "  disable      Disable a category"
        echo "  enable-all   Enable all alert categories"
        echo "  disable-all  Disable all alert categories"
        echo "  apply        Apply settings from .env file (legacy)"
        echo ""
        echo "Examples:"
        echo "  $0 sync                  # Auto-enable based on services.conf"
        echo "  $0 enable application    # Enable app metrics alerts"
        echo "  $0 disable nats          # Disable NATS alerts"
        exit 1
        ;;
esac
