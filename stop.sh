#!/bin/bash
# =============================================================================
# Stop Infrastructure Services
# =============================================================================
# Usage:
#   ./stop.sh              # Stop all services
#   ./stop.sh redis        # Stop specific service
#   ./stop.sh redis postgres  # Stop multiple services
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
CYAN='\033[0;36m'
NC='\033[0m'

log_step() { echo -e "${CYAN}[→]${NC} $1"; }
log_info() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

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

# Show help
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [service...]"
    echo ""
    echo "Stop infrastructure services"
    echo ""
    echo "Examples:"
    echo "  $0                    # Stop all services"
    echo "  $0 redis              # Stop redis only"
    echo "  $0 redis postgres     # Stop redis and postgres"
    echo "  $0 glitchtip          # Stop glitchtip only"
    echo ""
    echo "Available services:"
    for dir in services/*/; do
        if [[ -f "${dir}docker-compose.yml" ]]; then
            echo "  $(basename "$dir")"
        fi
    done
    exit 0
fi

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  Stopping Infrastructure Services${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [[ $# -gt 0 ]]; then
    # Stop specific services
    for service in "$@"; do
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

echo ""
log_info "Done"
echo ""
