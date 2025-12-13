#!/bin/bash
# =============================================================================
# Infrastructure Status - Comprehensive Service Information
# =============================================================================
# Usage:
#   ./status.sh              # Full status report
#   ./status.sh --quick      # Quick status (running/stopped only)
#   ./status.sh --json       # Output as JSON (for scripting)
#   ./status.sh redis        # Status of specific service
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load shared library
source "$SCRIPT_DIR/lib/common.sh"

# Require authentication
require_auth

# Parse arguments
QUICK_MODE=false
JSON_MODE=false
FILTER_SERVICE=""

for arg in "$@"; do
    case $arg in
        --quick|-q)
            QUICK_MODE=true
            ;;
        --json|-j)
            JSON_MODE=true
            ;;
        --help|-h)
            echo "Usage: $0 [options] [service]"
            echo ""
            echo "Options:"
            echo "  -q, --quick   Quick status (running/stopped only)"
            echo "  -j, --json    Output as JSON"
            echo "  -h, --help    Show this help"
            echo ""
            echo "Examples:"
            echo "  $0              # Full status report"
            echo "  $0 --quick      # Quick overview"
            echo "  $0 redis        # Redis service details"
            echo "  $0 postgres     # PostgreSQL service details"
            exit 0
            ;;
        -*)
            log_error "Unknown option: $arg"
            exit 1
            ;;
        *)
            FILTER_SERVICE="$arg"
            ;;
    esac
done

# =============================================================================
# Helper Functions
# =============================================================================

# Get container resource usage
get_container_stats() {
    local container=$1
    if is_container_running "$container"; then
        docker stats --no-stream --format "{{.CPUPerc}}|{{.MemUsage}}|{{.NetIO}}" "$container" 2>/dev/null || echo "N/A|N/A|N/A"
    else
        echo "N/A|N/A|N/A"
    fi
}

# Get container uptime
get_container_uptime() {
    local container=$1
    if is_container_running "$container"; then
        docker inspect --format='{{.State.StartedAt}}' "$container" 2>/dev/null | \
            xargs -I {} date -d {} +%s 2>/dev/null | \
            xargs -I {} bash -c 'echo $(( ($(date +%s) - {}) / 86400 ))d $(( (($(date +%s) - {}) % 86400) / 3600 ))h' 2>/dev/null || \
            docker ps --filter "name=^${container}$" --format "{{.Status}}" | sed 's/Up //'
    else
        echo "-"
    fi
}

# Get port mappings for container
get_container_ports() {
    local container=$1
    if is_container_running "$container"; then
        docker port "$container" 2>/dev/null | tr '\n' ', ' | sed 's/, $//'
    else
        echo "-"
    fi
}

# Test TCP connection
test_connection() {
    local host=$1
    local port=$2
    timeout 2 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null && echo "OK" || echo "FAIL"
}

# Get service URL
get_service_url() {
    local service=$1
    local port=$2
    local path=${3:-""}
    echo "http://localhost:${port}${path}"
}

# Print detailed service status
print_detailed_status() {
    local name=$1
    local container=$2
    local port=${3:-""}
    local url_path=${4:-""}
    local extra_info=${5:-""}

    if ! is_container_running "$container"; then
        echo -e "  ${RED}○${NC} $name"
        echo -e "    Status: ${RED}stopped${NC}"
        return
    fi

    local health=$(get_container_health "$container")
    local health_color=$GREEN
    [[ "$health" == "unhealthy" ]] && health_color=$RED
    [[ "$health" == "starting" ]] && health_color=$YELLOW

    echo -e "  ${GREEN}●${NC} $name"
    echo -e "    Status: ${health_color}${health}${NC}"

    if [[ "$QUICK_MODE" != "true" ]]; then
        # Uptime
        local uptime=$(get_container_uptime "$container")
        echo -e "    Uptime: $uptime"

        # Port & URL
        if [[ -n "$port" ]]; then
            local conn=$(test_connection "localhost" "$port")
            local conn_color=$GREEN
            [[ "$conn" == "FAIL" ]] && conn_color=$RED
            echo -e "    Port:   $port (${conn_color}${conn}${NC})"
            if [[ -n "$url_path" ]]; then
                echo -e "    URL:    $(get_service_url "$container" "$port" "$url_path")"
            fi
        fi

        # Resource usage
        local stats=$(get_container_stats "$container")
        local cpu=$(echo "$stats" | cut -d'|' -f1)
        local mem=$(echo "$stats" | cut -d'|' -f2)
        if [[ "$cpu" != "N/A" ]]; then
            echo -e "    CPU:    $cpu  Mem: $mem"
        fi

        # Extra info
        if [[ -n "$extra_info" ]]; then
            echo -e "    $extra_info"
        fi
    fi
}

# Print section header
print_section() {
    local title=$1
    echo ""
    echo -e "${CYAN}━━━ $title ━━━${NC}"
}

