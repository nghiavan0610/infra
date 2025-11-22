#!/bin/bash

# NATS Management Utility Script

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
    echo -e "${PURPLE}🛠️  NATS Management Utility${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${CYAN}Usage: $0 [COMMAND]${NC}"
    echo ""
    echo -e "${CYAN}Commands:${NC}"
    echo -e "  ${GREEN}start${NC}         Start NATS server with authentication"
    echo -e "  ${GREEN}stop${NC}          Stop NATS server"
    echo -e "  ${GREEN}restart${NC}       Restart NATS server"
    echo -e "  ${GREEN}status${NC}        Show NATS status and health"
    echo -e "  ${GREEN}logs${NC}          Show NATS logs (follow mode)"
    echo -e "  ${GREEN}logs-tail${NC}     Show last 50 log lines"
    echo -e "  ${GREEN}logs-error${NC}    Show only error logs"
    echo -e "  ${GREEN}monitor${NC}       Start with monitoring dashboard"
    echo -e "  ${GREEN}health${NC}        Comprehensive health check"
    echo -e "  ${GREEN}backup${NC}        Backup JetStream data"
    echo -e "  ${GREEN}restore${NC}       Restore JetStream data"
    echo -e "  ${GREEN}clean${NC}         Clean all data (destructive)"
    echo -e "  ${GREEN}test-auth${NC}     Test authentication setup"
    echo -e "  ${GREEN}reset-auth${NC}    Reset authentication configuration"
    echo -e "  ${GREEN}help${NC}          Show this help message"
    echo ""
    echo -e "${CYAN}Examples:${NC}"
    echo -e "  $0 start          # Start NATS with auth"
    echo -e "  $0 monitor        # Start with monitoring UI"
    echo -e "  $0 logs           # Follow logs in real-time"
    echo -e "  $0 health         # Check system health"
}

start_nats() {
    echo -e "${BLUE}▶ Starting NATS...${NC}"
    
    # Check if this is first run or needs full setup
    if ! docker ps | grep -q "nats" 2>/dev/null; then
        echo -e "${YELLOW}⚠️  Running full production setup...${NC}"
        ./start-nats.sh
    else
        echo -e "${BLUE}▶ Using quick start (NATS already running)...${NC}"
        docker-compose restart nats
        echo -e "${GREEN}✅ NATS restarted${NC}"
    fi
}

stop_nats() {
    echo -e "${YELLOW}▶ Stopping NATS server...${NC}"
    docker-compose down
    echo -e "${GREEN}✅ NATS server stopped${NC}"
}

restart_nats() {
    echo -e "${YELLOW}▶ Restarting NATS server...${NC}"
    docker-compose restart nats
    echo -e "${GREEN}✅ NATS server restarted${NC}"
}

show_status() {
    echo -e "${BLUE}▶ NATS Server Status:${NC}"
    echo ""
    docker-compose ps
    echo ""
    
    if docker ps | grep -q "nats"; then
        echo -e "${GREEN}✅ NATS container is running${NC}"
        
        # Show container health
        health=$(docker inspect nats --format='{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
        if [ "$health" = "healthy" ]; then
            echo -e "${GREEN}✅ Container health: $health${NC}"
        else
            echo -e "${YELLOW}⚠️  Container health: $health${NC}"
        fi
        
        # Check configuration
        echo ""
        echo -e "${CYAN}⚙️  Configuration Status:${NC}"
        if [ -f "./config/auth.conf" ] && grep -q "accounts" "./config/auth.conf" 2>/dev/null; then
            echo -e "${GREEN}✅ External authentication configured${NC}"
        elif grep -q "include.*auth.conf" "./config/nats.conf" 2>/dev/null; then
            echo -e "${GREEN}✅ Authentication include found in nats.conf${NC}"
        else
            echo -e "${YELLOW}⚠️  No authentication configured${NC}"
        fi
        
        # Show resource usage
        echo ""
        echo -e "${CYAN}📊 Resource Usage:${NC}"
        docker stats nats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}"
    else
        echo -e "${RED}❌ NATS container is not running${NC}"
    fi
}

