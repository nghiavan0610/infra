#!/bin/bash
# =============================================================================
# Garage Initialization Script
# =============================================================================
# Generates garage.toml from template and environment variables
# Usage: ./scripts/init.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Load environment
if [[ -f "${ROOT_DIR}/.env" ]]; then
    set -a
    source "${ROOT_DIR}/.env"
    set +a
else
    log_error ".env file not found. Copy from .env.example first."
    exit 1
fi

# Create directories
log_info "Creating directories..."
mkdir -p "${ROOT_DIR}/config"
mkdir -p "${ROOT_DIR}/data"
mkdir -p "${ROOT_DIR}/meta"

# Generate secrets if not set
if [[ -z "$GARAGE_RPC_SECRET" || "$GARAGE_RPC_SECRET" == "change-me"* ]]; then
    log_info "Generating RPC secret..."
    GARAGE_RPC_SECRET=$(openssl rand -hex 32)

    # Update .env file
    if grep -q "^GARAGE_RPC_SECRET=" "${ROOT_DIR}/.env"; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|^GARAGE_RPC_SECRET=.*|GARAGE_RPC_SECRET=${GARAGE_RPC_SECRET}|" "${ROOT_DIR}/.env"
        else
            sed -i "s|^GARAGE_RPC_SECRET=.*|GARAGE_RPC_SECRET=${GARAGE_RPC_SECRET}|" "${ROOT_DIR}/.env"
        fi
    fi
    log_warn "Generated new RPC secret - save this!"
fi

if [[ -z "$GARAGE_ADMIN_TOKEN" || "$GARAGE_ADMIN_TOKEN" == "change-me"* ]]; then
    log_info "Generating Admin token..."
    GARAGE_ADMIN_TOKEN=$(openssl rand -base64 32)

    if grep -q "^GARAGE_ADMIN_TOKEN=" "${ROOT_DIR}/.env"; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|^GARAGE_ADMIN_TOKEN=.*|GARAGE_ADMIN_TOKEN=${GARAGE_ADMIN_TOKEN}|" "${ROOT_DIR}/.env"
        else
            sed -i "s|^GARAGE_ADMIN_TOKEN=.*|GARAGE_ADMIN_TOKEN=${GARAGE_ADMIN_TOKEN}|" "${ROOT_DIR}/.env"
        fi
    fi
    log_warn "Generated new Admin token - save this!"
fi

if [[ -z "$GARAGE_METRICS_TOKEN" || "$GARAGE_METRICS_TOKEN" == "change-me"* ]]; then
    GARAGE_METRICS_TOKEN="$GARAGE_ADMIN_TOKEN"

    if grep -q "^GARAGE_METRICS_TOKEN=" "${ROOT_DIR}/.env"; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|^GARAGE_METRICS_TOKEN=.*|GARAGE_METRICS_TOKEN=${GARAGE_METRICS_TOKEN}|" "${ROOT_DIR}/.env"
        else
            sed -i "s|^GARAGE_METRICS_TOKEN=.*|GARAGE_METRICS_TOKEN=${GARAGE_METRICS_TOKEN}|" "${ROOT_DIR}/.env"
        fi
    fi
fi

# Generate garage.toml from template
log_info "Generating garage.toml..."

TEMPLATE="${ROOT_DIR}/config/garage.toml.template"
OUTPUT="${ROOT_DIR}/config/garage.toml"

if [[ ! -f "$TEMPLATE" ]]; then
    log_error "Template not found: $TEMPLATE"
    exit 1
fi

# Use envsubst if available, otherwise use sed
if command -v envsubst &>/dev/null; then
    envsubst < "$TEMPLATE" > "$OUTPUT"
else
    # Manual substitution
    cp "$TEMPLATE" "$OUTPUT"

    sed -i.bak \
        -e "s|\${GARAGE_REPLICATION_FACTOR:-1}|${GARAGE_REPLICATION_FACTOR:-1}|g" \
        -e "s|\${GARAGE_BLOCK_SIZE:-1048576}|${GARAGE_BLOCK_SIZE:-1048576}|g" \
        -e "s|\${GARAGE_COMPRESSION_LEVEL:-1}|${GARAGE_COMPRESSION_LEVEL:-1}|g" \
        -e "s|\${GARAGE_SLED_CACHE_CAPACITY:-134217728}|${GARAGE_SLED_CACHE_CAPACITY:-134217728}|g" \
        -e "s|\${GARAGE_RPC_PUBLIC_ADDR:-127.0.0.1:3901}|${GARAGE_RPC_PUBLIC_ADDR:-garage:3901}|g" \
        -e "s|\${GARAGE_RPC_SECRET}|${GARAGE_RPC_SECRET}|g" \
        -e "s|\${GARAGE_S3_REGION:-garage}|${GARAGE_S3_REGION:-garage}|g" \
        -e "s|\${GARAGE_S3_ROOT_DOMAIN:-.s3.garage.localhost}|${GARAGE_S3_ROOT_DOMAIN:-.s3.garage.localhost}|g" \
        -e "s|\${GARAGE_WEB_ROOT_DOMAIN:-.web.garage.localhost}|${GARAGE_WEB_ROOT_DOMAIN:-.web.garage.localhost}|g" \
        -e "s|\${GARAGE_ADMIN_TOKEN}|${GARAGE_ADMIN_TOKEN}|g" \
        -e "s|\${GARAGE_METRICS_TOKEN:-\${GARAGE_ADMIN_TOKEN}}|${GARAGE_METRICS_TOKEN:-$GARAGE_ADMIN_TOKEN}|g" \
        "$OUTPUT"

    rm -f "${OUTPUT}.bak"
fi

log_info "Generated: $OUTPUT"

echo ""
log_info "Initialization complete!"
echo ""
echo "Next steps:"
echo "  1. Start Garage:     docker compose up -d"
echo "  2. Check status:     docker exec garage /garage status"
echo "  3. Setup layout:     ./scripts/setup-layout.sh"
echo "  4. Create bucket:    ./scripts/manage.sh bucket create <name>"
echo ""
