#!/bin/bash
# =============================================================================
# Infrastructure Bootstrap Script
# =============================================================================
# Run this on a FRESH server to set up everything from scratch.
#
# Usage (on new server):
#   curl -fsSL https://raw.githubusercontent.com/YOUR_USER/infra/main/bootstrap.sh | bash
#
# Or clone first:
#   git clone https://github.com/YOUR_USER/infra.git && cd infra && ./bootstrap.sh
#
# Steps:
#   1. VPS hardening (user, SSH, firewall)
#   2. Docker installation
#   3. Clone/update infra repo
#   4. Configure services
#   5. Start infrastructure
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step() { echo -e "${CYAN}[→]${NC} $1"; }

header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# =============================================================================
# Configuration
# =============================================================================
REPO_URL="${INFRA_REPO_URL:-https://github.com/YOUR_USER/infra.git}"
INSTALL_DIR="${INFRA_DIR:-/opt/infra}"

# =============================================================================
# Detect what's already done
# =============================================================================
check_status() {
    header "Checking Current Status"

    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        IS_ROOT=true
        log_info "Running as root"
    else
        IS_ROOT=false
        log_info "Running as regular user"
    fi

    # Check Docker
    if command -v docker &> /dev/null && docker info &> /dev/null; then
        DOCKER_INSTALLED=true
        log_info "Docker is installed and running"
    else
        DOCKER_INSTALLED=false
        log_warn "Docker not installed or not running"
    fi

    # Check if infra repo exists
    if [[ -d "$INSTALL_DIR" ]] && [[ -f "$INSTALL_DIR/setup-all.sh" ]]; then
        REPO_EXISTS=true
        log_info "Infra repo found at $INSTALL_DIR"
    else
        REPO_EXISTS=false
        log_warn "Infra repo not found"
    fi

    # Check if services are running
    if docker ps 2>/dev/null | grep -q -E "(postgres|redis|traefik)"; then
        SERVICES_RUNNING=true
        log_info "Some services are already running"
    else
        SERVICES_RUNNING=false
        log_warn "No infrastructure services running"
    fi

    echo ""
}

# =============================================================================
# Menu
# =============================================================================
show_menu() {
    header "Infrastructure Bootstrap"

    echo "What would you like to do?"
    echo ""
    echo "  1) Full setup (fresh server - VPS + Docker + Services)"
    echo "  2) Install Docker only"
    echo "  3) Clone/update infra repo only"
    echo "  4) Configure and start services"
    echo "  5) Check status"
    echo "  6) Exit"
    echo ""
    read -p "Select option [1-6]: " choice
    echo ""

    case $choice in
        1) full_setup ;;
        2) install_docker ;;
        3) clone_repo ;;
        4) start_services ;;
        5) check_full_status ;;
        6) exit 0 ;;
        *) log_error "Invalid option"; show_menu ;;
    esac
}

# =============================================================================
# Step 1: VPS Setup
# =============================================================================
setup_vps() {
    header "Step 1: VPS Initial Setup"

    if [[ "$IS_ROOT" != "true" ]]; then
        log_warn "VPS setup requires root. Skipping..."
        log_info "Run manually: sudo bash vps/vps-initial-setup.sh"
        return
    fi

    read -p "Run VPS hardening? (creates user, hardens SSH, firewall) [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        if [[ -f "vps/vps-initial-setup.sh" ]]; then
            bash vps/vps-initial-setup.sh
        else
            log_warn "VPS setup script not found. Clone repo first."
        fi
    else
        log_info "Skipping VPS setup"
    fi
}

