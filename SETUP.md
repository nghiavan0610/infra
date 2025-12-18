# Infrastructure Setup Guide

Complete step-by-step guide for setting up infrastructure on a fresh VPS.

## Quick Start (Experienced Users)

```bash
# 1. SSH to fresh VPS (as opc on Oracle Cloud, or root on others)
ssh opc@your-server-ip

# 2. Setup GitHub SSH key (see Step 0 below), then clone
sudo mkdir -p /opt/infra && sudo chown $USER:$USER /opt/infra
git clone git@github.com:nghiavan0610/infra.git /opt/infra
cd /opt/infra

# 3. Harden the system (SSH port, firewall, fail2ban)
sudo bash scripts/vps-initial-setup.sh

# 4. In NEW terminal, test SSH with new port
ssh -p 2222 opc@your-server-ip
cd /opt/infra

# 5. Install Docker (adds current user to docker group)
bash scripts/docker-install.sh
exit  # Logout to apply docker group

# 6. Login again and start services
ssh -p 2222 opc@your-server-ip
cd /opt/infra
./test.sh                    # Validate
nano services.conf           # Enable services
./setup.sh --set-password    # Set admin password
./setup.sh                   # Start services
./status.sh                  # Verify

# 7. Secure and add users
./secure.sh                              # Secure file permissions
sudo bash scripts/add-user.sh            # Create Infra Admin (type 3)
sudo bash scripts/audit-access.sh        # Check who has access
```

---

## Prerequisites

- Fresh VPS with Ubuntu 22.04/24.04, Debian 12, or Oracle Linux 9
- Root access
- Minimum 2GB RAM, 2 CPU cores, 40GB disk
- SSH public key (recommended)
- Domain name (optional, for SSL)
- GitHub SSH key (for private repo access)

## Step 0: Setup GitHub SSH Key (Required for Private Repo)

Before cloning, you need to set up SSH key authentication with GitHub.

### 0.1 Generate SSH Key on Server

```bash
ssh-keygen -t ed25519 -C "deploy@$(hostname)"
# Press Enter to accept default location
# Press Enter for no passphrase (or set one)
```

### 0.2 Copy the Public Key

```bash
cat ~/.ssh/id_ed25519.pub
```

### 0.3 Add Key to GitHub

1. Go to https://github.com/settings/keys
2. Click "New SSH key"
3. Title: `deploy@your-server-name`
4. Paste the public key
5. Click "Add SSH key"

### 0.4 Test Connection

```bash
ssh -T git@github.com
# Should see: "Hi nghiavan0610! You've successfully authenticated..."
```

## Step 1: Initial Server Setup (System Hardening)

### 1.1 Login to Your VPS

```bash
# Oracle Cloud uses 'opc' user
ssh opc@your-server-ip

# Other providers may use 'root' or another default user
ssh root@your-server-ip
```

### 1.2 Clone Repository and Run VPS Setup Script

```bash
# Clone the repo
sudo mkdir -p /opt/infra && sudo chown $USER:$USER /opt/infra
git clone git@github.com:nghiavan0610/infra.git /opt/infra
cd /opt/infra

# Run the VPS setup script (system hardening only)
sudo bash scripts/vps-initial-setup.sh
```

### 1.3 What the Script Does

The script will prompt you for:
- **SSH Port**: Custom SSH port (default: 2222, recommended for security)
- **SSH Key**: Option to add/update SSH key for current user
- **Root Login**: Whether to disable root SSH login

The script automatically configures:
- SSH hardening (custom port, security settings)
- Firewall (UFW or firewalld) with ports 80, 443, SSH
- Fail2ban for brute-force protection
- Automatic security updates
- System limits optimized for production
- Timezone set to UTC
- Helpful shell aliases

**Note**: User creation is handled separately by `add-user.sh` after Docker is installed.

### 1.4 After Script Completes

**IMPORTANT**: Test SSH in a NEW terminal before closing the current session!

```bash
# In a NEW terminal, test the new connection with new port
ssh -p 2222 opc@your-server-ip

# Verify sudo works
sudo whoami
```

Only close the original terminal after confirming you can connect with the new SSH port.

## Step 2: Install Docker

### 2.1 Login with New SSH Port

