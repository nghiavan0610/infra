#!/bin/bash
# =============================================================================
# Vault Unseal Script
# =============================================================================
# Run after Vault restarts to unseal it
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Require authentication
INFRA_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$INFRA_ROOT/lib/common.sh"
require_auth

VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_ADDR

echo "Vault Unseal"
echo "============"
echo ""

# Check status
if docker exec vault vault status -address=$VAULT_ADDR 2>&1 | grep -q "Sealed.*false"; then
    echo "Vault is already unsealed"
    exit 0
fi

# Load keys if available
if [[ -f "keys.json" ]]; then
    echo "Found keys.json, auto-unsealing..."

    KEY1=$(jq -r '.unseal_keys_b64[0]' keys.json)
    KEY2=$(jq -r '.unseal_keys_b64[1]' keys.json)
    KEY3=$(jq -r '.unseal_keys_b64[2]' keys.json)

    docker exec vault vault operator unseal -address=$VAULT_ADDR "$KEY1" > /dev/null
    docker exec vault vault operator unseal -address=$VAULT_ADDR "$KEY2" > /dev/null
    docker exec vault vault operator unseal -address=$VAULT_ADDR "$KEY3" > /dev/null

    echo "Vault unsealed successfully"
else
    echo "No keys.json found. Enter unseal keys manually:"
    echo ""
    docker exec -it vault vault operator unseal -address=$VAULT_ADDR
    docker exec -it vault vault operator unseal -address=$VAULT_ADDR
    docker exec -it vault vault operator unseal -address=$VAULT_ADDR
fi
