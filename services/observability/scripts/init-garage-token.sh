#!/bin/bash
# =============================================================================
# Initialize Garage Metrics Token
# =============================================================================
# Creates the secrets file for Garage bearer token authentication.
# Garage is the only service requiring auth for Prometheus scraping.
#
# Usage: ./scripts/init-garage-token.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_DIR="$SCRIPT_DIR/../secrets"

# Require authentication
INFRA_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$INFRA_ROOT/lib/common.sh"
require_auth

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[SKIP]${NC} $1"; }

# Load .env
ENV_FILE="$SCRIPT_DIR/../.env"
if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

# Create secrets directory
mkdir -p "$SECRETS_DIR"

echo ""
echo "Initializing Garage metrics token..."
echo ""

# Garage metrics token
if [[ -n "$GARAGE_METRICS_TOKEN" ]]; then
    echo -n "$GARAGE_METRICS_TOKEN" > "$SECRETS_DIR/garage-metrics-token"
    chmod 600 "$SECRETS_DIR/garage-metrics-token"
    log_info "Garage metrics token configured"
else
    log_warn "GARAGE_METRICS_TOKEN not set in .env (skip if not using Garage)"
fi

echo ""
echo -e "${BLUE}Done! Restart Prometheus to apply:${NC}"
echo "  docker compose restart prometheus"
echo ""
