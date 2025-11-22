#!/bin/bash

#######################################
# VPS Initial Setup Script for Production
# Run this FIRST when you get a fresh VPS
# Features: User creation, SSH hardening, firewall, fail2ban, updates
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
   log_error "This script must be run as root (first time setup)"
   log_info "Run: sudo bash vps-initial-setup.sh"
   exit 1
fi

echo "=========================================="
echo "  VPS Initial Setup for Production"
echo "=========================================="
echo ""

#######################################
# Configuration Variables
#######################################
read -p "Enter new sudo username: " NEW_USER
read -s -p "Enter password for $NEW_USER: " NEW_PASSWORD
echo ""
read -s -p "Confirm password: " NEW_PASSWORD_CONFIRM
echo ""

if [[ "$NEW_PASSWORD" != "$NEW_PASSWORD_CONFIRM" ]]; then
    log_error "Passwords do not match"
    exit 1
fi

read -p "Enter SSH port (default 22, recommended: 2222): " SSH_PORT
SSH_PORT=${SSH_PORT:-2222}

read -p "Paste your SSH public key (for key-based auth): " SSH_PUBLIC_KEY

if [[ -z "$SSH_PUBLIC_KEY" ]]; then
    log_warn "No SSH key provided. You should use SSH keys for better security."
    read -p "Continue without SSH key? (y/n): " CONTINUE
    if [[ "$CONTINUE" != "y" ]]; then
        exit 1
    fi
fi

#######################################
# Detect OS
#######################################
log_step "Detecting operating system..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    log_info "Detected: $OS"
else
    log_error "Cannot detect OS"
    exit 1
fi

#######################################
# Update system
#######################################
log_step "Updating system packages..."
if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
    apt-get update
    apt-get upgrade -y
    apt-get install -y curl wget vim git ufw fail2ban unattended-upgrades
elif [[ "$OS" == "centos" ]] || [[ "$OS" == "rhel" ]] || [[ "$OS" == "amzn" ]]; then
    yum update -y
    yum install -y curl wget vim git firewalld fail2ban
fi
log_info "System updated"

#######################################
# Create new sudo user
#######################################
log_step "Creating new user: $NEW_USER"

# Check if user exists
if id "$NEW_USER" &>/dev/null; then
    log_warn "User $NEW_USER already exists"
else
    useradd -m -s /bin/bash "$NEW_USER"
    echo "$NEW_USER:$NEW_PASSWORD" | chpasswd
    usermod -aG sudo "$NEW_USER" 2>/dev/null || usermod -aG wheel "$NEW_USER"
    log_info "User $NEW_USER created with sudo privileges"
fi

#######################################
# Setup SSH key authentication
#######################################
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
    log_step "Setting up SSH key authentication for $NEW_USER"

    USER_HOME=$(eval echo ~$NEW_USER)
    mkdir -p "$USER_HOME/.ssh"
    echo "$SSH_PUBLIC_KEY" > "$USER_HOME/.ssh/authorized_keys"
    chmod 700 "$USER_HOME/.ssh"
    chmod 600 "$USER_HOME/.ssh/authorized_keys"
    chown -R "$NEW_USER:$NEW_USER" "$USER_HOME/.ssh"

    log_info "SSH key configured"
fi

#######################################
# Harden SSH configuration
#######################################
log_step "Hardening SSH configuration..."

# Backup original config
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%F_%T)

# Apply hardened SSH settings
cat > /etc/ssh/sshd_config.d/hardening.conf <<EOF
# SSH Hardening Configuration
Port $SSH_PORT
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries 3
MaxSessions 10
Protocol 2
EOF

# If SSH key is provided, disable password authentication
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
    sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config.d/hardening.conf
    log_info "SSH password authentication disabled (key-based only)"
fi

# Restart SSH (don't disconnect current session)
systemctl restart sshd || systemctl restart ssh

log_info "SSH hardened - New port: $SSH_PORT"
log_warn "IMPORTANT: Test SSH connection in a NEW terminal before closing this one!"
log_warn "Connect with: ssh -p $SSH_PORT $NEW_USER@YOUR_SERVER_IP"

#######################################
# Configure firewall
#######################################
log_step "Configuring firewall..."

if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
    # UFW setup
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow $SSH_PORT/tcp comment 'SSH'
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    ufw --force enable
    ufw status
    log_info "UFW firewall configured"

