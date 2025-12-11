#!/bin/bash

# OpenSearch Production Management Script
# ======================================

set -e

# Require authentication
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$INFRA_ROOT/lib/common.sh"
require_auth

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
ENV_FILE="$SCRIPT_DIR/.env"

# Load environment variables
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
else
    echo -e "${RED}❌ .env file not found!${NC}"
    exit 1
fi

show_usage() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}🔍 OpenSearch Production Management${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${GREEN}Available Commands:${NC}"
    echo -e "  ${GREEN}start${NC}         Start OpenSearch cluster"
    echo -e "  ${GREEN}stop${NC}          Stop OpenSearch cluster"
    echo -e "  ${GREEN}restart${NC}       Restart OpenSearch cluster"
    echo -e "  ${GREEN}status${NC}        Show cluster status"
    echo -e "  ${GREEN}logs${NC}          View cluster logs"
    echo -e "  ${GREEN}health${NC}        Check cluster health"
    echo -e "  ${GREEN}backup${NC}        Create cluster backup"
    echo -e "  ${GREEN}restore${NC}       Restore from backup"
    echo -e "  ${GREEN}monitoring${NC}    Start with monitoring"
    echo -e "  ${GREEN}dashboard${NC}     Open OpenSearch Dashboards"
    echo -e "  ${GREEN}reset-password${NC} Reset admin password"
    echo -e "  ${GREEN}cleanup${NC}       Clean up data and logs"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo -e "  $0 start          # Start the cluster"
    echo -e "  $0 health         # Check cluster health"
    echo -e "  $0 logs opensearch-node1  # View specific service logs"
    echo -e "  $0 monitoring     # Start with monitoring enabled"
    echo ""
}

check_prerequisites() {
    echo -e "${BLUE}▶ Checking prerequisites...${NC}"
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}❌ Docker is not installed${NC}"
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        echo -e "${RED}❌ Docker Compose is not installed${NC}"
        exit 1
    fi
    
    # Check system resources
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}' 2>/dev/null || echo "4096")
        if [[ $TOTAL_MEM -lt 4096 ]]; then
            echo -e "${YELLOW}⚠️  Warning: Less than 4GB RAM detected. OpenSearch may run slowly.${NC}"
        fi
        
        # Check vm.max_map_count on Linux
        MAX_MAP_COUNT=$(sysctl vm.max_map_count | cut -d' ' -f3)
        if [[ $MAX_MAP_COUNT -lt 262144 ]]; then
            echo -e "${YELLOW}⚠️  Setting vm.max_map_count for OpenSearch...${NC}"
            sudo sysctl -w vm.max_map_count=262144
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        TOTAL_MEM=$(sysctl -n hw.memsize | awk '{print $1/1024/1024}' 2>/dev/null || echo "4096")
        if [[ $TOTAL_MEM -lt 4096 ]]; then
            echo -e "${YELLOW}⚠️  Warning: Less than 4GB RAM detected. OpenSearch may run slowly.${NC}"
        fi
    fi
    
    echo -e "${GREEN}✅ Prerequisites check completed${NC}"
}

start_opensearch() {
    echo -e "${BLUE}▶ Starting OpenSearch cluster...${NC}"
    
    # Set proper permissions
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo chown -R 1000:1000 ./data ./logs ./backup 2>/dev/null || true
    else
        # macOS/other systems
        chmod -R 755 ./data ./logs ./backup 2>/dev/null || true
    fi
    
    # Start services
    docker-compose -f "$COMPOSE_FILE" up -d opensearch-node1 opensearch-dashboards
    
    echo -e "${GREEN}✅ OpenSearch cluster started${NC}"
    echo ""
    show_endpoints
}

stop_opensearch() {
    echo -e "${YELLOW}▶ Stopping OpenSearch cluster...${NC}"
    docker-compose -f "$COMPOSE_FILE" down
    echo -e "${GREEN}✅ OpenSearch cluster stopped${NC}"
}

restart_opensearch() {
    echo -e "${YELLOW}▶ Restarting OpenSearch cluster...${NC}"
    docker-compose -f "$COMPOSE_FILE" restart
    echo -e "${GREEN}✅ OpenSearch cluster restarted${NC}"
}

