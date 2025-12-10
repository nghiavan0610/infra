#!/bin/bash
# =============================================================================
# Stop All Infrastructure Services
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load shared library
source "$SCRIPT_DIR/lib/common.sh"

log_header "Stopping Infrastructure Services"

# Find all docker-compose.yml files and stop them
for dir in services/*; do
    if [[ -f "$dir/docker-compose.yml" ]]; then
        name=$(basename "$dir")
        log_step "Stopping $name..."
        (cd "$dir" && docker compose down 2>/dev/null) || true
    fi
done

echo ""
log_info "All services stopped"
echo ""
