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
echo "  4) Tunnel Only - SSH tunnel only (access DB/Redis from local, no shell)"
echo "  5) CI Runner   - Docker + apps access (for gitlab-runner service, no SSH)"
echo ""
read -p "Select user type [1-5]: " USER_TYPE

case "$USER_TYPE" in
    1)
        GRANT_SUDO="n"
        GRANT_DOCKER="n"
        TUNNEL_ONLY="n"
        CI_RUNNER="n"
        USER_TYPE_NAME="Developer"
        ;;
    2)
        GRANT_SUDO="y"
        GRANT_DOCKER="n"
        TUNNEL_ONLY="n"
        CI_RUNNER="n"
        USER_TYPE_NAME="DevOps"
        ;;
    3)
        GRANT_SUDO="y"
        GRANT_DOCKER="y"
        TUNNEL_ONLY="n"
        CI_RUNNER="n"
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
    4)
        GRANT_SUDO="n"
        GRANT_DOCKER="n"
        TUNNEL_ONLY="y"
        CI_RUNNER="n"
        USER_TYPE_NAME="Tunnel Only"
        echo ""
        log_info "TUNNEL ONLY USER:"
        echo "  This user can ONLY create SSH tunnels to access services."
        echo "  They cannot execute any commands on the server."
        echo "  Perfect for dev partners who need DB/Redis access from local."
        echo ""
        ;;
    5)
        GRANT_SUDO="n"
        GRANT_DOCKER="y"
        TUNNEL_ONLY="n"
        CI_RUNNER="y"
        USER_TYPE_NAME="CI Runner"
        echo ""
        log_info "CI RUNNER USER:"
        echo "  This is a service account for CI/CD runners (e.g., gitlab-runner)."
        echo "  It has Docker + apps group access but NO sudo and NO SSH access."
        echo "  Use this after installing gitlab-runner from official docs."
        echo ""
        ;;
    *)
        log_error "Invalid option. Choose 1, 2, 3, 4, or 5"
        exit 1
        ;;
esac

echo ""

#######################################
# Get user information
#######################################
if [[ "$CI_RUNNER" == "y" ]]; then
    read -p "Enter username for CI runner [gitlab-runner]: " USERNAME
    USERNAME="${USERNAME:-gitlab-runner}"
else
    read -p "Enter username for new team member: " USERNAME
fi

