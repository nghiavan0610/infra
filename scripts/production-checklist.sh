#!/bin/bash
# =============================================================================
# Production Readiness Checklist
# =============================================================================
# Run this before going to production to verify everything is configured.
#
# Usage:
#   bash scripts/production-checklist.sh
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS="${GREEN}✓${NC}"
FAIL="${RED}✗${NC}"
WARN="${YELLOW}!${NC}"
SKIP="${BLUE}-${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(dirname "$SCRIPT_DIR")"

# Counters
TOTAL=0
PASSED=0
FAILED=0
WARNINGS=0

check_pass() {
    ((TOTAL++))
    ((PASSED++))
    echo -e "  $PASS $1"
}

check_fail() {
    ((TOTAL++))
    ((FAILED++))
    echo -e "  $FAIL $1"
    [[ -n "$2" ]] && echo -e "      ${YELLOW}→ $2${NC}"
}

check_warn() {
    ((TOTAL++))
    ((WARNINGS++))
    echo -e "  $WARN $1"
    [[ -n "$2" ]] && echo -e "      ${YELLOW}→ $2${NC}"
}

check_skip() {
    echo -e "  $SKIP $1 (skipped)"
}

section() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

echo ""
echo "=========================================="
echo "  Production Readiness Checklist"
echo "=========================================="
echo "  Server: $(hostname)"
echo "  Date: $(date)"
echo "=========================================="

# =============================================================================
# 1. Security Checks
# =============================================================================
section "1. Security"

# Admin password set
if [[ -f "$INFRA_ROOT/.password_hash" ]]; then
    check_pass "Admin password configured"
else
    check_fail "Admin password not set" "./setup.sh --set-password"
fi

# File permissions
INFRA_PERMS=$(stat -c "%a" "$INFRA_ROOT" 2>/dev/null || stat -f "%OLp" "$INFRA_ROOT")
if [[ "$INFRA_PERMS" == "700" ]] || [[ "$INFRA_PERMS" == "750" ]]; then
    check_pass "Directory permissions secured ($INFRA_PERMS)"
else
    check_fail "Directory too open ($INFRA_PERMS)" "./secure.sh"
fi

# .secrets file permissions
if [[ -f "$INFRA_ROOT/.secrets" ]]; then
    SECRET_PERMS=$(stat -c "%a" "$INFRA_ROOT/.secrets" 2>/dev/null || stat -f "%OLp" "$INFRA_ROOT/.secrets")
    if [[ "$SECRET_PERMS" == "600" ]]; then
        check_pass ".secrets file secured (600)"
    else
        check_warn ".secrets file permissions ($SECRET_PERMS)" "./secure.sh"
    fi
fi

