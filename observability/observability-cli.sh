#!/bin/bash

# Observability Stack Management Script

set -e

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
    echo -e "${PURPLE}📊 Observability Stack Management${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${CYAN}Usage: $0 [COMMAND]${NC}"
    echo ""
    echo -e "${CYAN}Commands:${NC}"
    echo -e "  ${GREEN}start${NC}         Start all observability services"
    echo -e "  ${GREEN}stop${NC}          Stop all services"
    echo -e "  ${GREEN}restart${NC}       Restart all services"
    echo -e "  ${GREEN}status${NC}        Show service status"
    echo -e "  ${GREEN}health${NC}        Check health of all services"
    echo -e "  ${GREEN}logs${NC}          Show logs (all services)"
    echo -e "  ${GREEN}logs-grafana${NC}  Show Grafana logs"
    echo -e "  ${GREEN}logs-prometheus${NC} Show Prometheus logs"
    echo -e "  ${GREEN}logs-loki${NC}     Show Loki logs"
    echo -e "  ${GREEN}logs-tempo${NC}    Show Tempo logs"
    echo -e "  ${GREEN}logs-jaeger${NC}   Show Jaeger logs"
    echo -e "  ${GREEN}logs-otel${NC}     Show OTEL Collector logs"
    echo -e "  ${GREEN}urls${NC}          Show all service URLs"
    echo -e "  ${GREEN}backup${NC}        Backup all data volumes"
    echo -e "  ${GREEN}clean${NC}         Clean all data (destructive)"
    echo -e "  ${GREEN}help${NC}          Show this help"
}

start_stack() {
    echo -e "${BLUE}▶ Starting observability stack...${NC}"
    docker-compose up -d
    echo -e "${GREEN}✅ Stack started${NC}"
    echo ""
    show_urls
}

stop_stack() {
    echo -e "${YELLOW}▶ Stopping observability stack...${NC}"
    docker-compose down
    echo -e "${GREEN}✅ Stack stopped${NC}"
}

restart_stack() {
    echo -e "${YELLOW}▶ Restarting observability stack...${NC}"
    docker-compose restart
    echo -e "${GREEN}✅ Stack restarted${NC}"
}

show_status() {
    echo -e "${BLUE}▶ Service Status:${NC}"
    echo ""
    docker-compose ps
}

check_health() {
    echo -e "${BLUE}▶ Health Check:${NC}"
    echo ""
    
    # Load environment variables
    source .env 2>/dev/null || true
    
    # Check Grafana
    if curl -s "http://localhost:${GRAFANA_PORT:-3000}/api/health" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Grafana is healthy${NC}"
    else
        echo -e "${RED}❌ Grafana is not responding${NC}"
    fi
    
    # Check Prometheus
    if curl -s "http://localhost:${PROMETHEUS_PORT:-9090}/-/healthy" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Prometheus is healthy${NC}"
    else
        echo -e "${RED}❌ Prometheus is not responding${NC}"
    fi
    
    # Check Loki
    if curl -s "http://localhost:${LOKI_PORT:-3100}/ready" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Loki is healthy${NC}"
    else
        echo -e "${RED}❌ Loki is not responding${NC}"
    fi
    
    # Check Tempo
    if curl -s "http://localhost:${TEMPO_PORT:-3200}/ready" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Tempo is healthy${NC}"
    else
        echo -e "${RED}❌ Tempo is not responding${NC}"
    fi
    
    # Check Jaeger
    if curl -s "http://localhost:${JAEGER_UI_PORT:-16686}/" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Jaeger is healthy${NC}"
    else
        echo -e "${RED}❌ Jaeger is not responding${NC}"
    fi
    
    # Check OTEL Collector
    if curl -s "http://localhost:${OTEL_HEALTH_PORT:-13133}/" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ OTEL Collector is healthy${NC}"
    else
        echo -e "${RED}❌ OTEL Collector is not responding${NC}"
    fi
}

show_logs() {
    echo -e "${BLUE}▶ Showing all logs (Ctrl+C to exit)...${NC}"
    docker-compose logs -f
}

