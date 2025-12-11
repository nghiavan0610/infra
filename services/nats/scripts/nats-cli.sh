#!/bin/bash

# NATS Management Utility Script

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Require authentication
INFRA_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$INFRA_ROOT/lib/common.sh"
require_auth

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

show_help() {
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${PURPLE}NATS Management Utility${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${CYAN}Usage: $0 [COMMAND]${NC}"
    echo ""
    echo -e "${CYAN}Commands:${NC}"
    echo -e "  ${GREEN}start${NC}         Start NATS server"
    echo -e "  ${GREEN}stop${NC}          Stop NATS server"
    echo -e "  ${GREEN}restart${NC}       Restart NATS server"
    echo -e "  ${GREEN}status${NC}        Show NATS status and health"
    echo -e "  ${GREEN}logs${NC}          Show NATS logs (follow mode)"
    echo -e "  ${GREEN}logs-tail${NC}     Show last 50 log lines"
    echo -e "  ${GREEN}monitor${NC}       Start with monitoring (Surveyor)"
    echo -e "  ${GREEN}health${NC}        Comprehensive health check"
    echo -e "  ${GREEN}backup${NC}        Backup JetStream data"
    echo -e "  ${GREEN}test-auth${NC}     Test authentication setup"
    echo -e "  ${GREEN}reset-auth${NC}    Regenerate auth from template"
    echo -e "  ${GREEN}clean${NC}         Clean all data (destructive)"
    echo -e "  ${GREEN}help${NC}          Show this help message"
    echo ""
    echo -e "${CYAN}Examples:${NC}"
    echo -e "  $0 start          # Start NATS"
    echo -e "  $0 monitor        # Start with Surveyor metrics"
    echo -e "  $0 logs           # Follow logs"
    echo -e "  $0 health         # Check health"
}

start_nats() {
    echo -e "${BLUE}Starting NATS...${NC}"
    cd "$BASE_DIR"
    docker compose up -d
    echo -e "${GREEN}NATS started${NC}"
}

stop_nats() {
    echo -e "${YELLOW}Stopping NATS server...${NC}"
    cd "$BASE_DIR"
    docker compose down
    echo -e "${GREEN}NATS server stopped${NC}"
}

restart_nats() {
    echo -e "${YELLOW}Restarting NATS server...${NC}"
    cd "$BASE_DIR"
    docker compose restart nats
    echo -e "${GREEN}NATS server restarted${NC}"
}

show_status() {
    echo -e "${BLUE}NATS Server Status:${NC}"
    echo ""
    cd "$BASE_DIR"
    docker compose ps
    echo ""

    if docker ps | grep -q "nats"; then
        echo -e "${GREEN}NATS container is running${NC}"

        # Show container health
        health=$(docker inspect nats --format='{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
        if [ "$health" = "healthy" ]; then
            echo -e "${GREEN}Container health: $health${NC}"
        else
            echo -e "${YELLOW}Container health: $health${NC}"
        fi

        # Show resource usage
        echo ""
        echo -e "${CYAN}Resource Usage:${NC}"
        docker stats nats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"
    else
        echo -e "${RED}NATS container is not running${NC}"
    fi
}

show_logs() {
    echo -e "${BLUE}NATS logs (Ctrl+C to exit)...${NC}"
    cd "$BASE_DIR"
    docker compose logs -f nats
}

show_logs_tail() {
    echo -e "${BLUE}Last 50 NATS log entries:${NC}"
    cd "$BASE_DIR"
    docker compose logs --tail=50 nats
}

start_monitoring() {
    echo -e "${BLUE}Starting NATS with monitoring...${NC}"
    cd "$BASE_DIR"
    docker compose --profile monitoring up -d
    echo -e "${GREEN}NATS and Surveyor started${NC}"
    echo ""
    echo -e "${CYAN}Monitoring Endpoints:${NC}"
    echo -e "  NATS Monitoring:    http://localhost:8222"
    echo -e "  Connections:        http://localhost:8222/connz"
    echo -e "  JetStream:          http://localhost:8222/jsz"
    echo -e "  Prometheus Metrics: http://localhost:7777/metrics"
}

health_check() {
    echo -e "${BLUE}Health check...${NC}"
    echo ""

    # Check Docker
    if docker info > /dev/null 2>&1; then
        echo -e "${GREEN}Docker is running${NC}"
    else
        echo -e "${RED}Docker is not running${NC}"
        return 1
    fi

    # Check container
    if docker ps | grep -q "nats"; then
        echo -e "${GREEN}NATS container is running${NC}"
    else
        echo -e "${RED}NATS container is not running${NC}"
        return 1
    fi

    # Check HTTP monitoring
    if curl -s http://localhost:8222/healthz > /dev/null 2>&1; then
        echo -e "${GREEN}HTTP monitoring endpoint is healthy${NC}"
    else
        echo -e "${RED}HTTP monitoring endpoint is not responding${NC}"
    fi

    # Show server info
    echo ""
    echo -e "${CYAN}Server Info:${NC}"
    curl -s http://localhost:8222/varz 2>/dev/null | head -20 || echo "Unable to fetch server info"
}

backup_data() {
    echo -e "${BLUE}Backing up JetStream data...${NC}"
    timestamp=$(date +%Y%m%d_%H%M%S)
    backup_dir="$BASE_DIR/backups/jetstream_backup_$timestamp"
    mkdir -p "$backup_dir"

    # Get the volume data
    docker cp nats:/data "$backup_dir/" 2>/dev/null || true
    echo -e "${GREEN}Backup completed: $backup_dir${NC}"
    du -sh "$backup_dir" 2>/dev/null || true
}

test_auth() {
    echo -e "${BLUE}Testing authentication setup...${NC}"
    echo ""

    # Check files
    if [ -f "$BASE_DIR/.env" ]; then
        echo -e "${GREEN}.env file found${NC}"
    else
        echo -e "${RED}.env file not found${NC}"
    fi

    if [ -f "$BASE_DIR/config/auth.conf" ]; then
        echo -e "${GREEN}auth.conf found${NC}"
        if grep -q "accounts" "$BASE_DIR/config/auth.conf" 2>/dev/null; then
            echo -e "${GREEN}Accounts configured${NC}"
        fi
    else
        echo -e "${RED}auth.conf not found${NC}"
    fi

    if [ -f "$BASE_DIR/config/auth.conf.template" ]; then
        echo -e "${GREEN}auth.conf.template found${NC}"
    else
        echo -e "${YELLOW}auth.conf.template not found${NC}"
    fi
}

reset_auth() {
    echo -e "${YELLOW}Resetting authentication configuration...${NC}"
    echo "This will regenerate auth.conf from template and restart NATS."
    read -p "Continue? (y/N): " confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        "$SCRIPT_DIR/start-nats.sh"
    else
        echo -e "${GREEN}Operation cancelled${NC}"
    fi
}

clean_data() {
    echo -e "${RED}WARNING: This will remove ALL NATS data!${NC}"
    read -p "Type 'yes' to confirm: " confirm

    if [ "$confirm" = "yes" ]; then
        echo -e "${YELLOW}Stopping NATS and removing data...${NC}"
        cd "$BASE_DIR"
        docker compose down -v
        echo -e "${GREEN}All data removed${NC}"
    else
        echo -e "${GREEN}Operation cancelled${NC}"
    fi
}

# Main command handling
case "${1:-help}" in
    "start")
        start_nats
        ;;
    "stop")
        stop_nats
        ;;
    "restart")
        restart_nats
        ;;
    "status")
        show_status
        ;;
    "logs")
        show_logs
        ;;
    "logs-tail")
        show_logs_tail
        ;;
    "monitor")
        start_monitoring
        ;;
    "health")
        health_check
        ;;
    "backup")
        backup_data
        ;;
    "test-auth")
        test_auth
        ;;
    "reset-auth")
        reset_auth
        ;;
    "clean")
        clean_data
        ;;
    "help"|*)
        show_help
        ;;
esac