# SSH root login disabled
if grep -q "^PermitRootLogin no" /etc/ssh/sshd_config 2>/dev/null || \
   grep -q "^PermitRootLogin no" /etc/ssh/sshd_config.d/*.conf 2>/dev/null; then
    check_pass "SSH root login disabled"
else
    check_warn "SSH root login may be enabled" "Run vps-initial-setup.sh"
fi

# Firewall enabled
if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
    check_pass "Firewall (UFW) enabled"
elif command -v firewall-cmd &>/dev/null && firewall-cmd --state 2>/dev/null | grep -q "running"; then
    check_pass "Firewall (firewalld) enabled"
else
    check_warn "Firewall may not be enabled" "sudo ufw enable"
fi

# Fail2ban or Crowdsec
if systemctl is-active --quiet fail2ban 2>/dev/null; then
    check_pass "Fail2ban running"
elif docker ps --format '{{.Names}}' 2>/dev/null | grep -q "crowdsec"; then
    check_pass "Crowdsec running"
else
    check_warn "No brute-force protection detected" "Enable fail2ban or crowdsec"
fi

# Docker group check
DOCKER_USERS=$(getent group docker 2>/dev/null | cut -d: -f4 | tr ',' '\n' | grep -c . || echo 0)
if [[ $DOCKER_USERS -le 2 ]]; then
    check_pass "Docker access limited ($DOCKER_USERS users)"
else
    check_warn "Multiple users have Docker access ($DOCKER_USERS)" "Review with audit-access.sh"
fi

# =============================================================================
# 2. Services Running
# =============================================================================
section "2. Core Services"

# Check key containers
check_container() {
    local name=$1
    local required=$2
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${name}$"; then
        local health=$(docker inspect --format='{{.State.Health.Status}}' "$name" 2>/dev/null || echo "none")
        if [[ "$health" == "healthy" ]] || [[ "$health" == "none" ]]; then
            check_pass "$name running"
        else
            check_warn "$name running but unhealthy ($health)"
        fi
    else
        if [[ "$required" == "required" ]]; then
            check_fail "$name not running" "Check services.conf and run ./setup.sh"
        else
            check_skip "$name"
        fi
    fi
}

# Check enabled services from services.conf
if [[ -f "$INFRA_ROOT/services.conf" ]]; then
    grep -q "^postgres=true" "$INFRA_ROOT/services.conf" && check_container "postgres" "required"
    grep -q "^postgres-ha=true" "$INFRA_ROOT/services.conf" && check_container "postgres-master" "required"
    grep -q "^redis=true" "$INFRA_ROOT/services.conf" && check_container "redis-cache" "required"
    grep -q "^traefik=true" "$INFRA_ROOT/services.conf" && check_container "traefik" "required"
    grep -q "^observability=true" "$INFRA_ROOT/services.conf" && check_container "grafana" "required"
fi

# =============================================================================
# 3. Backups
# =============================================================================
section "3. Backups"

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "backup"; then
    check_pass "Backup service running"

    # Check if backup is configured
    if [[ -f "$INFRA_ROOT/services/backup/.env" ]]; then
        if grep -q "^RESTIC_PASSWORD=.\+" "$INFRA_ROOT/services/backup/.env" 2>/dev/null; then
            check_pass "Backup password configured"
        else
            check_fail "Backup password not set" "Edit services/backup/.env"
        fi

        if grep -q "^RESTIC_REPOSITORY=.\+" "$INFRA_ROOT/services/backup/.env" 2>/dev/null; then
            check_pass "Backup repository configured"
        else
            check_fail "Backup repository not set" "Edit services/backup/.env"
        fi
    fi
else
    if grep -q "^backup=true" "$INFRA_ROOT/services.conf" 2>/dev/null; then
        check_fail "Backup enabled but not running" "./setup.sh"
    else
        check_warn "Backup service not enabled" "Set backup=true in services.conf"
    fi
fi

# =============================================================================
# 4. Monitoring & Alerts
# =============================================================================
section "4. Monitoring & Alerts"

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "prometheus"; then
    check_pass "Prometheus running"
else
    check_warn "Prometheus not running" "Enable observability in services.conf"
fi

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "grafana"; then
    check_pass "Grafana running"
else
    check_warn "Grafana not running"
fi

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "alertmanager"; then
    check_pass "Alertmanager running"

    # Check alert destination
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "ntfy"; then
        check_pass "Ntfy running (push notifications)"
    else
        check_warn "No push notification service" "Enable ntfy for alerts"
    fi
else
    check_warn "Alertmanager not running"
fi

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "loki"; then
    check_pass "Loki running (log aggregation)"
else
    check_warn "Loki not running (no centralized logs)"
fi

# =============================================================================
# 5. SSL/TLS
# =============================================================================
section "5. SSL/TLS"

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "traefik"; then
    # Check if ACME is configured
    if [[ -f "$INFRA_ROOT/services/traefik/.env" ]]; then
        if grep -q "^TRAEFIK_ACME_EMAIL=.\+@.\+" "$INFRA_ROOT/services/traefik/.env" 2>/dev/null; then
            check_pass "Let's Encrypt email configured"
        else
            check_warn "Let's Encrypt email not set" "Edit services/traefik/.env"
        fi
    fi

    # Check acme.json exists
    if [[ -f "$INFRA_ROOT/services/traefik/certs/acme.json" ]]; then
        check_pass "ACME certificate store exists"
    else
        check_warn "ACME certificate store missing" "Will be created on first request"
    fi
else
    check_skip "Traefik not running"
fi

# =============================================================================
# 6. Resources
# =============================================================================
section "6. System Resources"

# Disk space
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
if [[ $DISK_USAGE -lt 70 ]]; then
    check_pass "Disk usage OK (${DISK_USAGE}%)"
elif [[ $DISK_USAGE -lt 85 ]]; then
    check_warn "Disk usage high (${DISK_USAGE}%)" "Consider cleanup or expansion"
else
    check_fail "Disk usage critical (${DISK_USAGE}%)" "Immediate action needed"
fi

# Memory
MEM_USAGE=$(free | awk '/Mem:/ {printf "%.0f", $3/$2 * 100}')
if [[ $MEM_USAGE -lt 80 ]]; then
    check_pass "Memory usage OK (${MEM_USAGE}%)"
elif [[ $MEM_USAGE -lt 90 ]]; then
    check_warn "Memory usage high (${MEM_USAGE}%)"
else
    check_fail "Memory usage critical (${MEM_USAGE}%)"
fi

# Docker disk usage
DOCKER_USAGE=$(docker system df --format '{{.Size}}' 2>/dev/null | head -1 || echo "unknown")
echo -e "  ${BLUE}ℹ${NC} Docker disk usage: $DOCKER_USAGE"

# =============================================================================
# 7. Updates
# =============================================================================
section "7. Updates"

# Auto-updates
if systemctl is-active --quiet unattended-upgrades 2>/dev/null; then
    check_pass "Auto security updates enabled (apt)"
elif systemctl is-active --quiet dnf-automatic.timer 2>/dev/null; then
    check_pass "Auto security updates enabled (dnf)"
else
    check_warn "Auto security updates may not be enabled"
fi

# Docker images
OUTDATED=$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -v '<none>' | head -5)
echo -e "  ${BLUE}ℹ${NC} Run 'docker compose pull' periodically to update images"

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=========================================="
echo "  Summary"
echo "=========================================="
echo ""
echo -e "  Total checks: $TOTAL"
echo -e "  ${GREEN}Passed: $PASSED${NC}"
echo -e "  ${RED}Failed: $FAILED${NC}"
echo -e "  ${YELLOW}Warnings: $WARNINGS${NC}"
echo ""

if [[ $FAILED -gt 0 ]]; then
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}  NOT READY FOR PRODUCTION${NC}"
    echo -e "${RED}  Fix the failed checks above before going live.${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    exit 1
elif [[ $WARNINGS -gt 3 ]]; then
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  REVIEW WARNINGS${NC}"
    echo -e "${YELLOW}  Consider addressing warnings for better security.${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    exit 0
else
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  READY FOR PRODUCTION${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    exit 0
fi