elif [[ "$OS" == "centos" ]] || [[ "$OS" == "rhel" ]] || [[ "$OS" == "amzn" ]]; then
    # Firewalld setup
    systemctl start firewalld
    systemctl enable firewalld
    firewall-cmd --permanent --zone=public --add-port=$SSH_PORT/tcp
    firewall-cmd --permanent --zone=public --add-service=http
    firewall-cmd --permanent --zone=public --add-service=https
    firewall-cmd --reload
    log_info "Firewalld configured"
fi

#######################################
# Configure fail2ban
#######################################
log_step "Configuring fail2ban for SSH protection..."

cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
destemail = root@localhost
sendername = Fail2Ban
action = %(action_mwl)s

[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
EOF

# For RHEL-based systems
if [[ "$OS" == "centos" ]] || [[ "$OS" == "rhel" ]] || [[ "$OS" == "amzn" ]]; then
    sed -i 's|/var/log/auth.log|/var/log/secure|' /etc/fail2ban/jail.local
fi

systemctl enable fail2ban
systemctl restart fail2ban

log_info "Fail2ban configured (3 failed attempts = 1 hour ban)"

#######################################
# Enable automatic security updates
#######################################
log_step "Configuring automatic security updates..."

if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
    cat > /etc/apt/apt.conf.d/50unattended-upgrades <<EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

    cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

    log_info "Automatic security updates enabled"
elif [[ "$OS" == "centos" ]] || [[ "$OS" == "rhel" ]] || [[ "$OS" == "amzn" ]]; then
    yum install -y yum-cron
    systemctl enable yum-cron
    systemctl start yum-cron
    log_info "Automatic security updates enabled (yum-cron)"
fi

#######################################
# Set timezone to UTC
#######################################
log_step "Setting timezone to UTC..."
timedatectl set-timezone UTC
log_info "Timezone set to UTC"

#######################################
# Configure system limits
#######################################
log_step "Configuring system limits for production..."

cat >> /etc/security/limits.conf <<EOF

# Production system limits
* soft nofile 65536
* hard nofile 65536
* soft nproc 32768
* hard nproc 32768
EOF

# Sysctl optimizations
cat >> /etc/sysctl.conf <<EOF

# Network optimizations
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15

# Security
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Memory
vm.swappiness = 10
vm.vfs_cache_pressure = 50
EOF

sysctl -p >/dev/null

log_info "System limits configured for production"

#######################################
# Create helpful aliases and motd
#######################################
log_step "Setting up helpful aliases..."

cat >> "$USER_HOME/.bashrc" <<'EOF'

# Custom aliases for Docker and system management
alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
alias dlog='docker logs -f'
alias dstop='docker stop $(docker ps -q)'
alias dclean='docker system prune -af'
alias update='sudo apt update && sudo apt upgrade -y'  # Change for yum if needed
alias ports='sudo netstat -tulpn | grep LISTEN'
alias meminfo='free -h'
alias cpuinfo='top -bn1 | grep "Cpu(s)"'
EOF

chown "$NEW_USER:$NEW_USER" "$USER_HOME/.bashrc"

log_info "Helpful aliases added to .bashrc"

#######################################
# Display summary
#######################################
echo ""
echo "=========================================="
log_info "VPS Initial Setup Complete!"
echo "=========================================="
echo ""
log_info "Configuration Summary:"
echo "  - New user: $NEW_USER (with sudo access)"
echo "  - SSH port: $SSH_PORT"
echo "  - Root login: DISABLED"
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
echo "  - SSH auth: KEY-BASED ONLY"
else
echo "  - SSH auth: PASSWORD (consider adding SSH key)"
fi
echo "  - Firewall: ENABLED (ports $SSH_PORT, 80, 443)"
echo "  - Fail2ban: ENABLED"
echo "  - Auto updates: ENABLED"
echo "  - Timezone: UTC"
echo ""
log_warn "CRITICAL NEXT STEPS:"
echo "  1. Open a NEW terminal and test SSH connection:"
echo "     ssh -p $SSH_PORT $NEW_USER@YOUR_SERVER_IP"
echo ""
echo "  2. Verify you can login and use sudo:"
echo "     sudo whoami"
echo ""
echo "  3. ONLY after successful test, close this root session"
echo ""
log_info "After verifying access, you can run:"
echo "  - Docker installation: ./docker-install-production.sh"
echo "  - View fail2ban status: sudo fail2ban-client status sshd"
echo "  - View firewall rules: sudo ufw status (or firewall-cmd --list-all)"
echo "  - Check system resources: htop (install with: apt install htop)"
echo ""
log_warn "Keep this terminal open until you verify new SSH access!"
echo "=========================================="
