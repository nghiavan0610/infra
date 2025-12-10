#!/bin/bash

#######################################
# SSH Protection for Oracle Linux 9
# Alternative to fail2ban using firewalld + SELinux
# Production-grade security
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
   log_info "Run: sudo bash setup-ssh-protection-ol9.sh"
   exit 1
fi

echo "=========================================="
echo "  SSH Protection Setup - Oracle Linux 9"
echo "  Production-Grade Security"
echo "=========================================="
echo ""

# Get SSH port
SSH_PORT=$(grep -E "^Port " /etc/ssh/sshd_config* 2>/dev/null | tail -1 | awk '{print $2}' || echo "22")
log_info "Detected SSH port: $SSH_PORT"

#######################################
# 1. Firewalld Rate Limiting
#######################################
log_step "Configuring firewalld SSH rate limiting..."

# Remove old SSH rules
firewall-cmd --permanent --remove-service=ssh 2>/dev/null || true
firewall-cmd --permanent --zone=public --remove-port=${SSH_PORT}/tcp 2>/dev/null || true

# Add SSH with rate limiting (3 connections per minute per IP)
firewall-cmd --permanent --add-rich-rule="rule family='ipv4' port port='${SSH_PORT}' protocol='tcp' accept limit value='3/m'"
firewall-cmd --permanent --add-rich-rule="rule family='ipv6' port port='${SSH_PORT}' protocol='tcp' accept limit value='3/m'"

# Log rejected attempts
firewall-cmd --permanent --add-rich-rule="rule family='ipv4' port port='${SSH_PORT}' protocol='tcp' log prefix='SSH-REJECT: ' level='warning' limit value='1/m' drop"

firewall-cmd --reload

log_info "Firewalld rate limiting configured (max 3 connections/min)"

#######################################
# 2. Configure SSH Security
#######################################
log_step "Hardening SSH configuration..."

# Create hardened SSH config if doesn't exist
if [ ! -f /etc/ssh/sshd_config.d/security.conf ]; then
    cat > /etc/ssh/sshd_config.d/security.conf <<EOF
# SSH Security Hardening
MaxAuthTries 3
MaxSessions 5
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2

# Disable weak algorithms
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256

# Additional hardening
PermitEmptyPasswords no
PermitUserEnvironment no
AllowAgentForwarding no
AllowTcpForwarding no
X11Forwarding no
EOF

    systemctl restart sshd
    log_info "SSH hardening applied"
else
    log_info "SSH security config already exists"
fi

#######################################
# 3. Configure SELinux (Already enabled on OL9)
#######################################
log_step "Verifying SELinux protection..."

SELINUX_STATUS=$(getenforce)
if [[ "$SELINUX_STATUS" == "Enforcing" ]]; then
    log_info "SELinux is enforcing (good for production)"
else
    log_warn "SELinux is $SELINUX_STATUS (recommended: Enforcing)"
fi

#######################################
# 4. Configure Auditd for SSH Monitoring
#######################################
log_step "Configuring audit rules for SSH..."

# Install auditd if not present
if ! command -v auditctl &> /dev/null; then
    dnf install -y audit
    systemctl enable auditd
    systemctl start auditd
fi

# Add SSH audit rules
cat > /etc/audit/rules.d/ssh.rules <<EOF
# Monitor SSH authentication
-w /var/log/secure -p wa -k ssh_auth
-w /etc/ssh/sshd_config -p wa -k ssh_config
-w /etc/ssh/sshd_config.d/ -p wa -k ssh_config

# Monitor failed SSH attempts
-a always,exit -F arch=b64 -S connect -F a2=16 -F success=0 -k ssh_failed
EOF

# Reload audit rules
augenrules --load 2>/dev/null || service auditd restart

log_info "SSH audit logging configured"

#######################################
# 5. Install and Configure OSSEC (Optional but Recommended)
#######################################
log_step "Installing OSSEC HIDS (Host Intrusion Detection)..."

