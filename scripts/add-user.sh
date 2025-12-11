#!/bin/bash

#######################################
# Add User Script - For Dev Team Management
# Quickly add new users with SSH key authentication
#
# User Types:
#   - Developer: SSH access only (no sudo, no docker)
#   - DevOps: SSH + sudo (can manage system, but NOT docker)
#   - Infra Admin: SSH + sudo + docker (full infrastructure access)
#
# Run as: sudo bash add-user.sh
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
   log_info "Run: sudo bash add-user.sh"
   exit 1
fi

echo "=========================================="
echo "  Add New User - Dev Team Management"
echo "=========================================="
echo ""

#######################################
# Show user type options
#######################################
echo -e "${CYAN}User Types:${NC}"
echo "  1) Developer   - SSH access only (application deployment)"
echo "  2) DevOps      - SSH + sudo (system management, NO docker)"
echo "  3) Infra Admin - SSH + sudo + docker (full infrastructure control)"
echo ""
read -p "Select user type [1-3]: " USER_TYPE

case "$USER_TYPE" in
    1)
        GRANT_SUDO="n"
        GRANT_DOCKER="n"
        USER_TYPE_NAME="Developer"
        ;;
    2)
        GRANT_SUDO="y"
        GRANT_DOCKER="n"
        USER_TYPE_NAME="DevOps"
        ;;
    3)
        GRANT_SUDO="y"
        GRANT_DOCKER="y"
        USER_TYPE_NAME="Infra Admin"
        echo ""
        log_warn "INFRA ADMIN WARNING:"
        echo "  This user will have FULL control over Docker containers."
        echo "  They can start/stop/remove ANY container, including databases."
        echo "  Only grant this to trusted infrastructure administrators!"
        echo ""
        read -p "Are you sure you want to create an Infra Admin? (yes/no): " CONFIRM
        if [[ "$CONFIRM" != "yes" ]]; then
            log_info "Cancelled. Use type 2 (DevOps) for system admins without Docker access."
            exit 0
        fi
        ;;
    *)
        log_error "Invalid option. Choose 1, 2, or 3"
        exit 1
        ;;
esac

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
    read -p "Do you want to update this user's permissions and SSH key? (y/n): " UPDATE_USER
    if [[ "$UPDATE_USER" != "y" ]]; then
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
# Handle group memberships
#######################################
USER_HOME=$(eval echo ~$USERNAME)

# Sudo access
if [[ "$GRANT_SUDO" == "y" ]]; then
    log_step "Granting sudo privileges to $USERNAME"
    usermod -aG sudo "$USERNAME" 2>/dev/null || usermod -aG wheel "$USERNAME"
    log_info "Sudo privileges granted"
else
    # Remove from sudo group if exists (for updates)
    if [[ "$USER_EXISTS" == "true" ]]; then
        gpasswd -d "$USERNAME" sudo 2>/dev/null || gpasswd -d "$USERNAME" wheel 2>/dev/null || true
        log_info "Sudo privileges removed"
    fi
fi

# Docker access
if [[ "$GRANT_DOCKER" == "y" ]]; then
    if getent group docker &>/dev/null; then
        log_step "Granting Docker access to $USERNAME"
        usermod -aG docker "$USERNAME"
        log_info "Docker access granted"
    else
        log_warn "Docker group does not exist. Install Docker first."
    fi
else
    # Remove from docker group if exists (for updates)
    if [[ "$USER_EXISTS" == "true" ]] && getent group docker &>/dev/null; then
        if groups "$USERNAME" | grep -q docker; then
            gpasswd -d "$USERNAME" docker 2>/dev/null || true
            log_info "Docker access removed"
        fi
    fi
fi

#######################################
# Setup SSH key authentication
#######################################
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
    log_step "Setting up SSH key authentication"

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
echo "  - Type: $USER_TYPE_NAME"
echo "  - Home directory: $USER_HOME"
echo ""
echo "Permissions:"
if [[ "$GRANT_SUDO" == "y" ]]; then
    echo -e "  - Sudo access: ${GREEN}YES${NC}"
else
    echo -e "  - Sudo access: ${YELLOW}NO${NC}"
fi
if [[ "$GRANT_DOCKER" == "y" ]]; then
    echo -e "  - Docker access: ${GREEN}YES${NC} (can manage all containers)"
else
    echo -e "  - Docker access: ${YELLOW}NO${NC} (cannot control infrastructure)"
fi
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
    echo -e "  - SSH key: ${GREEN}CONFIGURED${NC}"
else
    echo -e "  - SSH key: ${YELLOW}NOT SET${NC} (password auth only)"
fi

echo ""

# Show connection command
SSH_PORT=$(grep -E "^Port " /etc/ssh/sshd_config.d/hardening.conf 2>/dev/null | awk '{print $2}' || echo "22")
HOSTNAME=$(hostname -I | awk '{print $1}')

log_info "User can now connect with:"
echo "  ssh -p $SSH_PORT $USERNAME@$HOSTNAME"
echo ""

# Show what user CAN and CANNOT do
echo -e "${CYAN}What $USERNAME can do:${NC}"
echo "  - SSH into the server"
if [[ "$GRANT_SUDO" == "y" ]]; then
    echo "  - Run system commands with sudo"
    echo "  - Manage system packages, services, firewall"
fi
if [[ "$GRANT_DOCKER" == "y" ]]; then
    echo "  - Start/stop/remove Docker containers"
    echo "  - Access all infrastructure services"
    echo "  - Run management scripts in /opt/infra"
fi

echo ""
echo -e "${CYAN}What $USERNAME CANNOT do:${NC}"
if [[ "$GRANT_DOCKER" != "y" ]]; then
    echo "  - Control Docker containers (docker ps, docker stop, etc.)"
    echo "  - Access infrastructure management scripts"
fi
if [[ "$GRANT_SUDO" != "y" ]]; then
    echo "  - Run commands as root"
    echo "  - Install system packages"
    echo "  - Modify system configuration"
fi

echo ""
echo "=========================================="
