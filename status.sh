#!/bin/bash
# =============================================================================
# Infrastructure Status
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load shared library
source "$SCRIPT_DIR/lib/common.sh"

# Require authentication
require_auth

log_header "Infrastructure Status"

print_status() {
    local category=$1
    shift
    local services=("$@")

    echo -e "${CYAN}$category:${NC}"

    for service in "${services[@]}"; do
        container_name=$(echo "$service" | cut -d: -f1)
        display_name=$(echo "$service" | cut -d: -f2)
        print_service_status "$display_name" "$container_name"
    done
    echo ""
}

# Databases
print_status "Databases" \
    "postgres:PostgreSQL" \
    "redis-cache:Redis Cache" \
    "redis-queue:Redis Queue" \
    "mongo-primary:MongoDB" \
    "timescaledb:TimescaleDB" \
    "mysql:MySQL" \
    "memcached:Memcached" \
    "clickhouse:ClickHouse"

# Queues
print_status "Message Queues" \
    "nats:NATS" \
    "kafka:Kafka" \
    "rabbitmq:RabbitMQ"

# Storage
print_status "Storage" \
    "garage:Garage S3" \
    "minio:MinIO"

# Search & Vector
print_status "Search & Vector" \
    "meilisearch:Meilisearch" \
    "opensearch:OpenSearch" \
    "qdrant:Qdrant"

# Security
print_status "Security" \
    "fail2ban:Fail2ban" \
    "crowdsec:Crowdsec" \
    "authentik-server:Authentik" \
    "vault:Vault"

# Networking
print_status "Networking" \
    "traefik:Traefik" \
    "wireguard:WireGuard VPN"

# Monitoring & Tools
print_status "Monitoring & Tools" \
    "prometheus:Prometheus" \
    "grafana:Grafana" \
    "loki:Loki" \
    "tempo:Tempo" \
    "alertmanager:Alertmanager" \
    "uptime-kuma:Uptime Kuma" \
    "registry:Docker Registry" \
    "portainer:Portainer" \
    "redisinsight:RedisInsight" \
    "plausible:Plausible Analytics" \
    "dozzle:Dozzle" \
    "vaultwarden:Vaultwarden" \
    "ntfy:Ntfy" \
    "healthchecks:Healthchecks" \
    "watchtower:Watchtower" \
    "backup:Backup"

# AI / LLM
print_status "AI / LLM" \
    "langfuse:LangFuse" \
    "faster-whisper:Faster Whisper"

# CI/CD Runners
print_status "CI/CD Runners" \
    "github-runner:GitHub Runner" \
    "gitlab-runner:GitLab Runner" \
    "drone:Drone CI"

# Development & Debugging
print_status "Development & Debugging" \
    "sentry:Sentry" \
    "adminer:Adminer" \
    "mailpit:Mailpit" \
    "gitea:Gitea"

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Commands:"
echo "  ./setup.sh         Start services"
echo "  ./stop.sh          Stop all services"
echo "  docker ps          Show running containers"
echo ""