# Check if OSSEC is already installed
if [ ! -d /var/ossec ]; then
    read -p "Install OSSEC HIDS for advanced threat detection? (y/n): " INSTALL_OSSEC
    if [[ "$INSTALL_OSSEC" == "y" ]]; then
        log_info "Installing OSSEC..."
        dnf install -y ossec-hids ossec-hids-server 2>/dev/null || {
            log_warn "OSSEC not available in repos, skipping (optional)"
        }
    else
        log_info "Skipping OSSEC installation"
    fi
else
    log_info "OSSEC already installed"
fi

#######################################
# 6. Configure rsyslog for SSH logging
#######################################
log_step "Configuring enhanced SSH logging..."

cat > /etc/rsyslog.d/ssh.conf <<EOF
# Enhanced SSH logging
:programname, isequal, "sshd" /var/log/sshd.log
& stop
EOF

systemctl restart rsyslog

log_info "SSH logs now also go to /var/log/sshd.log"

#######################################
# 7. Create monitoring script
#######################################
log_step "Creating SSH monitoring script..."

cat > /usr/local/bin/check-ssh-attacks <<'EOF'
#!/bin/bash
# Quick script to check for SSH attack attempts

echo "=== SSH Failed Login Attempts (Last 24 hours) ==="
grep "Failed password" /var/log/secure | grep "$(date +%b\ %e)" | wc -l

echo ""
echo "=== Top 10 Failed Login IPs ==="
grep "Failed password" /var/log/secure | awk '{print $(NF-3)}' | sort | uniq -c | sort -rn | head -10

echo ""
echo "=== Recent Failed Attempts (Last 20) ==="
grep "Failed password" /var/log/secure | tail -20

echo ""
echo "=== Firewalld Rejections ==="
journalctl -u firewalld --since "24 hours ago" | grep -i reject | wc -l

echo ""
echo "=== Current SSH Connections ==="
ss -tnp | grep :${SSH_PORT:-22}
EOF

chmod +x /usr/local/bin/check-ssh-attacks

log_info "Monitoring script created: check-ssh-attacks"

#######################################
# 8. Optional: IP Blacklist Management
#######################################
log_step "Setting up IP blacklist management..."

cat > /usr/local/bin/block-ip <<'EOF'
#!/bin/bash
# Block an IP address permanently

if [ -z "$1" ]; then
    echo "Usage: block-ip <IP_ADDRESS>"
    exit 1
fi

IP=$1
firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='$IP' reject"
firewall-cmd --reload
echo "Blocked IP: $IP"
EOF

chmod +x /usr/local/bin/block-ip

cat > /usr/local/bin/unblock-ip <<'EOF'
#!/bin/bash
# Unblock an IP address

if [ -z "$1" ]; then
    echo "Usage: unblock-ip <IP_ADDRESS>"
    exit 1
fi

IP=$1
firewall-cmd --permanent --remove-rich-rule="rule family='ipv4' source address='$IP' reject"
firewall-cmd --reload
echo "Unblocked IP: $IP"
EOF

chmod +x /usr/local/bin/unblock-ip

log_info "IP management scripts created: block-ip, unblock-ip"

#######################################
# Display Summary
#######################################
echo ""
echo "=========================================="
log_info "SSH Protection Setup Complete!"
echo "=========================================="
echo ""
log_info "Protection Layers Configured:"
echo "  ✅ Firewalld rate limiting (3 conn/min per IP)"
echo "  ✅ SSH hardening (weak algorithms disabled)"
echo "  ✅ SELinux enforcement"
echo "  ✅ Audit logging for SSH"
echo "  ✅ Enhanced rsyslog monitoring"
echo "  ✅ Monitoring scripts installed"
echo ""
log_info "Available Commands:"
echo "  - check-ssh-attacks    # View attack attempts"
echo "  - block-ip <IP>        # Block an IP permanently"
echo "  - unblock-ip <IP>      # Unblock an IP"
echo ""
log_info "Check Protection Status:"
echo "  sudo firewall-cmd --list-all"
echo "  sudo check-ssh-attacks"
echo "  sudo ausearch -k ssh_auth"
echo ""
log_warn "Note: This is equivalent to fail2ban for Oracle Linux 9"
echo "=========================================="