show_logs() {
    echo -e "${BLUE}▶ NATS logs (Ctrl+C to exit)...${NC}"
    echo ""
    
    if [ -f "./logs/nats.log" ]; then
        echo -e "${CYAN}📄 Following file-based logs: ./logs/nats.log${NC}"
        tail -f ./logs/nats.log
    else
        echo -e "${YELLOW}⚠️  Log file not found, trying Docker logs...${NC}"
        docker-compose logs -f nats
    fi
}

show_logs_tail() {
    echo -e "${BLUE}▶ Last 50 NATS log entries:${NC}"
    echo ""
    
    if [ -f "./logs/nats.log" ]; then
        tail -n 50 ./logs/nats.log
    else
        echo -e "${YELLOW}⚠️  Log file not found${NC}"
    fi
}

show_logs_error() {
    echo -e "${BLUE}▶ NATS error logs:${NC}"
    echo ""
    
    if [ -f "./logs/nats.log" ]; then
        grep -E "\[ERR\]|\[FTL\]" ./logs/nats.log | tail -20
    else
        echo -e "${YELLOW}⚠️  Log file not found${NC}"
    fi
}

start_monitoring() {
    echo -e "${BLUE}▶ Starting NATS with monitoring dashboard...${NC}"
    docker-compose --profile monitoring up -d
    echo -e "${GREEN}✅ NATS and monitoring started${NC}"
    echo ""
    echo -e "${CYAN}📊 Available Monitoring Options:${NC}"
    echo -e "  ${GREEN}Built-in NATS Monitoring:${NC} http://localhost:8222"
    echo -e "  ${GREEN}Connection Info:${NC}         http://localhost:8222/connz"
    echo -e "  ${GREEN}JetStream Info:${NC}          http://localhost:8222/jsz"
    echo -e "  ${GREEN}Prometheus Metrics:${NC}      http://localhost:7777/metrics"
    echo ""
}

health_check() {
    echo -e "${BLUE}▶ Comprehensive health check...${NC}"
    echo ""
    
    # Check Docker
    if docker info > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Docker is running${NC}"
    else
        echo -e "${RED}❌ Docker is not running${NC}"
        return 1
    fi
    
    # Check container
    if docker ps | grep -q "nats"; then
        echo -e "${GREEN}✅ NATS container is running${NC}"
    else
        echo -e "${RED}❌ NATS container is not running${NC}"
        return 1
    fi
    
    # Check HTTP monitoring
    if curl -s http://localhost:${NATS_HTTP_PORT:-8222}/healthz > /dev/null 2>&1; then
        echo -e "${GREEN}✅ HTTP monitoring endpoint is healthy${NC}"
    else
        echo -e "${RED}❌ HTTP monitoring endpoint is not responding${NC}"
    fi
    
    # Check NATS client connection
    if docker exec nats nats --server=localhost:4222 server info > /dev/null 2>&1; then
        echo -e "${GREEN}✅ NATS server is accepting connections${NC}"
    else
        echo -e "${RED}❌ NATS server is not responding to client connections${NC}"
    fi
    
    # Check JetStream
    if docker exec nats nats --server=localhost:4222 stream ls > /dev/null 2>&1; then
        echo -e "${GREEN}✅ JetStream is operational${NC}"
    else
        echo -e "${YELLOW}⚠️  JetStream check failed (may be normal if no streams exist)${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}📈 Current Connections:${NC}"
    docker exec nats nats --server=localhost:4222 server info 2>/dev/null | grep -E "(connections|subscriptions)" || echo "Unable to fetch connection info"
}

