#!/bin/bash
# =============================================================================
# Authentik Setup Script
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo ""
echo "=============================================="
echo "  Authentik - Identity Provider Setup"
echo "=============================================="
echo ""

# Step 1: Create .env if not exists
if [[ ! -f ".env" ]]; then
    log_info "Creating .env from template..."
    cp .env.example .env

    # Generate secrets
    log_info "Generating secrets..."

    SECRET_KEY=$(openssl rand -base64 60 | tr -d '\n')
    DB_PASSWORD=$(openssl rand -base64 24 | tr -d '\n')
    BOOTSTRAP_PASS=$(openssl rand -base64 16 | tr -d '\n' | head -c 16)

    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|^AUTHENTIK_SECRET_KEY=.*|AUTHENTIK_SECRET_KEY=${SECRET_KEY}|" .env
        sed -i '' "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${DB_PASSWORD}|" .env
        sed -i '' "s|^AUTHENTIK_BOOTSTRAP_PASSWORD=.*|AUTHENTIK_BOOTSTRAP_PASSWORD=${BOOTSTRAP_PASS}|" .env
    else
        sed -i "s|^AUTHENTIK_SECRET_KEY=.*|AUTHENTIK_SECRET_KEY=${SECRET_KEY}|" .env
        sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${DB_PASSWORD}|" .env
        sed -i "s|^AUTHENTIK_BOOTSTRAP_PASSWORD=.*|AUTHENTIK_BOOTSTRAP_PASSWORD=${BOOTSTRAP_PASS}|" .env
    fi

    log_warn "Bootstrap password: ${BOOTSTRAP_PASS}"
    log_warn "Save this password! You'll need it for first login."
else
    log_info ".env already exists, skipping..."
fi

# Step 2: Create directories
log_info "Creating directories..."
mkdir -p data/postgres data/redis media templates certs

# Step 3: Start services
log_info "Starting Authentik..."
docker compose up -d

echo ""
echo "=============================================="
echo -e "  ${GREEN}Setup Complete!${NC}"
echo "=============================================="
echo ""
echo "Authentik is starting up (may take 1-2 minutes)..."
echo ""
echo "Access at: http://localhost:${AUTHENTIK_HTTP_PORT:-9000}"
echo ""
echo "First login:"
echo "  Username: akadmin"
echo "  Password: (check .env for AUTHENTIK_BOOTSTRAP_PASSWORD)"
echo ""
echo "Next steps:"
echo "  1. Change admin password"
echo "  2. Configure domain in .env (AUTHENTIK_DOMAIN)"
echo "  3. Setup Traefik integration (see README)"
echo ""
