#!/bin/bash
# =============================================================================
# Reset Infrastructure Admin Password
# =============================================================================
# Use this if you forgot your admin password.
# Requires root/sudo access to prove server ownership.
#
# Usage:
#   sudo bash scripts/reset-password.sh
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Must run as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (sudo)"
    echo ""
    echo "Usage: sudo bash scripts/reset-password.sh"
    exit 1
fi

# Find infra directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(dirname "$SCRIPT_DIR")"
PASSWORD_FILE="$INFRA_ROOT/.password_hash"

echo ""
echo "=========================================="
echo "  Infrastructure Password Reset"
echo "=========================================="
echo ""

# Check if password file exists
if [[ -f "$PASSWORD_FILE" ]]; then
    log_warn "Current password hash will be deleted!"
    echo ""
    read -p "Are you sure you want to reset the password? (yes/no): " CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then
        log_info "Cancelled"
        exit 0
    fi

    # Backup old hash (just in case)
    cp "$PASSWORD_FILE" "$PASSWORD_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    rm "$PASSWORD_FILE"
    log_info "Old password removed"
else
    log_info "No existing password found"
fi

echo ""

# Set new password
echo "Set new admin password:"
echo ""

read -s -p "Enter new password: " PASSWORD1
echo ""
read -s -p "Confirm password: " PASSWORD2
echo ""

if [[ "$PASSWORD1" != "$PASSWORD2" ]]; then
    log_error "Passwords do not match"
    exit 1
fi

if [[ ${#PASSWORD1} -lt 8 ]]; then
    log_error "Password must be at least 8 characters"
    exit 1
fi

# Store hash
echo -n "$PASSWORD1" | sha256sum | cut -d' ' -f1 > "$PASSWORD_FILE"
chmod 600 "$PASSWORD_FILE"

# Fix ownership if needed
INFRA_OWNER=$(stat -c "%U" "$INFRA_ROOT" 2>/dev/null || stat -f "%Su" "$INFRA_ROOT")
chown "$INFRA_OWNER:$INFRA_OWNER" "$PASSWORD_FILE" 2>/dev/null || true

echo ""
log_info "Password reset successfully!"
echo ""
echo "You can now run:"
echo "  cd $INFRA_ROOT"
echo "  ./setup.sh"
echo ""
echo "=========================================="
