#!/bin/bash

#######################################
# VPS Health Check Script
# Run this to verify your VPS is properly configured
#######################################

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS="${GREEN}✓ PASS${NC}"
FAIL="${RED}✗ FAIL${NC}"
WARN="${YELLOW}⚠ WARN${NC}"
INFO="${BLUE}ℹ INFO${NC}"

echo "=========================================="
echo "  VPS Health Check"
echo "=========================================="
echo ""

TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNINGS=0

check_pass() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    echo -e "$PASS $1"
}

check_fail() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
    echo -e "$FAIL $1"
    [[ -n "$2" ]] && echo -e "      ${YELLOW}Fix: $2${NC}"
}

check_warn() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    WARNINGS=$((WARNINGS + 1))
    echo -e "$WARN $1"
    [[ -n "$2" ]] && echo -e "      ${YELLOW}Suggestion: $2${NC}"
}

check_info() {
    echo -e "$INFO $1"
}

#######################################
# System Information
#######################################
echo "📊 System Information"
echo "─────────────────────"
check_info "OS: $(uname -s) $(uname -r)"
check_info "Hostname: $(hostname)"
check_info "Uptime: $(uptime -p 2>/dev/null || uptime)"
check_info "Current User: $USER"
echo ""

#######################################
# User & Permissions
#######################################
echo "👤 User & Permissions"
echo "─────────────────────"

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    check_warn "Running as root" "Use a non-root user for daily operations"
else
    check_pass "Running as non-root user ($USER)"
fi

# Check sudo access
if sudo -n true 2>/dev/null; then
    check_pass "User has passwordless sudo"
elif groups | grep -q sudo || groups | grep -q wheel; then
    check_pass "User has sudo privileges"
else
    check_fail "User does not have sudo privileges" "Add user to sudo/wheel group"
fi

# Check docker group
if groups | grep -q docker; then
    check_pass "User is in docker group"
else
    check_warn "User not in docker group" "Run: sudo usermod -aG docker $USER && logout"
fi

echo ""

#######################################
# SSH Security
#######################################
echo "🔐 SSH Security"
echo "───────────────"