backup_data() {
    echo -e "${BLUE}▶ Backing up JetStream data...${NC}"
    timestamp=$(date +%Y%m%d_%H%M%S)
    backup_dir="./backups/jetstream_backup_$timestamp"
    mkdir -p "$backup_dir"
    
    if [ -d "./data" ]; then
        cp -r ./data/* "$backup_dir/" 2>/dev/null || true
        echo -e "${GREEN}✅ Backup completed: $backup_dir${NC}"
        du -sh "$backup_dir"
    else
        echo -e "${YELLOW}⚠️  No data directory found${NC}"
    fi
}

test_auth() {
    echo -e "${BLUE}▶ Testing authentication setup...${NC}"
    
    echo -e "${CYAN}🔑 Testing template-based authentication:${NC}"
    
    # Check if .env file exists
    if [ -f ".env" ]; then
        echo -e "${GREEN}✅ .env file found${NC}"
        
        # Load environment variables to check services
        source .env 2>/dev/null || true
        
        # Check if auth.conf exists and has content
        if [ -f "./config/auth.conf" ] && [ -s "./config/auth.conf" ]; then
            echo -e "${GREEN}✅ Generated auth.conf found${NC}"
            
            # Check if auth.conf has authentication configured
            if grep -q "accounts" "./config/auth.conf" 2>/dev/null; then
                echo -e "${GREEN}✅ Authentication accounts found in auth.conf${NC}"
                
                # Check specific services
                local services=("${TEACHER_SERVICE_USER}" "${USER_SERVICE_USER}" "${COURSE_SERVICE_USER}" "${NOTIFICATION_SERVICE_USER}")
                for service in "${services[@]}"; do
                    if [ -n "$service" ] && grep -q "$service" "./config/auth.conf" 2>/dev/null; then
                        echo -e "${GREEN}✅ $service configured${NC}"
                    elif [ -n "$service" ]; then
                        echo -e "${RED}❌ $service not found${NC}"
                    fi
                done
            else
                echo -e "${RED}❌ No authentication accounts found in auth.conf${NC}"
            fi
        else
            echo -e "${RED}❌ Generated auth.conf not found or empty${NC}"
            echo -e "${YELLOW}💡 Run './start-nats.sh' to generate authentication${NC}"
        fi
    else
        echo -e "${RED}❌ .env file not found${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}🔐 Authentication status:${NC}"
    if docker exec nats cat /etc/nats/auth.conf 2>/dev/null | grep -q "accounts" 2>/dev/null; then
        echo -e "${GREEN}✅ Authentication configuration is active in container${NC}"
    else
        echo -e "${YELLOW}⚠️  Authentication configuration may not be loaded${NC}"
    fi
    
    # Check template status
    echo ""
    echo -e "${CYAN}📝 Template Status:${NC}"
    if [ -f "./config/auth.conf.template" ]; then
        echo -e "${GREEN}✅ Authentication template found${NC}"
    else
        echo -e "${RED}❌ Authentication template missing${NC}"
    fi
}

clean_data() {
    echo -e "${RED}⚠️  WARNING: This will remove ALL NATS data!${NC}"
    read -p "Are you sure you want to continue? Type 'yes' to confirm: " confirm
    
    if [ "$confirm" = "yes" ]; then
        echo -e "${YELLOW}▶ Stopping NATS and removing data...${NC}"
        docker-compose down -v
        rm -rf ./data/* 2>/dev/null || true
        rm -rf ./logs/* 2>/dev/null || true
        echo -e "${GREEN}✅ All data removed${NC}"
    else
        echo -e "${GREEN}✅ Operation cancelled${NC}"
    fi
}

reset_auth() {
    echo -e "${YELLOW}▶ Resetting authentication configuration...${NC}"
    echo ""
    echo "This will:"
    echo "1. Regenerate auth.conf from template"
    echo "2. Restart NATS with new configuration"
    echo ""
    read -p "Continue? (y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}▶ Regenerating authentication...${NC}"
        ./start-nats.sh
    else
        echo -e "${GREEN}✅ Operation cancelled${NC}"
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
    "logs-error")
        show_logs_error
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
