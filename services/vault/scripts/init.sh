#!/bin/bash
# =============================================================================
# Vault Initialization Script
# =============================================================================
# Run this ONCE after first start to initialize Vault
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_ADDR

echo ""
echo "=============================================="
echo "  Vault Initialization"
echo "=============================================="
echo ""

# Check if Vault is running
if ! docker exec vault vault status -address=$VAULT_ADDR 2>&1 | grep -q "Initialized"; then
    log_error "Vault is not running. Start it first: docker compose up -d"
    exit 1
fi

# Check if already initialized
if docker exec vault vault status -address=$VAULT_ADDR 2>&1 | grep -q "Initialized.*true"; then
    log_warn "Vault is already initialized"
    echo ""
    echo "If you need to unseal, run:"
    echo "  docker exec -it vault vault operator unseal"
    exit 0
fi

# Initialize Vault
log_info "Initializing Vault..."
INIT_OUTPUT=$(docker exec vault vault operator init -address=$VAULT_ADDR -key-shares=5 -key-threshold=3 -format=json)

# Save keys securely
echo "$INIT_OUTPUT" > keys.json
chmod 600 keys.json

# Extract root token and unseal keys
ROOT_TOKEN=$(echo "$INIT_OUTPUT" | jq -r '.root_token')
UNSEAL_KEY_1=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[0]')
UNSEAL_KEY_2=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[1]')
UNSEAL_KEY_3=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[2]')

log_info "Vault initialized. Unsealing..."

# Unseal Vault
docker exec vault vault operator unseal -address=$VAULT_ADDR "$UNSEAL_KEY_1" > /dev/null
docker exec vault vault operator unseal -address=$VAULT_ADDR "$UNSEAL_KEY_2" > /dev/null
docker exec vault vault operator unseal -address=$VAULT_ADDR "$UNSEAL_KEY_3" > /dev/null

log_info "Vault unsealed"

# Enable KV secrets engine
log_info "Enabling KV secrets engine..."
docker exec -e VAULT_TOKEN=$ROOT_TOKEN vault vault secrets enable -address=$VAULT_ADDR -path=secret kv-v2 2>/dev/null || true

# Create admin policy
log_info "Creating policies..."
docker exec -e VAULT_TOKEN=$ROOT_TOKEN vault vault policy write -address=$VAULT_ADDR admin /vault/policies/admin.hcl
docker exec -e VAULT_TOKEN=$ROOT_TOKEN vault vault policy write -address=$VAULT_ADDR app-read /vault/policies/app-read.hcl

echo ""
echo "=============================================="
echo -e "  ${GREEN}Initialization Complete!${NC}"
echo "=============================================="
echo ""
echo -e "${RED}IMPORTANT: Save these credentials securely!${NC}"
echo ""
echo "Root Token: $ROOT_TOKEN"
echo ""
echo "Unseal Keys (need 3 of 5 to unseal):"
echo "  Key 1: $UNSEAL_KEY_1"
echo "  Key 2: $UNSEAL_KEY_2"
echo "  Key 3: $UNSEAL_KEY_3"
echo "  (All 5 keys saved in keys.json)"
echo ""
echo "Access UI: http://localhost:8200"
echo ""
log_warn "Store unseal keys in DIFFERENT secure locations!"
log_warn "If you lose 3+ keys, your data is UNRECOVERABLE!"
echo ""
