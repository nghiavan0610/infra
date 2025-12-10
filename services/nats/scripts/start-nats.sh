#!/bin/bash

# Enhanced NATS startup script for production authentication
# Supports multiple environments and better error handling

set -e  # Exit on any error

# Colors for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$BASE_DIR/.env"
NATS_CONF="$BASE_DIR/config/nats.conf"
AUTH_TEMPLATE="$BASE_DIR/config/auth.conf.template"
AUTH_CONF="$BASE_DIR/config/auth.conf"
COMPOSE_FILE="$BASE_DIR/docker-compose.yml"

# Functions
print_header() {
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${PURPLE}� NATS Production Startup Script${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_step() {
    echo -e "${BLUE}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

check_prerequisites() {
    print_step "Checking prerequisites..."
    
    # Check if Docker is running
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker and try again."
        exit 1
    fi
    
    # Check if docker-compose is available
    if ! command -v docker-compose > /dev/null 2>&1; then
        print_error "docker-compose is not installed. Please install it and try again."
        exit 1
    fi
    
    # Check if envsubst is available (not needed for inline auth but kept for compatibility)
    if ! command -v envsubst > /dev/null 2>&1; then
        print_warning "envsubst is not available but not required for inline authentication"
        print_warning "Install gettext package if you need environment variable substitution"
    fi
    
    print_success "All prerequisites met"
}

check_environment() {
    print_step "Checking environment configuration..."
    
    # Check if .env file exists
    if [ ! -f "$ENV_FILE" ]; then
        print_error ".env file not found!"
        print_error "Please create $ENV_FILE with your credentials"
        echo ""
        echo "Example .env file:"
        echo "NATS_PORT=4222"
        echo "TEACHER_SERVICE_USER=teacher-service"
        echo "TEACHER_SERVICE_PASS=secure-password"
        exit 1
    fi
    
    # Check if auth template exists
    if [ ! -f "$AUTH_TEMPLATE" ]; then
        print_error "Authentication template not found: $AUTH_TEMPLATE"
        print_error "Please ensure the auth template exists"
        exit 1
    fi
    
    # Check if nats.conf exists
    if [ ! -f "$NATS_CONF" ]; then
        print_error "NATS configuration file not found: $NATS_CONF"
        exit 1
    fi
    
    # Check if docker-compose.yml exists
    if [ ! -f "$COMPOSE_FILE" ]; then
        print_error "Docker Compose file not found: $COMPOSE_FILE"
        exit 1
    fi
    
    print_success "Environment configuration validated"
}

load_environment() {
    print_step "Loading environment variables..."
    
    # Load environment variables
    set -a  # Automatically export all variables
    source "$ENV_FILE"
    set +a  # Stop auto-export
    
    print_success "Environment variables loaded"
}

generate_auth_config() {
    print_step "Generating authentication configuration from template..."
    
    # Generate auth.conf from template using environment variables
    envsubst < "$AUTH_TEMPLATE" > "$AUTH_CONF"
    
    # Validate generated auth.conf
    if [ ! -f "$AUTH_CONF" ] || [ ! -s "$AUTH_CONF" ]; then
        print_error "Failed to generate auth.conf from template"
        exit 1
    fi
    
    # Check if auth.conf has required content
    if ! grep -q "accounts" "$AUTH_CONF" 2>/dev/null; then
        print_error "Generated auth.conf appears invalid (no accounts section)"
        exit 1
    fi
    
    print_success "Authentication configuration generated successfully"
}

validate_config() {
    print_step "Validating generated authentication..."
    
    # Check if generated auth.conf has service accounts
    local services=("${TEACHER_SERVICE_USER}" "${USER_SERVICE_USER}" "${COURSE_SERVICE_USER}" "${NOTIFICATION_SERVICE_USER}")
    for service in "${services[@]}"; do
        if grep -q "$service" "$AUTH_CONF" 2>/dev/null; then
            print_success "$service account configured"
        else
            print_warning "$service account not found in generated config"
        fi
    done
    
    # Check for common auth configuration elements
    if grep -q "accounts" "$AUTH_CONF" 2>/dev/null; then
        print_success "Accounts block found"
    else
        print_error "No accounts block in generated config"
        exit 1
    fi
    
    print_success "Authentication validation complete"
}

stop_existing() {
    print_step "Stopping existing NATS containers..."

    cd "$BASE_DIR"
    docker compose down > /dev/null 2>&1 || true

    print_success "Existing containers stopped"
}

start_nats() {
    print_step "Starting NATS server with authentication..."

    # Start NATS
    cd "$BASE_DIR"
    docker compose up -d
    
    # Wait for NATS to be ready
    print_step "Waiting for NATS to be ready..."
    sleep 5
    
    # Check if NATS is healthy
    for i in {1..30}; do
        if docker compose ps nats | grep -q "healthy\|Up"; then
            break
        fi
        if [ $i -eq 30 ]; then
            print_error "NATS failed to start properly"
            docker compose logs nats
            exit 1
        fi
        sleep 1
    done
    
    print_success "NATS server started successfully"
}

print_summary() {
    print_step "Deployment Summary"
    echo ""
    echo -e "${CYAN}🔗 Service Endpoints:${NC}"
    echo -e "  NATS Client:     nats://localhost:${NATS_PORT:-4222}"
    echo -e "  HTTP Monitoring: http://localhost:${NATS_HTTP_PORT:-8222}"
    echo -e "  Surveyor UI:     http://localhost:7777 (if monitoring profile enabled)"
    echo ""
    echo -e "${CYAN}🔑 Service Credentials (from .env):${NC}"
    echo -e "  Teacher Service:      ${TEACHER_SERVICE_USER} / ${TEACHER_SERVICE_PASS}"
    echo -e "  User Service:         ${USER_SERVICE_USER} / ${USER_SERVICE_PASS}"
    echo -e "  Course Service:       ${COURSE_SERVICE_USER} / ${COURSE_SERVICE_PASS}"
    echo -e "  Notification Service: ${NOTIFICATION_SERVICE_USER} / ${NOTIFICATION_SERVICE_PASS}"
    echo -e "  System Admin:         ${SYS_USER} / ${SYS_PASS}"
    echo ""
    echo -e "${YELLOW}⚠️  Security Note: Keep .env file secure and update passwords regularly!${NC}"
    echo ""
    echo -e "${CYAN}📊 Useful Commands:${NC}"
    echo -e "  View logs:           docker-compose logs -f nats"
    echo -e "  Check status:        docker-compose ps"
    echo -e "  Stop NATS:           docker-compose down"
    echo -e "  Management CLI:      ./nats-cli.sh"
    echo ""
    echo -e "${CYAN}➕ Adding New Services:${NC}"
    echo -e "  1. Add credentials to .env"
    echo -e "  2. Add service to auth.conf.template"
    echo -e "  3. Run: ./start-nats.sh"
    echo -e "  📖 Guide: cat ADDING_SERVICES.md"
    echo ""
    echo -e "${GREEN}🎉 NATS is ready for production use!${NC}"
}

# Main execution
main() {
    print_header
    check_prerequisites
    check_environment
    load_environment
    generate_auth_config
    validate_config
    stop_existing
    start_nats
    print_summary
}

# Run main function
main "$@"
