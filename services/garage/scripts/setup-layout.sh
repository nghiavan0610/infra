#!/bin/bash
# =============================================================================
# Garage Layout Setup Script
# =============================================================================
# Assigns capacity to nodes and applies the cluster layout
# Usage: ./scripts/setup-layout.sh [capacity]
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Require authentication
INFRA_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$INFRA_ROOT/lib/common.sh"
require_auth

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Load environment
if [[ -f "${ROOT_DIR}/.env" ]]; then
    source "${ROOT_DIR}/.env"
fi

CAPACITY="${1:-${GARAGE_CAPACITY:-100G}}"
ZONE="${GARAGE_ZONE:-dc1}"

# Check if garage is running
if ! docker ps --format '{{.Names}}' | grep -q "^garage$"; then
    log_error "Garage container is not running. Start it first with: docker compose up -d"
    exit 1
fi

# Get node ID
log_info "Getting node ID..."
NODE_ID=$(docker exec garage /garage status 2>/dev/null | grep -oE '[a-f0-9]{64}' | head -1)

if [[ -z "$NODE_ID" ]]; then
    log_error "Could not get node ID. Is Garage running properly?"
    exit 1
fi

log_info "Node ID: ${NODE_ID:0:16}..."

# Check current layout status
LAYOUT_STATUS=$(docker exec garage /garage layout show 2>&1 || true)

if echo "$LAYOUT_STATUS" | grep -q "No nodes"; then
    log_info "Assigning capacity to node..."
    docker exec garage /garage layout assign \
        --zone "$ZONE" \
        --capacity "$CAPACITY" \
        "$NODE_ID"

    log_info "Applying layout..."
    docker exec garage /garage layout apply --version 1

    log_info "Layout applied successfully!"
else
    log_warn "Layout already configured"
    echo ""
    docker exec garage /garage layout show
fi

echo ""
log_info "Current status:"
docker exec garage /garage status
