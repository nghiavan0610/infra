#!/bin/bash

#######################################
# Remove User Script - For Dev Team Management
# Safely remove users created by add-user.sh
#
# This script will:
#   - Remove the user account and home directory
#   - Clean up SSH tunnel restrictions (if any)
#   - Remove from groups (sudo, docker, apps)
#
# Run as: sudo bash remove-user.sh
#######################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root"
   log_info "Run: sudo bash remove-user.sh"
   exit 1
fi

echo "=========================================="
echo "  Remove User - Dev Team Management"
echo "=========================================="
echo ""

#######################################
# List existing users (created by add-user.sh)
#######################################
echo -e "${CYAN}Users with login shells:${NC}"
echo ""

# Show users with UID >= 1000 (regular users, not system users)
awk -F: '$3 >= 1000 && $3 < 65534 {print "  - " $1 " (home: " $6 ")"}' /etc/passwd

echo ""

#######################################
# Get username to remove
#######################################
read -p "Enter username to remove: " USERNAME

# Validate username provided
if [[ -z "$USERNAME" ]]; then
    log_error "Username cannot be empty"
    exit 1
fi

# Check if user exists
if ! id "$USERNAME" &>/dev/null; then
    log_error "User '$USERNAME' does not exist"
    exit 1
fi

# Prevent removing critical users
PROTECTED_USERS=("root" "ubuntu" "admin" "postgres" "redis" "grafana" "prometheus")
for protected in "${PROTECTED_USERS[@]}"; do
    if [[ "$USERNAME" == "$protected" ]]; then
        log_error "Cannot remove protected system user: $USERNAME"
        exit 1
    fi
done

#######################################
# Show user information
#######################################
echo ""
echo -e "${CYAN}User Information:${NC}"
USER_HOME=$(eval echo ~$USERNAME)
echo "  - Username: $USERNAME"
echo "  - Home directory: $USER_HOME"
echo -n "  - Groups: "
groups "$USERNAME" 2>/dev/null | cut -d: -f2 || echo "(none)"

# Check if tunnel-only user
SSHD_CONFIG="/etc/ssh/sshd_config"
IS_TUNNEL_USER="n"
if grep -q "^Match User $USERNAME" "$SSHD_CONFIG" 2>/dev/null; then
    IS_TUNNEL_USER="y"
    echo -e "  - Type: ${YELLOW}Tunnel-only user${NC} (has SSH restrictions)"
else
    echo "  - Type: Regular user"
fi

echo ""

#######################################
# Confirm removal
#######################################
log_warn "This will permanently delete:"
echo "  - User account: $USERNAME"
echo "  - Home directory: $USER_HOME"
if [[ "$IS_TUNNEL_USER" == "y" ]]; then
    echo "  - SSH tunnel restrictions in sshd_config"
fi
echo ""

read -p "Are you sure you want to remove this user? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    log_info "Cancelled. No changes made."
    exit 0
fi

#######################################
# Check for running processes
#######################################
log_step "Checking for running processes..."
USER_PROCS=$(pgrep -u "$USERNAME" 2>/dev/null || true)
if [[ -n "$USER_PROCS" ]]; then
    log_warn "User has running processes:"
    ps -u "$USERNAME" -o pid,cmd --no-headers 2>/dev/null | head -5
    echo ""
    read -p "Kill all processes for $USERNAME? (y/n): " KILL_PROCS
    if [[ "$KILL_PROCS" == "y" ]]; then
        pkill -u "$USERNAME" 2>/dev/null || true
        sleep 1
        pkill -9 -u "$USERNAME" 2>/dev/null || true
        log_info "Processes terminated"
    else
        log_error "Cannot remove user with running processes"
        exit 1
    fi
else
    log_info "No running processes found"
fi

#######################################
# Remove SSH tunnel restrictions (if tunnel-only user)
#######################################
if [[ "$IS_TUNNEL_USER" == "y" ]]; then
    log_step "Removing SSH tunnel restrictions..."

    # Create backup
    cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak.$(date +%Y%m%d_%H%M%S)"

    # Remove the Match block for this user
    # The block starts with "# Tunnel-only user: $USERNAME" and ends before the next Match or end of file
    sed -i "/^# Tunnel-only user: $USERNAME/,/^Match User\|^$/{ /^Match User/!d; /^# Tunnel-only user: $USERNAME/d; }" "$SSHD_CONFIG"

    # Clean up any remaining empty lines at the end
    sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$SSHD_CONFIG" 2>/dev/null || true

    # More reliable approach: use awk to remove the block
    awk -v user="$USERNAME" '
    BEGIN { skip = 0 }
    /^# Tunnel-only user: / && $4 == user { skip = 1; next }
    /^Match User / && skip == 1 { skip = 0; next }
    skip == 1 && /^[[:space:]]/ { next }
    skip == 1 && /^[^[:space:]]/ { skip = 0 }
    { print }
    ' "${SSHD_CONFIG}.bak."* > "$SSHD_CONFIG.tmp" 2>/dev/null && mv "$SSHD_CONFIG.tmp" "$SSHD_CONFIG" || true

    log_info "SSH tunnel restrictions removed"

    # Reload SSH
    if systemctl is-active --quiet sshd; then
        systemctl reload sshd
        log_info "SSH service reloaded"
    elif systemctl is-active --quiet ssh; then
        systemctl reload ssh
        log_info "SSH service reloaded"
    fi
fi

#######################################
# Remove user from groups
#######################################
log_step "Removing from groups..."
for group in sudo wheel docker apps; do
    if getent group "$group" &>/dev/null; then
        if groups "$USERNAME" 2>/dev/null | grep -qw "$group"; then
            gpasswd -d "$USERNAME" "$group" 2>/dev/null || true
            log_info "Removed from $group group"
        fi
    fi
done

#######################################
# Delete user account
#######################################
log_step "Deleting user account..."

# Remove user and home directory
userdel -r "$USERNAME" 2>/dev/null || userdel "$USERNAME"
log_info "User account deleted"

# Clean up any remaining home directory
if [[ -d "$USER_HOME" ]]; then
    rm -rf "$USER_HOME"
    log_info "Home directory removed"
fi

#######################################
# Clean up any cron jobs
#######################################
if [[ -f "/var/spool/cron/crontabs/$USERNAME" ]]; then
    rm -f "/var/spool/cron/crontabs/$USERNAME"
    log_info "Cron jobs removed"
fi

#######################################
# Summary
#######################################
echo ""
echo "=========================================="
log_info "User Removed Successfully!"
echo "=========================================="
echo ""
echo "Removed:"
echo "  - User account: $USERNAME"
echo "  - Home directory: $USER_HOME"
if [[ "$IS_TUNNEL_USER" == "y" ]]; then
    echo "  - SSH tunnel restrictions"
fi
echo ""
