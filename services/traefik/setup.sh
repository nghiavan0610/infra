#!/bin/bash
# =============================================================================
# Traefik Setup Script
# =============================================================================
# Usage: ./setup.sh
# =============================================================================

set -e

# Require authentication
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$INFRA_ROOT/lib/common.sh"
require_auth

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Header
echo ""
echo "=============================================="
echo "  Traefik Reverse Proxy Setup"
echo "=============================================="
echo ""

# Check Docker
if ! command -v docker &> /dev/null; then
    error "Docker is not installed. Please install Docker first."
fi

# Check Docker Compose
if ! docker compose version &> /dev/null; then
    error "Docker Compose is not available. Please install Docker Compose V2."
fi

# Create network if not exists
info "Creating traefik-public network..."
if docker network ls | grep -q traefik-public; then
    warn "Network 'traefik-public' already exists, skipping..."
else
    docker network create traefik-public
    success "Network 'traefik-public' created"
fi

# Create .env if not exists
if [ ! -f .env ]; then
    info "Creating .env from .env.example..."
    cp .env.example .env
    success ".env file created"
    warn "Please edit .env with your configuration!"
else
    warn ".env already exists, skipping..."
fi

# Create acme.json with proper permissions
info "Setting up certificate storage..."
if [ ! -f certs/acme.json ]; then
    touch certs/acme.json
    chmod 600 certs/acme.json
    success "certs/acme.json created with correct permissions"
else
    # Ensure correct permissions
    chmod 600 certs/acme.json
    warn "certs/acme.json already exists, permissions verified"
fi

# Generate password hash
echo ""
echo "=============================================="
echo "  Dashboard Password Setup"
echo "=============================================="
echo ""

if command -v htpasswd &> /dev/null; then
    read -p "Enter dashboard username [admin]: " DASHBOARD_USER
    DASHBOARD_USER=${DASHBOARD_USER:-admin}

    read -s -p "Enter dashboard password: " DASHBOARD_PASS
    echo ""

    if [ -n "$DASHBOARD_PASS" ]; then
        # Generate hash
        HASH=$(htpasswd -nbB "$DASHBOARD_USER" "$DASHBOARD_PASS" | sed 's/\$/\$\$/g')

        # Update .env
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|TRAEFIK_DASHBOARD_AUTH=.*|TRAEFIK_DASHBOARD_AUTH=$HASH|" .env
        else
            sed -i "s|TRAEFIK_DASHBOARD_AUTH=.*|TRAEFIK_DASHBOARD_AUTH=$HASH|" .env
        fi

        success "Dashboard password hash generated and saved to .env"
    else
        warn "No password entered, using default (CHANGE THIS!)"
    fi
else
    warn "htpasswd not found. Install apache2-utils (Debian) or httpd-tools (RHEL)"
    warn "Generate password manually: htpasswd -nB admin"
    warn "Then update TRAEFIK_DASHBOARD_AUTH in .env (escape \$ with \$\$)"
fi

echo ""
echo "=============================================="
echo "  Configuration Required"
echo "=============================================="
echo ""
echo "Edit .env and configure:"
echo "  1. ACME_EMAIL - Your email for Let's Encrypt"
echo "  2. TRAEFIK_DASHBOARD_HOST - Dashboard domain"
echo "  3. DNS provider credentials (for wildcard certs)"
echo ""

read -p "Edit .env now? [Y/n]: " EDIT_ENV
EDIT_ENV=${EDIT_ENV:-Y}

if [[ "$EDIT_ENV" =~ ^[Yy]$ ]]; then
    if command -v nano &> /dev/null; then
        nano .env
    elif command -v vim &> /dev/null; then
        vim .env
    else
        warn "No editor found. Please edit .env manually."
    fi
fi

echo ""
echo "=============================================="
echo "  Ready to Start"
echo "=============================================="
echo ""

read -p "Start Traefik now? [Y/n]: " START_NOW
START_NOW=${START_NOW:-Y}

if [[ "$START_NOW" =~ ^[Yy]$ ]]; then
    info "Starting Traefik..."
    docker compose up -d

    echo ""
    success "Traefik is starting!"
    echo ""
    echo "Check status:  docker compose ps"
    echo "View logs:     docker compose logs -f"
    echo ""
    echo "Dashboard:     https://\$(grep TRAEFIK_DASHBOARD_HOST .env | cut -d= -f2)"
    echo ""
else
    echo ""
    info "To start Traefik later, run:"
    echo "  docker compose up -d"
    echo ""
fi
