#!/bin/bash

#######################################
# Audit Server Access Script
# Shows who has access to what on this server
#
# Run as: sudo bash audit-access.sh
#######################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[RISK]${NC} $1"; }
log_header() { echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

echo ""
echo "=========================================="
echo "  Server Access Audit"
echo "=========================================="
echo "  Hostname: $(hostname)"
echo "  Date: $(date)"
echo "=========================================="

#######################################
# Docker Group Members
#######################################
log_header "Docker Access (can control ALL containers)"

if getent group docker &>/dev/null; then
    DOCKER_USERS=$(getent group docker | cut -d: -f4)
    if [[ -n "$DOCKER_USERS" ]]; then
        echo ""
        echo "Users with Docker access:"
        IFS=',' read -ra USERS <<< "$DOCKER_USERS"
        for user in "${USERS[@]}"; do
            if [[ -n "$user" ]]; then
                echo -e "  - ${RED}$user${NC}"
            fi
        done
        echo ""
        log_warn "These users can start/stop/remove ANY container!"
        log_warn "They can also read secrets from running containers."
    else
        log_info "No non-root users in docker group"
    fi
else
    log_info "Docker not installed (no docker group)"
fi

#######################################
# Sudo Users
#######################################
log_header "Sudo Access (can run commands as root)"

echo ""
echo "Users with sudo privileges:"

# Check sudo group (Debian/Ubuntu)
if getent group sudo &>/dev/null; then
    SUDO_USERS=$(getent group sudo | cut -d: -f4)
    if [[ -n "$SUDO_USERS" ]]; then
        IFS=',' read -ra USERS <<< "$SUDO_USERS"
        for user in "${USERS[@]}"; do
            if [[ -n "$user" ]]; then
                # Check if also in docker group
                if groups "$user" 2>/dev/null | grep -q docker; then
                    echo -e "  - ${RED}$user${NC} (also has Docker access)"
                else
                    echo -e "  - ${YELLOW}$user${NC}"
                fi
            fi
        done
    fi
fi

# Check wheel group (RHEL/CentOS)
if getent group wheel &>/dev/null; then
    WHEEL_USERS=$(getent group wheel | cut -d: -f4)
    if [[ -n "$WHEEL_USERS" ]]; then
        IFS=',' read -ra USERS <<< "$WHEEL_USERS"
        for user in "${USERS[@]}"; do
            if [[ -n "$user" ]]; then
                # Check if also in docker group
                if groups "$user" 2>/dev/null | grep -q docker; then
                    echo -e "  - ${RED}$user${NC} (also has Docker access)"
                else
                    echo -e "  - ${YELLOW}$user${NC}"
                fi
            fi
        done
    fi
fi

echo ""
log_warn "Sudo users can add themselves to docker group!"
echo "  Command: sudo usermod -aG docker \$USER"

#######################################
# All Human Users
#######################################
log_header "All Human Users"

echo ""
printf "%-15s %-10s %-10s %-10s\n" "USERNAME" "SUDO" "DOCKER" "SHELL"
printf "%-15s %-10s %-10s %-10s\n" "--------" "----" "------" "-----"

# Get all human users (UID >= 1000)
while IFS=: read -r username _ uid _ _ _ shell; do
    if [[ $uid -ge 1000 ]] && [[ "$shell" != "/usr/sbin/nologin" ]] && [[ "$shell" != "/bin/false" ]]; then
        # Check sudo
        HAS_SUDO="no"
        if groups "$username" 2>/dev/null | grep -qE '\b(sudo|wheel)\b'; then
            HAS_SUDO="${YELLOW}yes${NC}"
        fi

        # Check docker
        HAS_DOCKER="no"
        if groups "$username" 2>/dev/null | grep -q docker; then
            HAS_DOCKER="${RED}YES${NC}"
        fi

        printf "%-15s %-10b %-10b %-10s\n" "$username" "$HAS_SUDO" "$HAS_DOCKER" "$shell"
    fi
done < /etc/passwd

#######################################
# Infrastructure Directory Access
#######################################
log_header "Infrastructure Directory"

INFRA_DIR="/opt/infra"
if [[ -d "$INFRA_DIR" ]]; then
    INFRA_PERMS=$(stat -c "%a" "$INFRA_DIR" 2>/dev/null || stat -f "%OLp" "$INFRA_DIR")
    INFRA_OWNER=$(stat -c "%U:%G" "$INFRA_DIR" 2>/dev/null || stat -f "%Su:%Sg" "$INFRA_DIR")

    echo ""
    echo "Directory: $INFRA_DIR"
    echo "Owner: $INFRA_OWNER"
    echo "Permissions: $INFRA_PERMS"
    echo ""

    if [[ "$INFRA_PERMS" == "700" ]]; then
        log_info "Directory is properly secured (700 - owner only)"
    elif [[ "$INFRA_PERMS" == "750" ]]; then
        log_warn "Directory allows group access (750)"
    else
        log_error "Directory may be too open ($INFRA_PERMS)"
        echo "  Run: ./secure.sh to fix permissions"
    fi
else
    log_warn "Infrastructure directory not found at $INFRA_DIR"
fi

#######################################
# Running Containers
#######################################
log_header "Running Docker Containers"

if command -v docker &>/dev/null; then
    echo ""
    CONTAINER_COUNT=$(docker ps -q 2>/dev/null | wc -l)
    if [[ $CONTAINER_COUNT -gt 0 ]]; then
        echo "Active containers: $CONTAINER_COUNT"
        echo ""
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | head -20
        if [[ $CONTAINER_COUNT -gt 19 ]]; then
            echo "  ... and $((CONTAINER_COUNT - 19)) more"
        fi
    else
        log_info "No running containers"
    fi
else
    log_info "Docker not installed"
fi

#######################################
# Security Recommendations
#######################################
log_header "Security Recommendations"

echo ""
ISSUES=0

# Check if multiple users have docker access
if getent group docker &>/dev/null; then
    DOCKER_USER_COUNT=$(getent group docker | cut -d: -f4 | tr ',' '\n' | grep -c . || echo 0)
    if [[ $DOCKER_USER_COUNT -gt 1 ]]; then
        log_warn "Multiple users ($DOCKER_USER_COUNT) have Docker access"
        echo "  Consider removing unnecessary users from docker group:"
        echo "  sudo gpasswd -d USERNAME docker"
        ((ISSUES++))
    fi
fi

# Check if infra directory is secured
if [[ -d "$INFRA_DIR" ]]; then
    INFRA_PERMS=$(stat -c "%a" "$INFRA_DIR" 2>/dev/null || stat -f "%OLp" "$INFRA_DIR")
    if [[ "$INFRA_PERMS" != "700" ]] && [[ "$INFRA_PERMS" != "750" ]]; then
        log_warn "Infrastructure directory permissions are too open"
        echo "  Run: cd $INFRA_DIR && ./secure.sh"
        ((ISSUES++))
    fi
fi

# Check for .env files with wrong permissions
if [[ -d "$INFRA_DIR" ]]; then
    OPEN_ENV=$(find "$INFRA_DIR" -name ".env" -perm /o+r 2>/dev/null | head -5)
    if [[ -n "$OPEN_ENV" ]]; then
        log_warn "Some .env files are world-readable:"
        echo "$OPEN_ENV" | while read f; do echo "  - $f"; done
        echo "  Run: cd $INFRA_DIR && ./secure.sh"
        ((ISSUES++))
    fi
fi

echo ""
if [[ $ISSUES -eq 0 ]]; then
    log_info "No major security issues found!"
else
    log_warn "Found $ISSUES issue(s) to review"
fi

echo ""
echo "=========================================="
