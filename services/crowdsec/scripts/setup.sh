#!/bin/bash
# =============================================================================
# Crowdsec Setup Script
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo ""
echo "=============================================="
echo "  Crowdsec - Setup"
echo "=============================================="
echo ""

# Step 1: Create .env if not exists
if [[ ! -f ".env" ]]; then
    log_info "Creating .env from template..."
    cp .env.example .env

    # Generate bouncer key
    BOUNCER_KEY=$(openssl rand -base64 32 | tr -d '\n')

    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|^BOUNCER_KEY_TRAEFIK=.*|BOUNCER_KEY_TRAEFIK=${BOUNCER_KEY}|" .env
    else
        sed -i "s|^BOUNCER_KEY_TRAEFIK=.*|BOUNCER_KEY_TRAEFIK=${BOUNCER_KEY}|" .env
    fi

    log_info "Generated bouncer key"
else
    log_info ".env already exists, skipping..."
fi

# Step 2: Create directories
log_info "Creating directories..."
mkdir -p config data

# Step 3: Start Crowdsec
log_info "Starting Crowdsec..."
docker compose up -d crowdsec

# Step 4: Wait for Crowdsec to be ready
log_info "Waiting for Crowdsec to start..."
sleep 5

for i in {1..30}; do
    if docker exec crowdsec cscli version &>/dev/null; then
        break
    fi
    sleep 1
done

# Step 5: Register bouncer
log_info "Registering Traefik bouncer..."

# Load bouncer key from .env
source .env

# Add bouncer if not exists
if ! docker exec crowdsec cscli bouncers list 2>/dev/null | grep -q "traefik-bouncer"; then
    docker exec crowdsec cscli bouncers add traefik-bouncer -k "$BOUNCER_KEY_TRAEFIK" 2>/dev/null || true
    log_info "Traefik bouncer registered"
else
    log_info "Traefik bouncer already registered"
fi

# Step 6: Start bouncer
log_info "Starting Traefik bouncer..."
docker compose up -d traefik-bouncer

echo ""
echo "=============================================="
echo -e "  ${GREEN}Setup Complete!${NC}"
echo "=============================================="
echo ""
echo "Crowdsec is running."
echo ""
echo "Next steps:"
echo "  1. Update Traefik to use the bouncer (see README)"
echo "  2. Check status: docker exec crowdsec cscli metrics"
echo ""