show_logs_service() {
    local service=$1
    echo -e "${BLUE}▶ Showing $service logs (Ctrl+C to exit)...${NC}"
    docker-compose logs -f "$service"
}

show_urls() {
    # Load environment variables
    source .env 2>/dev/null || true
    
    echo -e "${CYAN}📊 Service URLs:${NC}"
    echo ""
    echo -e "${GREEN}Grafana:${NC}          http://localhost:${GRAFANA_PORT:-3000}"
    echo -e "  Username: ${GRAFANA_ADMIN_USER:-admin}"
    echo -e "  Password: ${GRAFANA_ADMIN_PASSWORD:-admin}"
    echo ""
    echo -e "${GREEN}Prometheus:${NC}       http://localhost:${PROMETHEUS_PORT:-9090}"
    echo -e "${GREEN}Jaeger:${NC}           http://localhost:${JAEGER_UI_PORT:-16686}"
    echo -e "${GREEN}Loki:${NC}             http://localhost:${LOKI_PORT:-3100}"
    echo -e "${GREEN}Tempo:${NC}            http://localhost:${TEMPO_PORT:-3200}"
    echo ""
    echo -e "${CYAN}Integration Endpoints:${NC}"
    echo -e "${GREEN}OTEL gRPC:${NC}        localhost:${OTEL_GRPC_PORT:-4317}"
    echo -e "${GREEN}OTEL HTTP:${NC}        localhost:${OTEL_HTTP_PORT:-4318}"
    echo -e "${GREEN}Jaeger gRPC:${NC}      localhost:${JAEGER_GRPC_PORT:-14250}"
    echo ""
}

backup_data() {
    echo -e "${BLUE}▶ Backing up observability data...${NC}"
    timestamp=$(date +%Y%m%d_%H%M%S)
    backup_dir="./backups/backup_$timestamp"
    mkdir -p "$backup_dir"
    
    # Stop services
    docker-compose stop
    
    # Backup volumes
    docker run --rm -v observability_prometheus-data:/data -v "$(pwd)/$backup_dir":/backup alpine tar czf /backup/prometheus-data.tar.gz -C /data .
    docker run --rm -v observability_loki-data:/data -v "$(pwd)/$backup_dir":/backup alpine tar czf /backup/loki-data.tar.gz -C /data .
    docker run --rm -v observability_tempo-data:/data -v "$(pwd)/$backup_dir":/backup alpine tar czf /backup/tempo-data.tar.gz -C /data .
    docker run --rm -v observability_grafana-data:/data -v "$(pwd)/$backup_dir":/backup alpine tar czf /backup/grafana-data.tar.gz -C /data .
    
    # Restart services
    docker-compose start
    
    echo -e "${GREEN}✅ Backup completed: $backup_dir${NC}"
    du -sh "$backup_dir"
}

clean_data() {
    echo -e "${RED}⚠️  WARNING: This will delete all observability data!${NC}"
    read -p "Are you sure? (yes/no): " -r
    if [[ $REPLY == "yes" ]]; then
        echo -e "${YELLOW}▶ Cleaning all data...${NC}"
        docker-compose down -v
        echo -e "${GREEN}✅ All data cleaned${NC}"
    else
        echo -e "${BLUE}Cancelled${NC}"
    fi
}

# Main command handler
case "${1:-}" in
    start)
        start_stack
        ;;
    stop)
        stop_stack
        ;;
    restart)
        restart_stack
        ;;
    status)
        show_status
        ;;
    health)
        check_health
        ;;
    logs)
        show_logs
        ;;
    logs-grafana)
        show_logs_service "grafana"
        ;;
    logs-prometheus)
        show_logs_service "prometheus"
        ;;
    logs-loki)
        show_logs_service "loki"
        ;;
    logs-tempo)
        show_logs_service "tempo"
        ;;
    logs-jaeger)
        show_logs_service "jaeger"
        ;;
    logs-otel)
        show_logs_service "otel-collector"
        ;;
    urls)
        show_urls
        ;;
    backup)
        backup_data
        ;;
    clean)
        clean_data
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        show_help
        exit 1
        ;;
esac