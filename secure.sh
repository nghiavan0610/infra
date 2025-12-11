#!/bin/bash
# =============================================================================
# Secure Infrastructure Directory
# =============================================================================
# Sets proper file permissions to prevent unauthorized access
#
# Usage:
#   ./secure.sh              # Secure for current user only
#   ./secure.sh --group NAME # Secure for a group of admins
#   ./secure.sh --check      # Check current permissions (no changes)
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load shared library
source "$SCRIPT_DIR/lib/common.sh"

# Require authentication
require_auth

# =============================================================================
# Configuration
# =============================================================================

# Files that contain secrets (restrict to 600/640)
SENSITIVE_FILES=(
    ".secrets"
    ".password_hash"
    ".env"
)

# Patterns for sensitive files in subdirectories
SENSITIVE_PATTERNS=(
    "services/*/.env"
    "services/*/.env.local"
    "services/*/secrets/*"
    "services/*/.credentials/*"
)

# Directories that should not be world-readable
PRIVATE_DIRS=(
    "."
    "services"
    "lib"
    "scripts"
)

# =============================================================================
# Functions
# =============================================================================

check_permissions() {
    log_header "Permission Check"

    local issues=0

    # Check root directory
    local dir_perms=$(stat -c "%a" "$SCRIPT_DIR" 2>/dev/null || stat -f "%OLp" "$SCRIPT_DIR")
    if [[ "$dir_perms" =~ [0-7][0-7][5-7]$ ]]; then
        log_warn "Directory is world-readable: $SCRIPT_DIR ($dir_perms)"
        ((issues++))
    else
        log_info "Directory permissions OK: $SCRIPT_DIR ($dir_perms)"
    fi

    # Check sensitive files
    for file in "${SENSITIVE_FILES[@]}"; do
        if [[ -f "$SCRIPT_DIR/$file" ]]; then
            local perms=$(stat -c "%a" "$SCRIPT_DIR/$file" 2>/dev/null || stat -f "%OLp" "$SCRIPT_DIR/$file")
            if [[ "$perms" =~ [0-7][0-7][1-7]$ ]] || [[ "$perms" =~ [0-7][1-7][0-7]$ && ! "$perms" =~ ^[0-7][0-4] ]]; then
                log_warn "Sensitive file too open: $file ($perms)"
                ((issues++))
            else
                log_info "Sensitive file OK: $file ($perms)"
            fi
        fi
    done

    # Check .env files in services
    while IFS= read -r -d '' envfile; do
        local perms=$(stat -c "%a" "$envfile" 2>/dev/null || stat -f "%OLp" "$envfile")
        local relpath="${envfile#$SCRIPT_DIR/}"
        if [[ "$perms" =~ [0-7][0-7][1-7]$ ]]; then
            log_warn "Service .env too open: $relpath ($perms)"
            ((issues++))
        else
            log_info "Service .env OK: $relpath ($perms)"
        fi
    done < <(find "$SCRIPT_DIR/services" -name ".env" -print0 2>/dev/null)

    echo ""
    if [[ $issues -eq 0 ]]; then
        log_info "All permissions look good!"
    else
        log_warn "Found $issues permission issues. Run ./secure.sh to fix."
    fi

    return $issues
}

secure_for_user() {
    local owner=${1:-$USER}

    log_header "Securing for User: $owner"

    # Set ownership of entire directory
    log_step "Setting ownership to $owner..."
    if [[ "$EUID" -eq 0 ]]; then
        chown -R "$owner:$owner" "$SCRIPT_DIR"
    else
        # Try with sudo if not root
        if command -v sudo &>/dev/null; then
            sudo chown -R "$owner:$(id -gn $owner)" "$SCRIPT_DIR"
        else
            log_warn "Not root and sudo not available. Ownership unchanged."
        fi
    fi

    # Set root directory permissions (owner only)
    log_step "Setting directory permissions..."
    chmod 700 "$SCRIPT_DIR"

    # Most directories: 700 (owner only)
    find "$SCRIPT_DIR" -type d -exec chmod 700 {} \;

    # Mounted directories need 755 (Docker containers run as different users)
    log_step "Setting Docker-mounted directories (755)..."
    find "$SCRIPT_DIR/services" -type d \( \
        -name "dashboards" -o \
        -name "config" -o \
        -name "scripts" -o \
        -name "init-scripts" -o \
        -name "data" -o \
        -name "certs" -o \
        -name "rules" -o \
        -name "provisioning" -o \
        -name "alerting-rules" -o \
        -name "recording-rules" \
    \) -exec chmod 755 {} \;

    # Set script permissions (executable by owner)
    log_step "Setting script permissions (700)..."
    find "$SCRIPT_DIR" -name "*.sh" -exec chmod 700 {} \;

    # Set regular file permissions
    # Config files (644) - need to be readable by Docker containers
    log_step "Setting config file permissions (644)..."
    find "$SCRIPT_DIR/services" -type f \( \
        -name "*.conf" -o -name "*.yml" -o -name "*.yaml" -o -name "*.toml" -o \
        -name "*.json" -o -name "*.xml" -o -name "*.cnf" -o -name "*.ini" -o \
        -name "*.properties" -o -name "*.cfg" -o -name "*.rules" -o -name "*.sql" -o \
        -name "enabled_plugins" -o -name "definitions.json" -o -name "Corefile" -o \
        -name "*.template" -o -name "*.tmpl" -o -name "*.tpl" -o -name "*.lua" -o \
        -name "*.crt" -o -name "*.pem" -o -name "*.pub" \
    \) -exec chmod 644 {} \;

    # Private keys need stricter permissions (600)
    find "$SCRIPT_DIR/services" -type f \( -name "*.key" -o -name "keyfile" \) -exec chmod 600 {} \;

    # Other files (600)
    log_step "Setting other file permissions (600)..."
    find "$SCRIPT_DIR" -type f ! -path "*/services/*" ! -name "*.sh" ! -name "*.md" ! -name "*.txt" ! -name "LICENSE" ! -name ".gitignore" -exec chmod 600 {} \;

    # Ensure sensitive files are extra protected
    log_step "Protecting sensitive files..."
    for file in "${SENSITIVE_FILES[@]}"; do
        [[ -f "$SCRIPT_DIR/$file" ]] && chmod 600 "$SCRIPT_DIR/$file"
    done

    for pattern in "${SENSITIVE_PATTERNS[@]}"; do
        for file in $SCRIPT_DIR/$pattern; do
            [[ -f "$file" ]] && chmod 600 "$file"
        done
    done

    log_info "Directory secured for user: $owner"
    echo ""
    echo "Only $owner can now access /opt/infra"
}