# =============================================================================
# Service-Specific Status Functions
# =============================================================================

status_postgres() {
    local container="postgres"
    if ! is_container_running "$container"; then
        print_detailed_status "PostgreSQL" "$container" "5432"
        return
    fi

    # Get connection info
    local pg_version=$(docker exec "$container" psql -U postgres -c "SELECT version();" 2>/dev/null | grep PostgreSQL | head -1 | awk '{print $1, $2}' || echo "Unknown")
    local pg_connections=$(docker exec "$container" psql -U postgres -c "SELECT count(*) FROM pg_stat_activity;" -t 2>/dev/null | tr -d ' ' || echo "?")
    local pg_databases=$(docker exec "$container" psql -U postgres -c "SELECT count(*) FROM pg_database WHERE datistemplate = false;" -t 2>/dev/null | tr -d ' ' || echo "?")

    print_detailed_status "PostgreSQL" "$container" "5432" "" "Version: $pg_version"
    echo -e "    Connections: $pg_connections active | Databases: $pg_databases"
}

status_redis() {
    for redis_type in "cache" "queue"; do
        local container="redis-${redis_type}"
        local port=$([[ "$redis_type" == "cache" ]] && echo "6379" || echo "6380")

        if ! is_container_running "$container"; then
            print_detailed_status "Redis ${redis_type^}" "$container" "$port"
            continue
        fi

        # Get Redis info
        local redis_pass=$(grep "REDIS_${redis_type^^}_PASSWORD" "$SCRIPT_DIR/services/redis/.env" 2>/dev/null | cut -d'=' -f2)
        local redis_info=$(docker exec "$container" redis-cli -a "$redis_pass" INFO 2>/dev/null | grep -E "used_memory_human|connected_clients|db0" || echo "")
        local mem=$(echo "$redis_info" | grep used_memory_human | cut -d: -f2 | tr -d '\r')
        local clients=$(echo "$redis_info" | grep connected_clients | cut -d: -f2 | tr -d '\r')
        local keys=$(echo "$redis_info" | grep "db0:" | sed 's/.*keys=\([0-9]*\).*/\1/' || echo "0")

        print_detailed_status "Redis ${redis_type^}" "$container" "$port"
        [[ -n "$mem" ]] && echo -e "    Memory: $mem | Clients: $clients | Keys: ${keys:-0}"
    done
}

status_observability() {
    local services=(
        "prometheus:Prometheus:9090:/-/healthy"
        "grafana:Grafana:3000:"
        "loki:Loki:3100:/ready"
        "tempo:Tempo:3200:/ready"
        "alertmanager:Alertmanager:9093:/-/healthy"
        "alloy:Alloy:12345:"
    )

    for svc in "${services[@]}"; do
        local container=$(echo "$svc" | cut -d: -f1)
        local name=$(echo "$svc" | cut -d: -f2)
        local port=$(echo "$svc" | cut -d: -f3)
        local path=$(echo "$svc" | cut -d: -f4)
        print_detailed_status "$name" "$container" "$port" "$path"
    done

    # Show Grafana credentials if running
    if is_container_running "grafana" && [[ "$QUICK_MODE" != "true" ]]; then
        local grafana_user=$(grep "GRAFANA_ADMIN_USER" "$SCRIPT_DIR/services/observability/.env" 2>/dev/null | cut -d'=' -f2 || echo "admin")
        echo -e "    ${YELLOW}Login:${NC} $grafana_user / <check .env>"
    fi
}

status_traefik() {
    local container="traefik"
    if ! is_container_running "$container"; then
        print_detailed_status "Traefik" "$container" "80"
        return
    fi

    print_detailed_status "Traefik" "$container" "80" "" ""
    echo -e "    Ports: 80 (HTTP), 443 (HTTPS), 8080 (Dashboard)"

    # Count routers
    local routers=$(curl -s http://localhost:8080/api/http/routers 2>/dev/null | grep -o '"name"' | wc -l || echo "?")
    echo -e "    Active routers: $routers"
}

status_security() {
    # Fail2ban
    if is_container_running "fail2ban"; then
        local banned=$(docker exec fail2ban fail2ban-client status 2>/dev/null | grep "Currently banned" | awk '{sum += $NF} END {print sum}' || echo "?")
        print_detailed_status "Fail2ban" "fail2ban" ""
        echo -e "    Currently banned: $banned IPs"
    else
        print_detailed_status "Fail2ban" "fail2ban" ""
    fi

    # CrowdSec
    if is_container_running "crowdsec"; then
        local decisions=$(docker exec crowdsec cscli decisions list -o raw 2>/dev/null | wc -l || echo "?")
        print_detailed_status "CrowdSec" "crowdsec" "8080"
        echo -e "    Active decisions: $decisions"
    else
        print_detailed_status "CrowdSec" "crowdsec" "8080"
    fi

    print_detailed_status "Authentik" "authentik-server" "9000" "/"
    print_detailed_status "Vault" "vault" "8200" "/v1/sys/health"
}

# =============================================================================
# Main Status Report
# =============================================================================

if [[ -n "$FILTER_SERVICE" ]]; then
    # Show specific service
    log_header "Service Status: $FILTER_SERVICE"
    case "$FILTER_SERVICE" in
        postgres|postgresql)
            status_postgres
            ;;
        redis)
            status_redis
            ;;
        observability|grafana|prometheus|loki)
            status_observability
            ;;
        traefik)
            status_traefik
            ;;
        security|fail2ban|crowdsec)
            status_security
            ;;
        *)
            # Generic status for any container
            print_detailed_status "$FILTER_SERVICE" "$FILTER_SERVICE" ""
            ;;
    esac