```bash
# Use the SSH port you configured (default: 2222)
ssh -p 2222 opc@your-server-ip
cd /opt/infra
```

### 2.2 Run Docker Install Script

```bash
bash scripts/docker-install.sh
```

The script automatically:
- Installs Docker CE and Docker Compose plugin
- Configures Docker daemon for production
- Adds current user to `docker` group

### 2.3 Logout and Login Again

```bash
# IMPORTANT: Logout to apply docker group
exit

# Login again
ssh -p 2222 opc@your-server-ip
cd /opt/infra
```

### 2.4 Verify Installation

```bash
# Check versions
docker --version
docker compose version

# Test docker works (no sudo needed!)
docker run --rm hello-world
```

## Step 3: Validate Configuration

```bash
cd /opt/infra

# Make scripts executable
chmod +x setup.sh stop.sh status.sh test.sh

# Run validation tests
./test.sh
```

Expected output:
```
[PASS] Docker installed
[PASS] Docker Compose installed
[PASS] All compose files valid
...
ALL TESTS PASSED!
```

## Step 4: Configure Services

### 4.1 Choose Services

Edit `services.conf` to enable services you need:

```bash
nano services.conf
```

### 4.2 Service Presets

**Minimal (recommended to start):**
```ini
# Networking
traefik=true

# Databases
postgres=true
redis=true

# Monitoring
observability=true
```

**Standard (production):**
```ini
# Networking
traefik=true

# Databases
postgres=true
redis=true

# Storage
garage=true

# Security
fail2ban=true
crowdsec=true

# Monitoring
observability=true
uptime-kuma=true
backup=true
```

**With AI/LLM support:**
```ini
# Add to standard:
langfuse=true
```

## Step 5: Start Services

### 5.1 Set Admin Password

```bash
./setup.sh --set-password
# Enter a strong password when prompted
```

### 5.2 Start Services

```bash
# Start services from services.conf
./setup.sh

# Or use a preset
./setup.sh --minimal
./setup.sh --standard
```

### 5.3 Verify Services Running

```bash
./status.sh
```

Expected output:
```
Databases:
  ● PostgreSQL (healthy)
  ● Redis Cache (healthy)
  ● Redis Queue (healthy)

Monitoring & Tools:
  ● Prometheus (healthy)
  ● Grafana (healthy)
  ...
```

## Step 6: Secure Infrastructure

### 6.1 Secure File Permissions

```bash
cd /opt/infra

# Secure for your user only (strictest)
./secure.sh

# Or secure for a group of admins
./secure.sh --group infra-admins

# Check current permissions
./secure.sh --check
```

This sets:
- Directories: `700` (owner only)
- Scripts: `700` (owner execute only)
- Config files: `644` (readable by Docker containers)
- Sensitive files (.env, .secrets): `600` (owner only)

### 6.2 Audit Current Access

```bash
sudo bash scripts/audit-access.sh
```

This shows:
- Users in docker group (can control ALL containers)
- Users with sudo access
- Infrastructure directory permissions
- Security recommendations

### 6.3 Add Team Members

Use the appropriate user type for each team member:

```bash
sudo bash scripts/add-user.sh
```

**User Types:**

| Type | SSH | Sudo | Docker | Use Case |
|------|-----|------|--------|----------|
| **1) Developer** | ✅ | ❌ | ❌ | App deployment only |
| **2) DevOps** | ✅ | ✅ | ❌ | System management (NO Docker) |
| **3) Infra Admin** | ✅ | ✅ | ✅ | Full infrastructure control |
| **4) Tunnel Only** | tunnel | ❌ | ❌ | DB access from local (no shell) |

**Important Security Notes:**

- **Developer**: Can SSH and deploy apps, but cannot access databases or containers directly
- **DevOps**: Can manage system (packages, firewall, etc.) but CANNOT control Docker containers
- **Infra Admin**: Full access - only grant to trusted administrators
- **Tunnel Only**: Can only create SSH tunnels, cannot execute any commands on the server

