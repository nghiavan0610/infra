#!/bin/bash
# =============================================================================
# Backup System Setup Script
# =============================================================================
# Usage: ./setup.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Require authentication
INFRA_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$INFRA_ROOT/lib/common.sh"
require_auth

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo ""
echo "=============================================="
echo "  Backup System Setup"
echo "=============================================="
echo ""

# -----------------------------------------------------------------------------
# Install Restic
# -----------------------------------------------------------------------------
install_restic() {
    if command -v restic &> /dev/null; then
        success "Restic already installed: $(restic version | head -1)"
        return 0
    fi

    info "Installing Restic..."

    # Detect OS
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        local arch="amd64"
        if [[ $(uname -m) == "aarch64" ]]; then
            arch="arm64"
        fi

        curl -L "https://github.com/restic/restic/releases/download/v0.16.4/restic_0.16.4_linux_${arch}.bz2" | bunzip2 > /tmp/restic
        sudo mv /tmp/restic /usr/local/bin/restic
        sudo chmod +x /usr/local/bin/restic

    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
            brew install restic
        else
            error "Please install Homebrew first: https://brew.sh"
        fi
    else
        error "Unsupported OS: $OSTYPE"
    fi

    success "Restic installed: $(restic version | head -1)"
}

# -----------------------------------------------------------------------------
# Setup Environment
# -----------------------------------------------------------------------------
setup_environment() {
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        warn ".env already exists"
        read -p "Overwrite? [y/N]: " overwrite
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi

    info "Creating .env from template..."
    cp "${SCRIPT_DIR}/.env.example" "${SCRIPT_DIR}/.env"

    # Generate Restic password
    local restic_password=$(openssl rand -base64 32)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|RESTIC_PASSWORD=.*|RESTIC_PASSWORD=${restic_password}|" "${SCRIPT_DIR}/.env"
    else
        sed -i "s|RESTIC_PASSWORD=.*|RESTIC_PASSWORD=${restic_password}|" "${SCRIPT_DIR}/.env"
    fi

    success ".env created with generated password"
    warn "IMPORTANT: Save this password securely! You need it to restore backups!"
    echo ""
    echo "  Restic Password: ${restic_password}"
    echo ""
}

# -----------------------------------------------------------------------------
# Create Directories
# -----------------------------------------------------------------------------
create_directories() {
    info "Creating directories..."

    mkdir -p "${SCRIPT_DIR}/logs"
    mkdir -p "${SCRIPT_DIR}/config"

    success "Directories created"
}

# -----------------------------------------------------------------------------
# Make Scripts Executable
# -----------------------------------------------------------------------------
make_executable() {
    info "Making scripts executable..."

    chmod +x "${SCRIPT_DIR}/scripts/"*.sh

    success "Scripts are executable"
}

# -----------------------------------------------------------------------------
# Initialize Restic Repository
# -----------------------------------------------------------------------------
init_repository() {
    info "Do you want to initialize the Restic repository now?"
    echo "  (You need to configure .env first with your storage backend)"
    echo ""
    read -p "Initialize repository? [y/N]: " init_repo

    if [[ "$init_repo" =~ ^[Yy]$ ]]; then
        source "${SCRIPT_DIR}/.env"

        if [[ -z "${RESTIC_REPOSITORY:-}" ]]; then
            error "RESTIC_REPOSITORY not set in .env"
        fi

        info "Initializing repository: ${RESTIC_REPOSITORY}"
        restic init || warn "Repository may already be initialized"
        success "Repository ready"
    fi
}

# -----------------------------------------------------------------------------
# Setup Scheduling
# -----------------------------------------------------------------------------
setup_scheduling() {
    echo ""
    info "How do you want to schedule backups?"
    echo "  1) Cron (traditional)"
    echo "  2) Systemd timer (modern Linux)"
    echo "  3) Skip (I'll set up manually)"
    echo ""
    read -p "Choose [1-3]: " schedule_choice

    case "$schedule_choice" in
        1)
            info "Setting up cron..."
            if [[ "$OSTYPE" == "linux-gnu"* ]]; then
                sudo cp "${SCRIPT_DIR}/cron/backup-cron" /etc/cron.d/infra-backup
                sudo chmod 644 /etc/cron.d/infra-backup
                success "Cron job installed at /etc/cron.d/infra-backup"
            else
                warn "For macOS, add to crontab manually:"
                echo "  crontab -e"
                echo "  0 2 * * * ${SCRIPT_DIR}/scripts/backup.sh all"
            fi
            ;;
        2)
            if [[ "$OSTYPE" == "linux-gnu"* ]]; then
                info "Setting up systemd timer..."
                sudo cp "${SCRIPT_DIR}/cron/backup.service" /etc/systemd/system/
                sudo cp "${SCRIPT_DIR}/cron/backup.timer" /etc/systemd/system/

                # Update path in service file
                sudo sed -i "s|/opt/infra/backup|${SCRIPT_DIR}|g" /etc/systemd/system/backup.service

                sudo systemctl daemon-reload
                sudo systemctl enable --now backup.timer
                success "Systemd timer enabled"
                echo ""
                echo "  Check status: systemctl status backup.timer"
                echo "  View logs:    journalctl -u backup.service"
            else
                warn "Systemd not available on macOS. Use cron instead."
            fi
            ;;
        3)
            info "Skipping scheduling setup"
            ;;
        *)
            warn "Invalid choice, skipping"
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Test Backup
# -----------------------------------------------------------------------------
test_backup() {
    echo ""
    read -p "Run a test backup now? [y/N]: " run_test

    if [[ "$run_test" =~ ^[Yy]$ ]]; then
        info "Running test backup..."
        "${SCRIPT_DIR}/scripts/backup.sh" all
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    install_restic
    setup_environment
    create_directories
    make_executable

    echo ""
    warn "Please edit .env and configure:"
    echo "  - Storage backend (MinIO, S3, Backblaze B2, etc.)"
    echo "  - Database credentials"
    echo "  - Volumes to backup"
    echo ""
    read -p "Press Enter to edit .env (or Ctrl+C to skip)..." _

    if command -v nano &> /dev/null; then
        nano "${SCRIPT_DIR}/.env"
    elif command -v vim &> /dev/null; then
        vim "${SCRIPT_DIR}/.env"
    fi

    init_repository
    setup_scheduling
    test_backup

    echo ""
    echo "=============================================="
    echo "  Setup Complete!"
    echo "=============================================="
    echo ""
    echo "  Manual backup:   ${SCRIPT_DIR}/scripts/backup.sh"
    echo "  Restore:         ${SCRIPT_DIR}/scripts/restore.sh"
    echo "  List snapshots:  ${SCRIPT_DIR}/scripts/restore.sh list"
    echo ""
    echo "  Logs:            ${SCRIPT_DIR}/logs/"
    echo "  Config:          ${SCRIPT_DIR}/.env"
    echo ""
}

main "$@"