else
    # Full status report
    log_header "Infrastructure Status"

    # System overview
    if [[ "$QUICK_MODE" != "true" ]]; then
        echo -e "${CYAN}System Overview${NC}"
        echo -e "  Containers: $(docker ps -q | wc -l | tr -d ' ') running / $(docker ps -aq | wc -l | tr -d ' ') total"
        echo -e "  Networks:   $(docker network ls -q | wc -l | tr -d ' ')"
        echo -e "  Volumes:    $(docker volume ls -q | wc -l | tr -d ' ')"

        # Disk usage
        disk_info=$(df -h / | tail -1 | awk '{print $3 "|" $4 "|" $5}')
        echo -e "  Disk:       $(echo "$disk_info" | cut -d'|' -f1) used / $(echo "$disk_info" | cut -d'|' -f2) available ($(echo "$disk_info" | cut -d'|' -f3))"
    fi

    # Databases
    print_section "Databases"
    status_postgres
    status_redis
    print_detailed_status "MongoDB" "mongo-primary" "27017"
    print_detailed_status "ClickHouse" "clickhouse" "8123" "/"
    print_detailed_status "MySQL" "mysql" "3306"
    print_detailed_status "TimescaleDB" "timescaledb" "5433"

    # Message Queues
    print_section "Message Queues"
    print_detailed_status "NATS" "nats" "4222"
    print_detailed_status "Kafka" "kafka" "9092"
    print_detailed_status "RabbitMQ" "rabbitmq" "5672" "" ""
    if is_container_running "rabbitmq"; then
        echo -e "    Management: http://localhost:15672"
    fi

    # Storage
    print_section "Storage"
    print_detailed_status "Garage S3" "garage" "3900"
    print_detailed_status "MinIO" "minio" "9000" "" ""
    if is_container_running "minio"; then
        echo -e "    Console: http://localhost:9001"
    fi

    # Search & Vector
    print_section "Search & Vector"
    print_detailed_status "Meilisearch" "meilisearch" "7700" "/health"
    print_detailed_status "OpenSearch" "opensearch" "9200" "/_cluster/health"
    print_detailed_status "Qdrant" "qdrant" "6333" "/health"

    # Networking
    print_section "Networking"
    status_traefik
    print_detailed_status "WireGuard" "wireguard" "51820"

    # Security
    print_section "Security"
    status_security

    # Observability
    print_section "Observability"
    status_observability

    # Monitoring & Tools
    print_section "Tools & Utilities"
    print_detailed_status "Uptime Kuma" "uptime-kuma" "3001" "/"
    print_detailed_status "Ntfy" "ntfy" "8080" "/"
    print_detailed_status "Portainer" "portainer" "9443" "/"
    print_detailed_status "Dozzle" "dozzle" "9999" "/"
    print_detailed_status "Vaultwarden" "vaultwarden" "8080" "/"
    print_detailed_status "Watchtower" "watchtower" ""

    # AI / LLM
    print_section "AI / LLM"
    print_detailed_status "LangFuse" "langfuse" "3000" "/"
    print_detailed_status "Faster Whisper" "faster-whisper" "8000" "/health"

    # CI/CD
    print_section "CI/CD"
    print_detailed_status "GitHub Runner" "github-runner" ""
    print_detailed_status "GitLab Runner" "gitlab-runner" ""
    print_detailed_status "Gitea" "gitea" "3002" "/"
    print_detailed_status "Drone CI" "drone" "8082" "/"

    # Development
    print_section "Development"
    print_detailed_status "Adminer" "adminer" "8080" "/"
    print_detailed_status "Mailpit" "mailpit" "8025" "/"
    print_detailed_status "RedisInsight" "redisinsight" "5540" "/"

    # Error Tracking
    print_section "Error Tracking"
    print_detailed_status "GlitchTip" "glitchtip" "8000" "/"
fi

# Footer
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Commands:"
echo "  ./setup.sh            Start/configure services"
echo "  ./stop.sh             Stop services"
echo "  ./stop.sh --prune     Stop + cleanup unused resources"
echo "  ./status.sh --quick   Quick status overview"
echo "  docker logs <name>    View container logs"
echo ""