```bash
# Example: Add a developer
sudo bash scripts/add-user.sh
# Select: 1) Developer
# Enter username: alice
# Paste SSH key

# Example: Add an infra admin (requires confirmation)
sudo bash scripts/add-user.sh
# Select: 3) Infra Admin
# Type "yes" to confirm

# Example: Add a tunnel-only user for dev partner
sudo bash scripts/add-user.sh
# Select: 4) Tunnel Only
# Enter username and paste SSH key
```

### 6.4 Dev Partner Access (SSH Tunnel)

Allow dev partners to access production databases from their local machine:

```bash
# 1. Add tunnel-only user (on server)
sudo bash scripts/add-user.sh
# Select: 4) Tunnel Only
# Enter username (e.g., dev-partner)
# Paste their SSH public key
```

**Dev partner runs on their local machine:**

```bash
# Create SSH tunnel
ssh -N -p 2222 \
    -L 5432:localhost:5432 \
    -L 6379:localhost:6379 \
    -L 6380:localhost:6380 \
    dev-partner@your-server-ip

# In another terminal, connect to services
psql -h localhost -p 5432 -U postgres
redis-cli -h localhost -p 6379
```

**What tunnel-only users can do:**
- Create SSH tunnels to PostgreSQL, Redis, etc.
- Connect to databases from their local machine

**What tunnel-only users CANNOT do:**
- Execute any commands on the server
- Get a shell session
- Access files on the server
- Control Docker containers

### 6.5 Remove Docker Access from User

If you need to downgrade a user's access:

```bash
# Remove from docker group
sudo gpasswd -d username docker

# User must logout and login for changes to take effect
```

---

## Step 7: Access Services

### 7.1 Get Credentials

```bash
cat .secrets
```

### 7.2 Access URLs

| Service | URL | Notes |
|---------|-----|-------|
| Grafana | http://your-ip:3000 | Dashboards & monitoring |
| Prometheus | http://your-ip:9090 | Metrics |
| Traefik | http://your-ip:8080 | Reverse proxy dashboard |
| Uptime Kuma | http://your-ip:3001 | Status page |
| LangFuse | http://your-ip:3050 | LLM observability |

### 7.3 Default Ports

| Service | Port |
|---------|------|
| PostgreSQL | 5432 |
| Redis Cache | 6379 |
| Redis Queue | 6380 |
| MongoDB | 27017 |
| MySQL | 3306 |

## Step 8: Create Database for Your App

Use the unified `db-cli.sh` to manage users across all database types.

### 8.1 Database CLI Overview

```bash
# Syntax
./lib/db-cli.sh <database-type> <command> [args...]

# Or use the symlink
./scripts/db-cli.sh <database-type> <command> [args...]
```

**Supported Database Types:**

| Type | Container | Description |
|------|-----------|-------------|
| `postgres` | postgres | PostgreSQL single node |
| `postgres-ha` | postgres-master | PostgreSQL with replica |
| `timescaledb` | timescaledb | TimescaleDB (time-series) |
| `mysql` | mysql | MySQL 8.0 |
| `mongo` | mongo | MongoDB replica set |
| `clickhouse` | clickhouse | ClickHouse (analytics) |

### 8.2 Create Users

```bash
# PostgreSQL
./lib/db-cli.sh postgres create-user myapp secretpass123 myapp_db
# Output: postgresql://myapp:secretpass123@postgres:5432/myapp_db

# PostgreSQL HA (uses master)
./lib/db-cli.sh postgres-ha create-user myapp secretpass123 myapp_db

# TimescaleDB
./lib/db-cli.sh timescaledb create-user myapp secretpass123 myapp_db

# MySQL
./lib/db-cli.sh mysql create-user myapp secretpass123 myapp_db
# Output: mysql://myapp:secretpass123@mysql:3306/myapp_db

# MongoDB
./lib/db-cli.sh mongo create-user myapp secretpass123 myapp_db
# Output: mongodb://myapp:secretpass123@mongo-primary:27017/myapp_db

# ClickHouse
./lib/db-cli.sh clickhouse create-user myapp secretpass123 myapp_db
```

### 8.3 List Users

```bash
./lib/db-cli.sh postgres list-users
./lib/db-cli.sh mysql list-users
./lib/db-cli.sh mongo list-users
```

### 8.4 Delete User