# Validate username
if [[ ! "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    log_error "Invalid username. Use only lowercase letters, numbers, underscore, and hyphen"
    exit 1
fi

# Check if user already exists
if id "$USERNAME" &>/dev/null; then
    if [[ "$CI_RUNNER" == "y" ]]; then
        log_warn "User $USERNAME already exists"
        read -p "Do you want to update this user's group permissions? (y/n): " UPDATE_USER
    else
        log_error "User $USERNAME already exists!"
        read -p "Do you want to update this user's permissions and SSH key? (y/n): " UPDATE_USER
    fi
    if [[ "$UPDATE_USER" != "y" ]]; then
        log_info "Exiting without changes"
        exit 0
    fi
    USER_EXISTS=true
else
    USER_EXISTS=false
fi

# Get password (only for new users, skip for tunnel-only and CI runner)
if [[ "$USER_EXISTS" == "false" ]] && [[ "$TUNNEL_ONLY" != "y" ]] && [[ "$CI_RUNNER" != "y" ]]; then
    read -s -p "Enter password for $USERNAME: " PASSWORD
    echo ""
    read -s -p "Confirm password: " PASSWORD_CONFIRM
    echo ""

    if [[ "$PASSWORD" != "$PASSWORD_CONFIRM" ]]; then
        log_error "Passwords do not match"
        exit 1
    fi
fi

# Get SSH public key (skip for CI runner - service account)
if [[ "$CI_RUNNER" != "y" ]]; then
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
else
    SSH_PUBLIC_KEY=""
fi

#######################################
# Create or update user
#######################################
if [[ "$USER_EXISTS" == "false" ]]; then
    log_step "Creating user: $USERNAME"
    if [[ "$TUNNEL_ONLY" == "y" ]]; then
        # Tunnel-only user gets nologin shell
        useradd -m -s /usr/sbin/nologin "$USERNAME"
        log_info "User $USERNAME created (tunnel-only, no shell)"
    elif [[ "$CI_RUNNER" == "y" ]]; then
        # CI runner needs shell but no password (service account)
        useradd -m -s /bin/bash "$USERNAME"
        passwd -l "$USERNAME"  # Lock password (no login via password)
        log_info "User $USERNAME created (CI runner service account, password locked)"
    else
        useradd -m -s /bin/bash "$USERNAME"
        echo "$USERNAME:$PASSWORD" | chpasswd
        log_info "User $USERNAME created"
    fi
else
    log_step "Updating existing user: $USERNAME"
    if [[ "$TUNNEL_ONLY" == "y" ]]; then
        usermod -s /usr/sbin/nologin "$USERNAME"
        log_info "Shell changed to nologin (tunnel-only)"
    elif [[ "$CI_RUNNER" == "y" ]]; then
        usermod -s /bin/bash "$USERNAME"
        log_info "Shell set to /bin/bash for CI runner"
    fi
fi

#######################################
# Handle group memberships
#######################################
USER_HOME=$(eval echo ~$USERNAME)

# Create apps group if it doesn't exist (for app directory access)
if ! getent group apps &>/dev/null; then
    groupadd apps
    log_info "Created 'apps' group for application directory access"
fi

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

# Docker access (Infra Admin only)
if [[ "$GRANT_DOCKER" == "y" ]]; then
    if getent group docker &>/dev/null; then
        log_step "Granting Docker access to $USERNAME"
        usermod -aG docker "$USERNAME"
        log_info "Docker access granted"
    else
        log_warn "Docker group does not exist. Install Docker first."
    fi

    # Infra Admin always gets apps group access
    usermod -aG apps "$USERNAME"
    log_info "Apps group access granted"
else
    # Remove from docker group if exists (for updates)
    if [[ "$USER_EXISTS" == "true" ]] && getent group docker &>/dev/null; then
        if groups "$USERNAME" | grep -q docker; then
            gpasswd -d "$USERNAME" docker 2>/dev/null || true
            log_info "Docker access removed"
        fi
    fi
fi

# Apps group access for DevOps (optional - can read app configs without sudo)
if [[ "$GRANT_SUDO" == "y" ]] && [[ "$GRANT_DOCKER" != "y" ]] && [[ "$TUNNEL_ONLY" != "y" ]]; then
    echo ""
    echo -e "${CYAN}Apps Group Access:${NC}"
    echo "  The 'apps' group allows reading application configs in /opt/apps"
    echo "  without needing sudo. Useful for debugging."
    read -p "Add $USERNAME to apps group? (y/n): " ADD_APPS_GROUP

    if [[ "$ADD_APPS_GROUP" == "y" ]]; then
        usermod -aG apps "$USERNAME"
        log_info "Apps group access granted (can read /opt/apps)"
        APPS_GROUP_GRANTED="y"
    else
        # Remove from apps group if exists (for updates)
        if [[ "$USER_EXISTS" == "true" ]]; then
            gpasswd -d "$USERNAME" apps 2>/dev/null || true
        fi
        APPS_GROUP_GRANTED="n"
    fi
else
    APPS_GROUP_GRANTED="n"
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
# Configure SSH restrictions for tunnel-only users
#######################################
if [[ "$TUNNEL_ONLY" == "y" ]]; then
    log_step "Configuring SSH tunnel-only restrictions"

    SSHD_CONFIG="/etc/ssh/sshd_config"
    MATCH_BLOCK="Match User $USERNAME"

    # Check if Match block already exists
    if grep -q "^Match User $USERNAME" "$SSHD_CONFIG" 2>/dev/null; then
        log_warn "SSH Match block for $USERNAME already exists, skipping"
    else
        # Add Match block for tunnel-only user
        cat >> "$SSHD_CONFIG" << EOF

# Tunnel-only user: $USERNAME (added by add-user.sh)
Match User $USERNAME
    AllowTcpForwarding yes
    X11Forwarding no
    AllowAgentForwarding no
    PermitTTY no
    ForceCommand /bin/false
EOF
        log_info "SSH tunnel-only restrictions configured"

        # Reload SSH
        if systemctl is-active --quiet sshd; then
            systemctl reload sshd
            log_info "SSH service reloaded"
        elif systemctl is-active --quiet ssh; then
            systemctl reload ssh
            log_info "SSH service reloaded"
        fi
    fi
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
    echo -e "  - Apps group: ${GREEN}YES${NC} (can access /opt/apps)"
else
    echo -e "  - Docker access: ${YELLOW}NO${NC} (cannot control infrastructure)"
    if [[ "$APPS_GROUP_GRANTED" == "y" ]]; then
        echo -e "  - Apps group: ${GREEN}YES${NC} (can read /opt/apps)"
    else
        echo -e "  - Apps group: ${YELLOW}NO${NC}"
    fi
fi
if [[ "$CI_RUNNER" == "y" ]]; then
    echo -e "  - SSH key: ${YELLOW}N/A${NC} (service account)"
elif [[ -n "$SSH_PUBLIC_KEY" ]]; then
    echo -e "  - SSH key: ${GREEN}CONFIGURED${NC}"
else
    echo -e "  - SSH key: ${YELLOW}NOT SET${NC} (password auth only)"
fi

echo ""

# Show connection command
SSH_PORT=$(grep -E "^Port " /etc/ssh/sshd_config.d/hardening.conf 2>/dev/null | awk '{print $2}' || grep -E "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
HOSTNAME=$(hostname -I | awk '{print $1}')

if [[ "$CI_RUNNER" == "y" ]]; then
    log_info "CI Runner service account configured!"
    echo ""
    echo -e "${CYAN}Next steps:${NC}"
    echo "  1. Install gitlab-runner (if not already installed):"
    echo "     curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh | sudo bash"
    echo "     sudo apt-get install gitlab-runner"
    echo ""
    echo "  2. Register the runner:"
    echo "     sudo gitlab-runner register"
    echo ""
    echo "  3. Restart gitlab-runner service:"
    echo "     sudo systemctl restart gitlab-runner"
    echo ""
    echo -e "${CYAN}What $USERNAME can do:${NC}"
    echo "  - Run docker commands (docker ps, docker compose, etc.)"
    echo "  - Write to /opt/apps directory"
    echo "  - Deploy applications via CI/CD"
    echo ""
    echo -e "${CYAN}What $USERNAME CANNOT do:${NC}"
    echo "  - SSH into the server (no password, no key)"
    echo "  - Run commands as root (no sudo)"
    echo "  - Access system configuration"
elif [[ "$TUNNEL_ONLY" == "y" ]]; then
    log_info "Dev partner can create SSH tunnel with:"
    echo ""
    echo "  # Create tunnel (run on local machine)"
    echo "  ssh -N -p $SSH_PORT \\"
    echo "      -L 5432:localhost:5432 \\"
    echo "      -L 6379:localhost:6379 \\"
    echo "      -L 6380:localhost:6380 \\"
    echo "      $USERNAME@$HOSTNAME"
    echo ""
    echo "  # Then connect to services locally:"
    echo "  psql -h localhost -p 5432 -U postgres"
    echo "  redis-cli -h localhost -p 6379"
    echo ""
    echo -e "${CYAN}What $USERNAME can do:${NC}"
    echo "  - Create SSH tunnels to access PostgreSQL, Redis, etc."
    echo "  - Connect to databases from their local machine"
    echo ""
    echo -e "${CYAN}What $USERNAME CANNOT do:${NC}"
    echo "  - Execute ANY commands on the server"
    echo "  - Get a shell session"
    echo "  - Access files on the server"
    echo "  - Control Docker containers"
else
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
        echo "  - Modify application configs directly on server"
    fi
    if [[ "$GRANT_SUDO" != "y" ]]; then
        echo "  - Run commands as root"
        echo "  - Install system packages"
        echo "  - Modify system configuration"
    fi

    # Show Grafana access for non-docker users
    if [[ "$GRANT_DOCKER" != "y" ]]; then
        echo ""
        echo -e "${CYAN}How to view logs (via Grafana):${NC}"
        echo "  1. Open: http://$HOSTNAME:3000"
        echo "  2. Login with Grafana credentials"
        echo "  3. Go to: Explore → Loki → Select container"
        echo ""
        echo -e "${CYAN}Production Workflow:${NC}"
        echo "  - All app changes should go through Git → CI/CD"
        echo "  - Never modify .env or docker-compose directly on server"
        echo "  - Use GitLab/GitHub CI variables for secrets"
    fi
fi

echo ""
echo "=========================================="
