#!/bin/bash
# =============================================================================
# Stop Infrastructure Services
# =============================================================================
# Usage:
#   ./stop.sh              # Stop all services
#   ./stop.sh redis        # Stop specific service
#   ./stop.sh --prune      # Stop all + cleanup unused Docker resources
#   ./stop.sh --prune-all  # Stop all + aggressive cleanup (includes volumes)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load shared library
source "$SCRIPT_DIR/lib/common.sh"

# Require authentication
require_auth

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_step() { echo -e "${CYAN}[→]${NC} $1"; }
log_info() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

# Parse flags
PRUNE=false
PRUNE_ALL=false
SERVICES=()

for arg in "$@"; do
    case $arg in
        --prune)
            PRUNE=true
            ;;
        --prune-all)
            PRUNE_ALL=true
            ;;
        --help|-h)
            echo "Usage: $0 [options] [service...]"
            echo ""
            echo "Stop infrastructure services"
            echo ""
            echo "Options:"
            echo "  --prune       Clean up unused images and containers after stopping"
            echo "  --prune-all   Aggressive cleanup including unused volumes (WARNING: data loss)"
            echo "  -h, --help    Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                    # Stop all services"
            echo "  $0 redis              # Stop redis only"
            echo "  $0 redis postgres     # Stop redis and postgres"
            echo "  $0 --prune            # Stop all + clean unused images"
            echo "  $0 --prune-all        # Stop all + clean images and volumes"
            echo ""
            echo "Available services:"
            for dir in services/*/; do
                if [[ -f "${dir}docker-compose.yml" ]]; then
                    echo "  $(basename "$dir")"
                fi
            done
            exit 0
            ;;
        *)
            SERVICES+=("$arg")
            ;;
    esac
done

stop_service() {
    local name=$1
    local dir="services/$name"

    if [[ -f "$dir/docker-compose.yml" ]]; then
        log_step "Stopping $name..."
        (cd "$dir" && docker compose down 2>/dev/null) && log_info "$name stopped" || log_error "Failed to stop $name"
    else
        log_error "Service not found: $name"
        return 1
    fi
}

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  Stopping Infrastructure Services${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [[ ${#SERVICES[@]} -gt 0 ]]; then
    # Stop specific services
    for service in "${SERVICES[@]}"; do
        stop_service "$service"
    done
else
    # Stop all services
    for dir in services/*; do
        if [[ -f "$dir/docker-compose.yml" ]]; then
            name=$(basename "$dir")
            stop_service "$name"
        fi
    done
fi

# Cleanup if requested
if [[ "$PRUNE_ALL" == true ]]; then
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Cleaning Up Docker Resources (Aggressive)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    log_warn "This will remove unused images, containers, networks, AND volumes"

    log_step "Removing stopped containers..."
    docker container prune -f 2>/dev/null && log_info "Containers cleaned"

    log_step "Removing unused networks..."
    docker network prune -f 2>/dev/null && log_info "Networks cleaned"

    log_step "Removing unused images..."
    docker image prune -a -f 2>/dev/null && log_info "Images cleaned"

    log_step "Removing unused volumes..."
    docker volume prune -f 2>/dev/null && log_info "Volumes cleaned"

    # Show space freed
    echo ""
    log_info "Disk usage after cleanup:"
    df -h / | tail -1 | awk '{print "  Root: " $3 " used / " $4 " available (" $5 " used)"}'

elif [[ "$PRUNE" == true ]]; then
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Cleaning Up Docker Resources${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    log_step "Removing stopped containers..."
    docker container prune -f 2>/dev/null && log_info "Containers cleaned"

    log_step "Removing unused networks..."
    docker network prune -f 2>/dev/null && log_info "Networks cleaned"

    log_step "Removing dangling images..."
    docker image prune -f 2>/dev/null && log_info "Dangling images cleaned"

    log_step "Removing unused images (not used by any container)..."
    docker image prune -a -f 2>/dev/null && log_info "Unused images cleaned"

    # Show space freed
    echo ""
    log_info "Disk usage after cleanup:"
    df -h / | tail -1 | awk '{print "  Root: " $3 " used / " $4 " available (" $5 " used)"}'

    echo ""
    log_warn "Volumes were NOT removed. Use --prune-all to remove unused volumes (data loss warning)"
fi

echo ""
log_info "Done"
echo ""