```bash
# Keep database
./lib/db-cli.sh postgres delete-user myapp

# Delete user AND drop owned databases/schemas
./lib/db-cli.sh postgres delete-user myapp --drop-schema
```

### 8.5 Connection Strings

After creating users, use these connection strings from your app:

| Database | Connection String |
|----------|-------------------|
| PostgreSQL | `postgresql://myapp:secret@postgres:5432/myapp_db` |
| PostgreSQL HA | `postgresql://myapp:secret@postgres-master:5432/myapp_db` |
| TimescaleDB | `postgresql://myapp:secret@timescaledb:5432/myapp_db` |
| MySQL | `mysql://myapp:secret@mysql:3306/myapp_db` |
| MongoDB | `mongodb://myapp:secret@mongo-primary:27017/myapp_db?replicaSet=rs0` |
| Redis Cache | `redis://:password@redis-cache:6379` |
| Redis Queue | `redis://:password@redis-queue:6379` |

## Step 9: Deploy Your Application

### 9.1 Create docker-compose.yml for Your App

```yaml
# /opt/apps/myapp/docker-compose.yml
services:
  myapp:
    image: myapp:latest
    container_name: myapp
    restart: unless-stopped
    environment:
      - DATABASE_URL=postgresql://myapp:secretpass123@postgres:5432/myapp_db
      - REDIS_URL=redis://:password@redis-cache:6379
    ports:
      - "8080:8080"
    networks:
      - infra

networks:
  infra:
    external: true
```

### 9.2 Start Your App

```bash
cd /opt/apps/myapp
docker compose up -d
```

### 9.3 Connect to Observability (Optional)

```bash
# Register app with Prometheus metrics scraping
/opt/infra/scripts/app-cli.sh connect myapp --port 8080 --metrics

# Add custom dashboard and alerts (copy files first, then reload)
cp dashboard.json /opt/infra/services/observability/dashboards/app-myapp.json
cp alerts.yml /opt/infra/services/observability/config/alerting-rules/app-myapp.yml
/opt/infra/scripts/app-cli.sh reload
```

## Step 10: Setup Domain & SSL (Optional)

### 10.1 Configure Traefik

Edit `services/traefik/.env`:

```bash
cd /opt/infra/services/traefik
cp .env.example .env
nano .env
```

Set your email for Let's Encrypt:

```ini
TRAEFIK_ACME_EMAIL=your@email.com
```

### 10.2 Add Labels to Your App

```yaml
services:
  myapp:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`app.yourdomain.com`)"
      - "traefik.http.routers.myapp.tls.certresolver=letsencrypt"
```

### 10.3 Update DNS

Point your domain to your server IP:

```text
app.yourdomain.com  →  A  →  your-server-ip
```

## Step 11: Setup Backups (Recommended)

### 11.1 Configure Backup Service

```bash
cd /opt/infra/services/backup
cp .env.example .env
nano .env
```

Set backup destination (S3, local, etc.):

```ini
RESTIC_PASSWORD=your-backup-password
RESTIC_REPOSITORY=s3:s3.amazonaws.com/your-bucket
AWS_ACCESS_KEY_ID=xxx
AWS_SECRET_ACCESS_KEY=xxx
```

### 11.2 Enable Backup

```bash
# Edit services.conf
nano /opt/infra/services.conf
# Set: backup=true

# Restart
./setup.sh
```

## Step 12: Production Checklist

Before going live, run the production readiness checklist:

```bash
bash scripts/production-checklist.sh
```

This validates:

- **Security**: Admin password, file permissions, SSH hardening, firewall, brute-force protection
- **Services**: All enabled services running and healthy
- **Backups**: Backup service configured with repository and password
- **Monitoring**: Prometheus, Grafana, Alertmanager, Loki running
- **SSL/TLS**: Let's Encrypt configured, ACME certificate store exists
- **Resources**: Disk usage < 85%, memory usage < 90%
- **Updates**: Auto security updates enabled

Exit codes:

- `0` = Ready for production (or minor warnings)
- `1` = Not ready - fix failed checks first

Example:

```bash
$ bash scripts/production-checklist.sh

==========================================
  Production Readiness Checklist
==========================================
  Server: my-server
  Date: Wed Dec 11 10:00:00 UTC 2025

━━━ 1. Security ━━━
  ✓ Admin password configured
  ✓ Directory permissions secured (700)
  ✓ SSH root login disabled
  ✓ Firewall (UFW) enabled
  ✓ Fail2ban running
  ✓ Docker access limited (2 users)

━━━ 2. Core Services ━━━
  ✓ postgres running
  ✓ redis-cache running
  ✓ traefik running
  ✓ grafana running

━━━ 3. Backups ━━━
  ✓ Backup service running
  ✓ Backup password configured
  ✓ Backup repository configured

━━━ 4. Monitoring & Alerts ━━━
  ✓ Prometheus running
  ✓ Grafana running
  ✓ Alertmanager running
  ! No push notification service → Enable ntfy for alerts

━━━ 5. SSL/TLS ━━━
  ✓ Let's Encrypt email configured
  ✓ ACME certificate store exists

━━━ 6. System Resources ━━━
  ✓ Disk usage OK (45%)
  ✓ Memory usage OK (62%)
  ℹ Docker disk usage: 12.5GB

━━━ 7. Updates ━━━
  ✓ Auto security updates enabled (apt)

==========================================
  Summary
==========================================
  Total checks: 18
  Passed: 17
  Failed: 0
  Warnings: 1

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  READY FOR PRODUCTION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Troubleshooting

### Forgot Admin Password

If you forgot your infrastructure admin password, reset it with root access:

```bash
sudo bash scripts/reset-password.sh
```

This requires root/sudo access (proves you own the server) and lets you set a new password.

### Service Won't Start

```bash
# Check logs
docker logs <container-name>

# Check compose file
docker compose -f services/<service>/docker-compose.yml config
```

### Database Connection Failed

```bash
# Test from inside network
docker exec -it postgres psql -U postgres -c "SELECT 1"

# Check if service is on infra network
docker network inspect infra
```

### Port Already in Use

```bash
# Find what's using the port
sudo lsof -i :5432
sudo netstat -tulpn | grep 5432
```

### Reset Everything

```bash
# Stop all services
./stop.sh

# Remove all containers and volumes (DANGEROUS - deletes data)
docker system prune -a --volumes

# Start fresh
./setup.sh
```

## Maintenance Commands

| Command | Description |
|---------|-------------|
| `./status.sh` | Check all services |
| `./stop.sh` | Stop all services |
| `./setup.sh` | Start/restart services |
| `./secure.sh` | Secure file permissions |
| `./secure.sh --check` | Audit permissions |
| `./test.sh` | Validate configurations |
| `docker logs -f <name>` | View container logs |
| `docker stats` | Resource usage |

## Security Checklist

### Server Security

- [ ] SSH hardened (`vps-initial-setup.sh`)
- [ ] Custom SSH port (not 22)
- [ ] SSH key authentication only
- [ ] Root login disabled
- [ ] Firewall enabled (ufw/firewalld)
- [ ] Fail2ban enabled
- [ ] Auto security updates enabled

### Infrastructure Security

- [ ] Admin password set (`./setup.sh --set-password`)
- [ ] File permissions secured (`./secure.sh`)
- [ ] Strong passwords in `.secrets`
- [ ] Database ports not exposed publicly (127.0.0.1 only)
- [ ] Traefik SSL configured for public services

### Access Control

- [ ] Docker access limited to Infra Admins only
- [ ] Team members added with correct user type:
  - Developers: type 1 (SSH only)
  - DevOps: type 2 (sudo, NO docker)
  - Infra Admins: type 3 (full access)
- [ ] Audit access periodically (`scripts/audit-access.sh`)
- [ ] Regular backups configured

### Verify Security

```bash
# Run production readiness checklist
bash scripts/production-checklist.sh

# Check who has Docker access
sudo bash scripts/audit-access.sh

# Check file permissions
./secure.sh --check

# List docker group members
getent group docker
```

## Next Steps

1. **Monitor** - Check Grafana dashboards regularly
2. **Backup** - Verify backups are running
3. **Update** - Keep services updated with `docker compose pull`
4. **Scale** - Add more services as needed

## Getting Help

- Check service README: `services/<service>/README.md`
- View logs: `docker logs <container-name>`
- Run tests: `./test.sh --verbose`