show_status() {
    echo -e "${BLUE}▶ OpenSearch Cluster Status:${NC}"
    echo ""
    docker-compose -f "$COMPOSE_FILE" ps
    echo ""
    
    if docker ps | grep -q "opensearch-node1"; then
        echo -e "${GREEN}✅ OpenSearch node is running${NC}"
        
        # Check cluster health
        echo -e "${BLUE}▶ Cluster Health:${NC}"
        curl -s -u admin:${OPENSEARCH_INITIAL_ADMIN_PASSWORD} \
             "http://localhost:${OPENSEARCH_PORT}/_cluster/health?pretty" 2>/dev/null || \
             echo -e "${YELLOW}⚠️  Health check failed - cluster may still be starting${NC}"
    else
        echo -e "${RED}❌ OpenSearch node is not running${NC}"
    fi
}

show_logs() {
    SERVICE=${1:-opensearch-node1}
    echo -e "${BLUE}▶ Showing logs for ${SERVICE}...${NC}"
    docker-compose -f "$COMPOSE_FILE" logs -f "$SERVICE"
}

check_health() {
    echo -e "${BLUE}▶ Comprehensive health check...${NC}"
    echo ""
    
    # Container health
    echo -e "${CYAN}📦 Container Status:${NC}"
    docker-compose -f "$COMPOSE_FILE" ps
    echo ""
    
    # OpenSearch API health
    echo -e "${CYAN}🔍 OpenSearch API Health:${NC}"
    if curl -s -u admin:${OPENSEARCH_INITIAL_ADMIN_PASSWORD} \
            "http://localhost:${OPENSEARCH_PORT}/_cluster/health" &>/dev/null; then
        
        # Cluster health
        HEALTH=$(curl -s -u admin:${OPENSEARCH_INITIAL_ADMIN_PASSWORD} \
                     "http://localhost:${OPENSEARCH_PORT}/_cluster/health" | \
                     jq -r '.status' 2>/dev/null || echo "unknown")
        
        case $HEALTH in
            "green")
                echo -e "${GREEN}✅ Cluster status: GREEN (healthy)${NC}"
                ;;
            "yellow")
                echo -e "${YELLOW}⚠️  Cluster status: YELLOW (functional but degraded)${NC}"
                ;;
            "red")
                echo -e "${RED}❌ Cluster status: RED (critical issues)${NC}"
                ;;
            *)
                echo -e "${YELLOW}⚠️  Cluster status: UNKNOWN${NC}"
                ;;
        esac
        
        # Node info
        echo -e "${CYAN}📊 Node Information:${NC}"
        curl -s -u admin:${OPENSEARCH_INITIAL_ADMIN_PASSWORD} \
             "http://localhost:${OPENSEARCH_PORT}/_nodes/_local" | \
             jq '.nodes | to_entries[0].value | {name: .name, version: .version, os: .os.name, jvm: .jvm.version}' 2>/dev/null || \
             echo "Could not retrieve node information"
        
    else
        echo -e "${RED}❌ OpenSearch API is not responding${NC}"
    fi
    
    # Dashboard health
    echo ""
    echo -e "${CYAN}📊 Dashboard Health:${NC}"
    if curl -s "http://localhost:${OPENSEARCH_DASHBOARDS_PORT}/api/status" &>/dev/null; then
        echo -e "${GREEN}✅ OpenSearch Dashboards is responding${NC}"
    else
        echo -e "${RED}❌ OpenSearch Dashboards is not responding${NC}"
    fi
}

start_monitoring() {
    echo -e "${BLUE}▶ Starting OpenSearch with monitoring...${NC}"
    
    # Set proper permissions
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo chown -R 1000:1000 ./data ./logs ./backup 2>/dev/null || true
    else
        # macOS/other systems
        chmod -R 755 ./data ./logs ./backup 2>/dev/null || true
    fi
    
    # Start with monitoring profile
    docker-compose -f "$COMPOSE_FILE" --profile monitoring up -d
    
    echo -e "${GREEN}✅ OpenSearch with monitoring started${NC}"
    echo ""
    show_endpoints
}