# =============================================================================
# Step 2: Docker Installation
# =============================================================================
install_docker() {
    header "Step 2: Docker Installation"

    if [[ "$DOCKER_INSTALLED" == "true" ]]; then
        log_info "Docker already installed"
        docker --version
        return
    fi

    log_step "Installing Docker..."

    # Try to use local script first
    if [[ -f "docker/docker-install-production.sh" ]]; then
        bash docker/docker-install-production.sh
    elif [[ -f "$INSTALL_DIR/docker/docker-install-production.sh" ]]; then
        bash "$INSTALL_DIR/docker/docker-install-production.sh"
    else
        # Download and run
        log_step "Downloading Docker install script..."
        curl -fsSL https://get.docker.com | bash
        sudo systemctl enable docker
        sudo systemctl start docker
        sudo usermod -aG docker $USER
    fi

    log_info "Docker installed"
    log_warn "You may need to log out and back in for docker group"
}

# =============================================================================
# Step 3: Clone Repository
# =============================================================================
clone_repo() {
    header "Step 3: Clone/Update Infra Repository"

    if [[ "$REPO_EXISTS" == "true" ]]; then
        log_info "Repo exists, pulling latest..."
        cd "$INSTALL_DIR"
        git pull
    else
        log_step "Cloning repository..."

        # Create directory
        sudo mkdir -p "$INSTALL_DIR"
        sudo chown $USER:$USER "$INSTALL_DIR"

        # Clone
        git clone "$REPO_URL" "$INSTALL_DIR"
        cd "$INSTALL_DIR"
    fi

    log_info "Repository ready at $INSTALL_DIR"
}

# =============================================================================
# Step 4: Start Services
# =============================================================================
start_services() {
    header "Step 4: Configure & Start Services"

    if [[ ! -f "$INSTALL_DIR/setup-all.sh" ]]; then
        log_error "Infra repo not found. Run 'Clone repo' first."
        return
    fi

    cd "$INSTALL_DIR"

    # Check if password is set
    if [[ ! -f ".password_hash" ]]; then
        log_step "Setting admin password..."
        ./setup-all.sh --set-password
    fi

    # Edit services.conf
    echo ""
    log_info "Current services.conf:"
    echo ""
    grep "=true" services.conf | head -10
    echo ""

    read -p "Edit services.conf before starting? [y/N]: " edit_conf
    if [[ "$edit_conf" =~ ^[Yy]$ ]]; then
        ${EDITOR:-nano} services.conf
    fi

    # Start
    log_step "Starting services..."
    ./setup-all.sh
}

# =============================================================================
# Full Setup
# =============================================================================
full_setup() {
    header "Full Setup (Fresh Server)"

    echo "This will:"
    echo "  1. Harden VPS (optional)"
    echo "  2. Install Docker"
    echo "  3. Clone infra repo to $INSTALL_DIR"
    echo "  4. Configure and start services"
    echo ""
    read -p "Continue? [y/N]: " confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Cancelled"
        exit 0
    fi

    setup_vps
    install_docker
    clone_repo
    start_services

    header "Setup Complete!"
    echo "Your infrastructure is now running."
    echo ""
    echo "Next steps:"
    echo "  cd $INSTALL_DIR"
    echo "  ./status.sh              # Check services"
    echo "  ./lib/db-cli.sh --help   # Manage databases"
    echo ""
}

# =============================================================================
# Status Check
# =============================================================================
check_full_status() {
    header "Full Status Check"

    check_status

    if [[ -f "$INSTALL_DIR/status.sh" ]]; then
        cd "$INSTALL_DIR"
        ./status.sh
    fi
}

# =============================================================================
# Main
# =============================================================================
main() {
    # If running from curl pipe, clone first
    if [[ ! -f "setup-all.sh" ]] && [[ ! -d ".git" ]]; then
        header "Bootstrap from Remote"
        log_step "Downloading infra repository..."

        INSTALL_DIR="${INSTALL_DIR:-/opt/infra}"
        sudo mkdir -p "$INSTALL_DIR"
        sudo chown $USER:$USER "$INSTALL_DIR"

        git clone "$REPO_URL" "$INSTALL_DIR"
        cd "$INSTALL_DIR"

        log_info "Repository cloned to $INSTALL_DIR"
        exec ./bootstrap.sh
    fi

    # Already in repo
    INSTALL_DIR="$(pwd)"
    check_status
    show_menu
}

main "$@"