# Check root login
if sudo grep -q "^PermitRootLogin no" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/* 2>/dev/null; then
    check_pass "Root login disabled"
else
    check_fail "Root login NOT disabled" "Set 'PermitRootLogin no' in sshd_config"
fi

# Check password authentication
if sudo grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/* 2>/dev/null; then
    check_pass "Password authentication disabled (key-based only)"
elif sudo grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/* 2>/dev/null; then
    check_warn "Password authentication enabled" "Consider using SSH keys only"
fi

# Check SSH port
SSH_PORT=$(sudo grep -h "^Port " /etc/ssh/sshd_config /etc/ssh/sshd_config.d/* 2>/dev/null | awk '{print $2}' | head -1)
if [[ -n "$SSH_PORT" ]] && [[ "$SSH_PORT" != "22" ]]; then
    check_pass "SSH on custom port: $SSH_PORT"
else
    check_warn "SSH on default port 22" "Consider using custom port (e.g., 2222)"
fi

# Check if SSH is running
if systemctl is-active --quiet sshd || systemctl is-active --quiet ssh; then
    check_pass "SSH service is running"
else
    check_fail "SSH service not running" "Start with: sudo systemctl start sshd"
fi

echo ""

#######################################
# Firewall
#######################################
echo "🛡️  Firewall"
echo "───────────"

# Check UFW (Ubuntu/Debian)
if command -v ufw &> /dev/null; then
    if sudo ufw status | grep -q "Status: active"; then
        check_pass "UFW firewall is active"

        # Check if SSH port is allowed
        if [[ -n "$SSH_PORT" ]]; then
            if sudo ufw status | grep -q "$SSH_PORT"; then
                check_pass "SSH port $SSH_PORT allowed in firewall"
            else
                check_fail "SSH port $SSH_PORT NOT in firewall rules" "Run: sudo ufw allow $SSH_PORT/tcp"
            fi
        fi

    else
        check_fail "UFW firewall is inactive" "Enable with: sudo ufw enable"
    fi
# Check firewalld (CentOS/RHEL)
elif command -v firewall-cmd &> /dev/null; then
    if systemctl is-active --quiet firewalld; then
        check_pass "Firewalld is active"
    else
        check_fail "Firewalld is inactive" "Start with: sudo systemctl start firewalld"
    fi
else
    check_warn "No firewall detected (ufw/firewalld)" "Install and configure a firewall"
fi

echo ""

#######################################
# Fail2ban
#######################################
echo "🚫 Fail2ban"
echo "───────────"

if command -v fail2ban-client &> /dev/null; then
    if systemctl is-active --quiet fail2ban; then
        check_pass "Fail2ban is running"

        # Check SSH jail
        if sudo fail2ban-client status sshd &> /dev/null; then
            check_pass "SSH jail is active"
            BANNED=$(sudo fail2ban-client status sshd | grep "Currently banned" | awk '{print $NF}')
            check_info "Currently banned IPs: $BANNED"
        else
            check_warn "SSH jail not configured" "Configure in /etc/fail2ban/jail.local"
        fi
    else
        check_fail "Fail2ban installed but not running" "Start with: sudo systemctl start fail2ban"
    fi
else
    check_warn "Fail2ban not installed" "Install with: sudo apt install fail2ban"
fi

echo ""

#######################################
# Docker
#######################################
echo "🐳 Docker"
echo "─────────"

if command -v docker &> /dev/null; then
    check_pass "Docker is installed"
    check_info "Version: $(docker --version)"

    # Check if docker service is running
    if systemctl is-active --quiet docker; then
        check_pass "Docker service is running"
    else
        check_fail "Docker service not running" "Start with: sudo systemctl start docker"
    fi

    # Check docker compose
    if docker compose version &> /dev/null; then
        check_pass "Docker Compose v2 installed"
        check_info "Version: $(docker compose version --short)"
    else
        check_warn "Docker Compose v2 not found" "Install docker-compose-plugin"
    fi

    # Check if user can run docker without sudo
    if docker ps &> /dev/null; then
        check_pass "User can run Docker without sudo"
    else
        check_warn "Cannot run Docker without sudo" "Logout/login or run: newgrp docker"
    fi

    # Check running containers
    RUNNING_CONTAINERS=$(docker ps -q 2>/dev/null | wc -l)
    check_info "Running containers: $RUNNING_CONTAINERS"

else
    check_fail "Docker not installed" "Run docker-install-production.sh"
fi

echo ""

#######################################
# System Resources
#######################################
echo "💻 System Resources"
echo "───────────────────"

# Memory
TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
USED_MEM=$(free -m | awk '/^Mem:/{print $3}')
MEM_PERCENT=$((USED_MEM * 100 / TOTAL_MEM))

if [[ $MEM_PERCENT -lt 80 ]]; then
    check_pass "Memory usage: ${MEM_PERCENT}% (${USED_MEM}MB / ${TOTAL_MEM}MB)"
elif [[ $MEM_PERCENT -lt 90 ]]; then
    check_warn "Memory usage: ${MEM_PERCENT}% (${USED_MEM}MB / ${TOTAL_MEM}MB)" "Consider adding more RAM"
else
    check_fail "Memory usage: ${MEM_PERCENT}% (${USED_MEM}MB / ${TOTAL_MEM}MB)" "Memory critical!"
fi

# Disk
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
DISK_AVAIL=$(df -h / | awk 'NR==2 {print $4}')

if [[ $DISK_USAGE -lt 80 ]]; then
    check_pass "Disk usage: ${DISK_USAGE}% (${DISK_AVAIL} available)"
elif [[ $DISK_USAGE -lt 90 ]]; then
    check_warn "Disk usage: ${DISK_USAGE}% (${DISK_AVAIL} available)" "Clean up or add more storage"
else
    check_fail "Disk usage: ${DISK_USAGE}% (${DISK_AVAIL} available)" "Disk space critical!"
fi

# Load average
LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | xargs)
check_info "Load average: $LOAD_AVG"

# Check swap
if free | grep -q Swap; then
    SWAP_TOTAL=$(free -m | awk '/^Swap:/{print $2}')
    if [[ $SWAP_TOTAL -gt 0 ]]; then
        check_pass "Swap configured: ${SWAP_TOTAL}MB"
    else
        check_warn "No swap configured" "Consider adding swap for systems with <4GB RAM"
    fi
fi

echo ""

#######################################
# Updates & Security
#######################################
echo "🔄 Updates & Security"
echo "─────────────────────"

# Check automatic updates (Ubuntu/Debian)
if command -v unattended-upgrade &> /dev/null; then
    if systemctl is-active --quiet unattended-upgrades 2>/dev/null; then
        check_pass "Automatic updates enabled (unattended-upgrades)"
    else
        check_warn "unattended-upgrades installed but not active"
    fi
# Check yum-cron (CentOS/RHEL)
elif command -v yum-cron &> /dev/null; then
    if systemctl is-active --quiet yum-cron; then
        check_pass "Automatic updates enabled (yum-cron)"
    else
        check_warn "yum-cron installed but not active"
    fi
else
    check_warn "Automatic updates not configured" "Install unattended-upgrades or yum-cron"
fi

# Check for pending updates
if command -v apt &> /dev/null; then
    UPDATES=$(apt list --upgradable 2>/dev/null | grep -c upgradable || echo 0)
    if [[ $UPDATES -eq 0 ]]; then
        check_pass "System is up to date"
    else
        check_warn "$UPDATES updates available" "Run: sudo apt update && sudo apt upgrade"
    fi
elif command -v yum &> /dev/null; then
    UPDATES=$(yum check-update 2>/dev/null | grep -v "^$" | grep -v "Last metadata" | wc -l || echo 0)
    if [[ $UPDATES -eq 0 ]]; then
        check_pass "System is up to date"
    else
        check_warn "$UPDATES updates available" "Run: sudo yum update"
    fi
fi

echo ""

#######################################
# Network
#######################################
echo "🌐 Network"
echo "──────────"

# Check open ports
check_info "Listening ports:"
sudo netstat -tulpn 2>/dev/null | grep LISTEN | awk '{print "      " $4 " - " $7}' | head -10

echo ""

#######################################
# Summary
#######################################
echo "=========================================="
echo "  Summary"
echo "=========================================="
echo ""
echo "Total Checks: $TOTAL_CHECKS"
echo -e "${GREEN}Passed: $PASSED_CHECKS${NC}"
[[ $WARNINGS -gt 0 ]] && echo -e "${YELLOW}Warnings: $WARNINGS${NC}"
[[ $FAILED_CHECKS -gt 0 ]] && echo -e "${RED}Failed: $FAILED_CHECKS${NC}"
echo ""

if [[ $FAILED_CHECKS -eq 0 ]] && [[ $WARNINGS -eq 0 ]]; then
    echo -e "${GREEN}🎉 All checks passed! Your VPS is properly configured.${NC}"
    exit 0
elif [[ $FAILED_CHECKS -eq 0 ]]; then
    echo -e "${YELLOW}⚠️  Configuration OK but some improvements recommended.${NC}"
    exit 0
else
    echo -e "${RED}❌ Some critical issues found. Please address failed checks.${NC}"
    exit 1
fi