show_endpoints() {
    echo -e "${CYAN}🔗 Service Endpoints:${NC}"
    echo -e "  ${GREEN}OpenSearch API:${NC}       http://localhost:${OPENSEARCH_PORT}"
    echo -e "  ${GREEN}OpenSearch Dashboards:${NC} http://localhost:${OPENSEARCH_DASHBOARDS_PORT}"
    echo ""
    echo -e "${CYAN}🔑 Default Credentials:${NC}"
    echo -e "  ${GREEN}Username:${NC} admin"
    echo -e "  ${GREEN}Password:${NC} ${OPENSEARCH_INITIAL_ADMIN_PASSWORD}"
    echo ""
    echo -e "${YELLOW}⚠️  Security Note: Change default password in production!${NC}"
}

open_dashboard() {
    echo -e "${BLUE}▶ Opening OpenSearch Dashboards...${NC}"
    
    if command -v open &> /dev/null; then
        open "http://localhost:${OPENSEARCH_DASHBOARDS_PORT}"
    elif command -v xdg-open &> /dev/null; then
        xdg-open "http://localhost:${OPENSEARCH_DASHBOARDS_PORT}"
    else
        echo -e "${CYAN}📊 Open this URL in your browser:${NC}"
        echo -e "  http://localhost:${OPENSEARCH_DASHBOARDS_PORT}"
    fi
}

reset_password() {
    echo -e "${YELLOW}▶ Resetting admin password...${NC}"
    
    read -p "Enter new admin password: " -s NEW_PASSWORD
    echo ""
    
    if [[ -z "$NEW_PASSWORD" ]]; then
        echo -e "${RED}❌ Password cannot be empty${NC}"
        exit 1
    fi
    
    # Update password via API
    curl -X PUT "http://localhost:${OPENSEARCH_PORT}/_plugins/_security/api/internalusers/admin" \
         -u admin:${OPENSEARCH_INITIAL_ADMIN_PASSWORD} \
         -H "Content-Type: application/json" \
         -d "{\"password\":\"$NEW_PASSWORD\"}" && \
    echo -e "${GREEN}✅ Password updated successfully${NC}" || \
    echo -e "${RED}❌ Failed to update password${NC}"
}

create_backup() {
    echo -e "${BLUE}▶ Creating cluster backup...${NC}"
    
    BACKUP_NAME="backup_$(date +%Y%m%d_%H%M%S)"
    
    # Register backup repository
    curl -X PUT "http://localhost:${OPENSEARCH_PORT}/_snapshot/backup_repo" \
         -u admin:${OPENSEARCH_INITIAL_ADMIN_PASSWORD} \
         -H "Content-Type: application/json" \
         -d '{
             "type": "fs",
             "settings": {
                 "location": "/usr/share/opensearch/backup"
             }
         }' && \
    
    # Create snapshot
    curl -X PUT "http://localhost:${OPENSEARCH_PORT}/_snapshot/backup_repo/$BACKUP_NAME" \
         -u admin:${OPENSEARCH_INITIAL_ADMIN_PASSWORD} \
         -H "Content-Type: application/json" \
         -d '{"include_global_state": true}' && \
    
    echo -e "${GREEN}✅ Backup '$BACKUP_NAME' created successfully${NC}" || \
    echo -e "${RED}❌ Backup creation failed${NC}"
}

cleanup_data() {
    echo -e "${YELLOW}⚠️  This will delete all OpenSearch data and logs!${NC}"
    read -p "Are you sure? (yes/no): " CONFIRM
    
    if [[ "$CONFIRM" == "yes" ]]; then
        stop_opensearch
        echo -e "${YELLOW}▶ Cleaning up data and logs...${NC}"
        sudo rm -rf ./data/* ./logs/* 2>/dev/null || true
        echo -e "${GREEN}✅ Cleanup completed${NC}"
    else
        echo -e "${BLUE}Operation cancelled${NC}"
    fi
}

# Main command handling
case "${1:-help}" in
    "start")
        check_prerequisites
        start_opensearch
        ;;
    "stop")
        stop_opensearch
        ;;
    "restart")
        restart_opensearch
        ;;
    "status")
        show_status
        ;;
    "logs")
        show_logs "$2"
        ;;
    "health")
        check_health
        ;;
    "monitoring")
        check_prerequisites
        start_monitoring
        ;;
    "dashboard")
        open_dashboard
        ;;
    "backup")
        create_backup
        ;;
    "reset-password")
        reset_password
        ;;
    "cleanup")
        cleanup_data
        ;;
    "help"|*)
        show_usage
        ;;
esac
