#!/bin/bash
# =============================================================================
# Docker Registry Setup Script
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Require authentication
INFRA_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$INFRA_ROOT/lib/common.sh"
require_auth

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo ""
echo "=============================================="
echo "  Docker Registry - Setup"
echo "=============================================="
echo ""

# Step 1: Create .env if not exists
if [[ ! -f ".env" ]]; then
    log_info "Creating .env from template..."
    cp .env.example .env

    # Generate password
    PASSWORD=$(openssl rand -base64 16 | tr -d '\n' | head -c 16)

    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|^REGISTRY_PASSWORD=.*|REGISTRY_PASSWORD=${PASSWORD}|" .env
    else
        sed -i "s|^REGISTRY_PASSWORD=.*|REGISTRY_PASSWORD=${PASSWORD}|" .env
    fi

    log_warn "Generated password: ${PASSWORD}"
else
    log_info ".env already exists, skipping..."
fi

# Load env
source .env

# Step 2: Create directories
log_info "Creating directories..."
mkdir -p data auth certs

# Step 3: Create htpasswd file
log_info "Creating authentication file..."

if command -v htpasswd &> /dev/null; then
    htpasswd -Bn "${REGISTRY_USER:-admin}" <<< "${REGISTRY_PASSWORD}" > auth/htpasswd
elif command -v docker &> /dev/null; then
    docker run --rm --entrypoint htpasswd httpd:2 -Bn "${REGISTRY_USER:-admin}" <<< "${REGISTRY_PASSWORD}" > auth/htpasswd
else
    log_warn "htpasswd not found. Install apache2-utils or use Docker."
    exit 1
fi

# Step 4: Start registry
log_info "Starting Docker Registry..."
docker compose up -d registry

echo ""
echo "=============================================="
echo -e "  ${GREEN}Setup Complete!${NC}"
echo "=============================================="
echo ""
echo "Registry is running at: localhost:${REGISTRY_PORT:-5000}"
echo ""
echo "Login credentials:"
echo "  Username: ${REGISTRY_USER:-admin}"
echo "  Password: (check .env for REGISTRY_PASSWORD)"
echo ""
echo "Usage:"
echo "  # Login"
echo "  docker login localhost:${REGISTRY_PORT:-5000}"
echo ""
echo "  # Tag and push"
echo "  docker tag myapp localhost:${REGISTRY_PORT:-5000}/myapp:v1"
echo "  docker push localhost:${REGISTRY_PORT:-5000}/myapp:v1"
echo ""
echo "Optional - Start Web UI:"
echo "  docker compose --profile ui up -d"
echo "  http://localhost:${REGISTRY_UI_PORT:-5001}"
echo ""