secure_for_group() {
    local group=$1

    log_header "Securing for Group: $group"

    # Check if group exists
    if ! getent group "$group" &>/dev/null; then
        log_step "Creating group: $group"
        if [[ "$EUID" -eq 0 ]]; then
            groupadd "$group"
        else
            sudo groupadd "$group"
        fi
        log_info "Group created: $group"
        echo ""
        echo "Add users to this group with:"
        echo "  sudo usermod -aG $group USERNAME"
        echo ""
    fi

    # Set ownership
    log_step "Setting ownership to root:$group..."
    if [[ "$EUID" -eq 0 ]]; then
        chown -R "root:$group" "$SCRIPT_DIR"
    else
        sudo chown -R "root:$group" "$SCRIPT_DIR"
    fi

    # Set root directory permissions (owner + group)
    log_step "Setting directory permissions..."
    chmod 750 "$SCRIPT_DIR"

    # Most directories: 750 (owner + group)
    find "$SCRIPT_DIR" -type d -exec chmod 750 {} \;

    # Mounted directories need 755 (Docker containers run as different users)
    log_step "Setting Docker-mounted directories (755)..."
    find "$SCRIPT_DIR/services" -type d \( \
        -name "dashboards" -o \
        -name "config" -o \
        -name "scripts" -o \
        -name "init-scripts" -o \
        -name "data" -o \
        -name "certs" -o \
        -name "rules" -o \
        -name "provisioning" -o \
        -name "alerting-rules" -o \
        -name "recording-rules" \
    \) -exec chmod 755 {} \;

    # Set script permissions (executable by owner + group)
    log_step "Setting script permissions (750)..."
    find "$SCRIPT_DIR" -name "*.sh" -exec chmod 750 {} \;

    # Set config file permissions (readable by all - needed by Docker containers)
    log_step "Setting config file permissions (644)..."
    find "$SCRIPT_DIR/services" -type f \( \
        -name "*.conf" -o -name "*.yml" -o -name "*.yaml" -o -name "*.toml" -o \
        -name "*.json" -o -name "*.xml" -o -name "*.cnf" -o -name "*.ini" -o \
        -name "*.properties" -o -name "*.cfg" -o -name "*.rules" -o -name "*.sql" -o \
        -name "enabled_plugins" -o -name "definitions.json" -o -name "Corefile" -o \
        -name "*.template" -o -name "*.tmpl" -o -name "*.tpl" -o -name "*.lua" -o \
        -name "*.crt" -o -name "*.pem" -o -name "*.pub" \
    \) -exec chmod 644 {} \;

    # Private keys need stricter permissions (600)
    find "$SCRIPT_DIR/services" -type f \( -name "*.key" -o -name "keyfile" \) -exec chmod 600 {} \;

    # Other files (readable by group)
    log_step "Setting other file permissions (640)..."
    find "$SCRIPT_DIR" -type f ! -path "*/services/*" ! -name "*.sh" ! -name "*.md" ! -name "*.txt" ! -name "LICENSE" ! -name ".gitignore" -exec chmod 640 {} \;

    # Sensitive files - owner only (not even group)
    log_step "Protecting sensitive files (600)..."
    for file in "${SENSITIVE_FILES[@]}"; do
        [[ -f "$SCRIPT_DIR/$file" ]] && chmod 600 "$SCRIPT_DIR/$file"
    done

    for pattern in "${SENSITIVE_PATTERNS[@]}"; do
        for file in $SCRIPT_DIR/$pattern; do
            [[ -f "$file" ]] && chmod 600 "$file"
        done
    done

    log_info "Directory secured for group: $group"
    echo ""
    echo "Members of '$group' can run scripts."
    echo "Only root can read sensitive files (.env, .secrets)."
}

show_help() {
    echo "Usage: ./secure.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  (no args)        Secure for current user only (strictest)"
    echo "  --group NAME     Secure for admin group (allows multiple admins)"
    echo "  --check          Check current permissions without changes"
    echo "  --help           Show this help"
    echo ""
    echo "Examples:"
    echo "  ./secure.sh                    # Only you can access"
    echo "  ./secure.sh --group infra      # 'infra' group members can access"
    echo "  ./secure.sh --check            # Audit current permissions"
    echo ""
}

# =============================================================================
# Main
# =============================================================================

case "${1:-}" in
    --help|-h)
        show_help
        ;;
    --check)
        check_permissions
        ;;
    --group)
        if [[ -z "${2:-}" ]]; then
            log_error "Group name required: ./secure.sh --group NAME"
            exit 1
        fi
        secure_for_group "$2"
        ;;
    "")
        secure_for_user "$USER"
        ;;
    *)
        log_error "Unknown option: $1"
        show_help
        exit 1
        ;;
esac
