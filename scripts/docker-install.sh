#!/bin/bash

#######################################
# Production-Grade Docker Installation Script
# Supports: Ubuntu, Debian, CentOS, RHEL, Oracle Linux, Amazon Linux
# Features: Error handling, logging, security hardening
#######################################

set -euo pipefail  # Exit on error, undefined variables, pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   log_error "This script should not be run as root. Run as a regular user with sudo privileges."
   exit 1
fi

# Check sudo privileges
if ! sudo -n true 2>/dev/null; then
    log_error "This script requires sudo privileges. Please run with a user that has sudo access."
    exit 1
fi

log_info "Starting Docker installation for production environment..."

#######################################
# Detect OS
#######################################
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        OS="rhel"
        OS_VERSION=$(cat /etc/redhat-release | grep -oE '[0-9]+\.[0-9]+' | head -1)
    else
        log_error "Unsupported operating system"
        exit 1
    fi

    log_info "Detected OS: $OS $OS_VERSION"
}

#######################################
# Remove old Docker installations
#######################################
remove_old_docker() {
    log_info "Removing old Docker installations if any..."

    if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
        sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    elif [[ "$OS" == "centos" ]] || [[ "$OS" == "rhel" ]] || [[ "$OS" == "amzn" ]] || [[ "$OS" == "ol" ]]; then
        sudo yum remove -y docker docker-client docker-client-latest docker-common docker-latest \
            docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true
    fi

    log_info "Old Docker versions removed"
}

#######################################
# Install Docker on Ubuntu/Debian
#######################################
install_docker_debian() {
    log_info "Installing Docker on Debian-based system..."

    # Install prerequisites
    sudo apt-get update
    sudo apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        software-properties-common

    # Add Docker's official GPG key
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$OS/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    # Set up the repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker Engine
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    log_info "Docker installed successfully on $OS"
}

#######################################
# Install Docker on CentOS/RHEL
#######################################
install_docker_rhel() {
    log_info "Installing Docker on RHEL-based system..."

    # Install prerequisites
    sudo yum install -y yum-utils device-mapper-persistent-data lvm2

    # Add Docker repository
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

    # Install Docker Engine
    sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    log_info "Docker installed successfully on $OS"
}

#######################################
# Install Docker on Amazon Linux
#######################################
install_docker_amazon() {
    log_info "Installing Docker on Amazon Linux..."

    sudo yum update -y

    if [[ "$OS_VERSION" == "2" ]]; then
        sudo amazon-linux-extras install docker -y

        # Install Docker Compose plugin separately for AL2
        COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d'"' -f4)
        sudo mkdir -p /usr/local/lib/docker/cli-plugins
        sudo curl -SL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-$(uname -m)" \
            -o /usr/local/lib/docker/cli-plugins/docker-compose
        sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    else
        # Amazon Linux 2023+
        sudo yum install -y docker
        sudo yum install -y docker-compose-plugin
    fi

    log_info "Docker installed successfully on Amazon Linux"
}

#######################################
# Configure Docker daemon for production
#######################################
configure_docker_daemon() {
    log_info "Configuring Docker daemon for production..."

    sudo mkdir -p /etc/docker

    # Create daemon.json with production settings
    sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "live-restore": true,
  "userland-proxy": false,
  "no-new-privileges": true,
  "icc": false,
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 64000,
      "Soft": 64000
    }
  }
}
EOF

    log_info "Docker daemon configured with production settings"
}

#######################################
# Start and enable Docker
#######################################
start_docker() {
    log_info "Starting Docker service..."

    sudo systemctl daemon-reload
    sudo systemctl start docker
    sudo systemctl enable docker

    # Wait for Docker to be ready
    sleep 3

    if sudo systemctl is-active --quiet docker; then
        log_info "Docker service is running"
    else
        log_error "Docker service failed to start"
        sudo journalctl -u docker -n 50 --no-pager
        exit 1
    fi
}

#######################################
# Add user to docker group
#######################################
add_user_to_docker_group() {
    log_info "Adding user $USER to docker group..."

    sudo usermod -aG docker $USER

    log_warn "You need to log out and back in for group changes to take effect"
    log_warn "Or run: newgrp docker"
}

#######################################
# Setup apps directory for deployments
#######################################
setup_apps_directory() {
    log_info "Setting up /opt/apps directory for deployments..."

    # Create apps group if it doesn't exist
    if ! getent group apps &>/dev/null; then
        sudo groupadd apps
        log_info "Created 'apps' group"
    fi

    # Add current user to apps group
    sudo usermod -aG apps $USER
    log_info "Added $USER to apps group"

    # Create /opt/apps with proper permissions
    sudo mkdir -p /opt/apps
    sudo chown root:apps /opt/apps
    sudo chmod 2775 /opt/apps  # setgid so new files inherit apps group

    log_info "Apps directory configured: /opt/apps (group: apps, mode: 2775)"
}

#######################################
# Verify installation
#######################################
verify_installation() {
    log_info "Verifying Docker installation..."

    # Check Docker version
    DOCKER_VERSION=$(docker --version)
    log_info "Docker version: $DOCKER_VERSION"

    # Check Docker Compose version
    if docker compose version &>/dev/null; then
        COMPOSE_VERSION=$(docker compose version)
        log_info "Docker Compose version: $COMPOSE_VERSION"
    else
        log_error "Docker Compose plugin not found"
        exit 1
    fi

    # Test Docker with hello-world (using sudo since user isn't in group yet in current session)
    log_info "Running test container..."
    if sudo docker run --rm hello-world > /dev/null 2>&1; then
        log_info "Docker is working correctly!"
    else
        log_error "Docker test failed"
        exit 1
    fi
}

#######################################
# Display post-installation info
#######################################
display_post_install_info() {
    echo ""
    echo "=========================================="
    log_info "Docker installation completed successfully!"
    echo "=========================================="
    echo ""
    echo "Current user ($USER) has been added to docker group."
    echo ""
    log_warn "IMPORTANT: Log out and log back in for docker access!"
    echo "  Or run: newgrp docker"
    echo ""
    echo "=========================================="
    log_info "Next Steps:"
    echo "=========================================="
    echo ""
    echo "1. Log out and log back in (required for docker group)"
    echo ""
    echo "2. Test Docker:"
    echo "   docker run hello-world"
    echo "   docker compose version"
    echo ""
    echo "3. Create Infra Admin user (if needed):"
    echo "   sudo bash scripts/add-user.sh"
    echo "   -> Select type 3 (Infra Admin) for full permissions"
    echo ""
    echo "4. Setup infrastructure:"
    echo "   cd /opt/infra && ./setup.sh"
    echo ""
    echo "=========================================="
    log_info "Docker daemon config: /etc/docker/daemon.json"
    log_info "View logs: sudo journalctl -u docker -f"
    echo "=========================================="
    echo ""
}

#######################################
# Main installation flow
#######################################
main() {
    detect_os
    remove_old_docker

    case "$OS" in
        ubuntu|debian)
            install_docker_debian
            ;;
        centos|rhel|ol)
            install_docker_rhel
            ;;
        amzn)
            install_docker_amazon
            ;;
        *)
            log_error "Unsupported OS: $OS"
            exit 1
            ;;
    esac

    configure_docker_daemon
    start_docker
    add_user_to_docker_group
    setup_apps_directory
    verify_installation
    display_post_install_info
}

# Run main function
main
