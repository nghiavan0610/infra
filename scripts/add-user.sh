#!/bin/bash

#######################################
# Add User Script - For Dev Team Management
# Quickly add new users with SSH key authentication
# Run as: sudo bash add-user.sh
#######################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root"
   log_info "Run: sudo bash add-user.sh"
   exit 1
fi

echo "=========================================="
echo "  Add New User - Dev Team Management"
echo "=========================================="
echo ""

#######################################
# Get user information
#######################################
read -p "Enter username for new team member: " USERNAME

# Validate username
if [[ ! "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    log_error "Invalid username. Use only lowercase letters, numbers, underscore, and hyphen"
    exit 1
fi

# Check if user already exists
if id "$USERNAME" &>/dev/null; then
    log_error "User $USERNAME already exists!"
    read -p "Do you want to update this user's SSH key? (y/n): " UPDATE_KEY
    if [[ "$UPDATE_KEY" != "y" ]]; then
        log_info "Exiting without changes"
        exit 0
    fi
    USER_EXISTS=true
else
    USER_EXISTS=false
fi

# Get password (only for new users)
if [[ "$USER_EXISTS" == "false" ]]; then
    read -s -p "Enter password for $USERNAME: " PASSWORD
    echo ""
    read -s -p "Confirm password: " PASSWORD_CONFIRM
    echo ""

    if [[ "$PASSWORD" != "$PASSWORD_CONFIRM" ]]; then
        log_error "Passwords do not match"
        exit 1
    fi
fi

# Ask about sudo access
read -p "Grant sudo privileges to $USERNAME? (y/n): " GRANT_SUDO
GRANT_SUDO=${GRANT_SUDO,,}  # Convert to lowercase

# Get SSH public key
echo ""
log_info "Please provide SSH public key for $USERNAME"
echo "Paste the SSH public key (press Enter when done):"
read SSH_PUBLIC_KEY

if [[ -z "$SSH_PUBLIC_KEY" ]]; then
    log_warn "No SSH key provided!"
    read -p "Continue without SSH key? User will need password auth. (y/n): " CONTINUE
    if [[ "$CONTINUE" != "y" ]]; then
        log_info "Exiting without changes"
        exit 1
    fi
fi

#######################################
# Create or update user
#######################################
if [[ "$USER_EXISTS" == "false" ]]; then
    log_step "Creating user: $USERNAME"
    useradd -m -s /bin/bash "$USERNAME"
    echo "$USERNAME:$PASSWORD" | chpasswd
    log_info "User $USERNAME created"
else
    log_step "Updating existing user: $USERNAME"
fi

#######################################
# Grant sudo access
#######################################
if [[ "$GRANT_SUDO" == "y" ]]; then
    log_step "Granting sudo privileges to $USERNAME"
    usermod -aG sudo "$USERNAME" 2>/dev/null || usermod -aG wheel "$USERNAME"
    log_info "Sudo privileges granted"
fi

#######################################
# Setup SSH key authentication
#######################################
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
    log_step "Setting up SSH key authentication"

    USER_HOME=$(eval echo ~$USERNAME)
    mkdir -p "$USER_HOME/.ssh"

    # If updating existing user, append to authorized_keys
    if [[ "$USER_EXISTS" == "true" ]]; then
        # Check if key already exists
        if grep -q "$SSH_PUBLIC_KEY" "$USER_HOME/.ssh/authorized_keys" 2>/dev/null; then
            log_warn "SSH key already exists for this user"
        else
            echo "$SSH_PUBLIC_KEY" >> "$USER_HOME/.ssh/authorized_keys"
            log_info "SSH key added to existing authorized_keys"
        fi
    else
        # New user - create new authorized_keys
        echo "$SSH_PUBLIC_KEY" > "$USER_HOME/.ssh/authorized_keys"
        log_info "SSH key configured"
    fi

    # Set correct permissions
    chmod 700 "$USER_HOME/.ssh"
    chmod 600 "$USER_HOME/.ssh/authorized_keys"
    chown -R "$USERNAME:$USERNAME" "$USER_HOME/.ssh"
fi

#######################################
# Display summary
#######################################
echo ""
echo "=========================================="
log_info "User Setup Complete!"
echo "=========================================="
echo ""
echo "User Information:"
echo "  - Username: $USERNAME"
echo "  - Home directory: $(eval echo ~$USERNAME)"
if [[ "$GRANT_SUDO" == "y" ]]; then
    echo "  - Sudo access: YES"
else
    echo "  - Sudo access: NO"
fi
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
    echo "  - SSH key: CONFIGURED"
else
    echo "  - SSH key: NOT SET (password auth only)"
fi
echo ""

# Show connection command
SSH_PORT=$(grep -E "^Port " /etc/ssh/sshd_config.d/hardening.conf 2>/dev/null | awk '{print $2}' || echo "22")
HOSTNAME=$(hostname -I | awk '{print $1}')

log_info "User can now connect with:"
echo "  ssh -p $SSH_PORT $USERNAME@$HOSTNAME"
echo ""

if [[ "$GRANT_SUDO" == "y" ]]; then
    log_info "To use sudo:"
    echo "  sudo whoami"
fi

echo "=========================================="
