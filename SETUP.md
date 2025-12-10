# Infrastructure Setup Guide

Complete step-by-step guide for setting up infrastructure on a fresh VPS.

## Quick Start (Experienced Users)

```bash
# 1. SSH to fresh VPS as root
ssh root@your-server-ip

# 2. Setup GitHub SSH key (see Step 0 below), then clone
sudo mkdir -p /opt/infra && sudo chown $USER:$USER /opt/infra
git clone git@github.com:nghiavan0610/infra.git /opt/infra
cd /opt/infra
bash scripts/vps-initial-setup.sh

# 3. In NEW terminal, login as new user
ssh -p 2222 deploy@your-server-ip
cd /opt/infra

# 4. Install Docker
bash scripts/docker-install.sh
exit  # Logout to apply docker group

# 5. Login again and start services
ssh -p 2222 deploy@your-server-ip
cd /opt/infra
./test.sh                    # Validate
nano services.conf           # Enable services
./setup.sh --set-password    # Set admin password
./setup.sh                   # Start services
./status.sh                  # Verify
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

## Step 1: Initial Server Setup

### 1.1 Login to Your VPS

```bash
ssh root@your-server-ip
```

### 1.2 Download and Run VPS Setup Script

```bash
# Download the script
curl -fsSL https://raw.githubusercontent.com/nghiavan0610/infra/main/scripts/vps-initial-setup.sh -o vps-initial-setup.sh

# Or clone the repo first
sudo mkdir -p /opt/infra && sudo chown $USER:$USER /opt/infra
git clone git@github.com:nghiavan0610/infra.git /opt/infra
cd /opt/infra

# Run the VPS setup script
bash scripts/vps-initial-setup.sh
```

### 1.3 What the Script Does

The script will prompt you for:
- **Username**: New sudo user (e.g., `deploy`)
- **Password**: Password for the new user
- **SSH Port**: Custom SSH port (default: 2222, recommended for security)
- **SSH Public Key**: Your public key for key-based authentication

The script automatically configures:
- Creates non-root user with sudo privileges
- SSH hardening (disables root login, custom port)
- Key-based authentication (if SSH key provided)
- Firewall (UFW or firewalld)
- Fail2ban for brute-force protection
- Automatic security updates
- System limits optimized for production
- Timezone set to UTC

### 1.4 After Script Completes

**IMPORTANT**: Test SSH in a NEW terminal before closing the root session!

```bash
# In a NEW terminal, test the new connection
ssh -p 2222 deploy@your-server-ip

# Verify sudo works
sudo whoami
```

Only close the root terminal after confirming the new user can connect and use sudo.

## Step 2: Install Docker

### 2.1 Login as Deploy User

```bash
# Use the SSH port you configured (default: 2222)
ssh -p 2222 deploy@your-server-ip
```

### 2.2 Clone Infrastructure Repository (if not already done)

```bash
# Skip if you already cloned in Step 1
sudo mkdir -p /opt/infra && sudo chown $USER:$USER /opt/infra
git clone git@github.com:nghiavan0610/infra.git /opt/infra
cd /opt/infra
```

### 2.3 Run Docker Install Script

```bash
bash scripts/docker-install.sh
```

### 2.4 Add User to Docker Group

```bash
sudo usermod -aG docker $USER

# IMPORTANT: Logout and login again
exit
```

### 2.5 Verify Installation

```bash
ssh deploy@your-server-ip
cd /opt/infra

# Check versions
docker --version
docker compose version

# Test docker works
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

## Step 6: Access Services

### 6.1 Get Credentials

```bash
cat .secrets
```

### 6.2 Access URLs

| Service | URL | Notes |
|---------|-----|-------|
| Grafana | http://your-ip:3000 | Dashboards & monitoring |
| Prometheus | http://your-ip:9090 | Metrics |
| Traefik | http://your-ip:8080 | Reverse proxy dashboard |
| Uptime Kuma | http://your-ip:3001 | Status page |
| LangFuse | http://your-ip:3050 | LLM observability |

### 6.3 Default Ports

| Service | Port |
|---------|------|
| PostgreSQL | 5432 |
| Redis Cache | 6379 |
| Redis Queue | 6380 |
| MongoDB | 27017 |
| MySQL | 3306 |

## Step 7: Create Database for Your App

### 7.1 PostgreSQL

```bash
# Create user + database
./lib/db-cli.sh postgres create-user myapp secretpass123 myapp_db

# Output:
# Connection string:
#   postgresql://myapp:secretpass123@postgres:5432/myapp_db
```

### 7.2 List Users

```bash
./lib/db-cli.sh postgres list-users
```

### 7.3 Delete User

```bash
# Keep database
./lib/db-cli.sh postgres delete-user myapp

# Delete database too
./lib/db-cli.sh postgres delete-user myapp --drop-schema
```

## Step 8: Deploy Your Application

### 8.1 Create docker-compose.yml for Your App

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

### 8.2 Start Your App

```bash
cd /opt/apps/myapp
docker compose up -d
```

### 8.3 Connect to Observability (Optional)

```bash
/opt/infra/lib/app-cli.sh connect myapp --port 8080
```

## Step 9: Setup Domain & SSL (Optional)

### 9.1 Configure Traefik

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

### 9.2 Add Labels to Your App

```yaml
services:
  myapp:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`app.yourdomain.com`)"
      - "traefik.http.routers.myapp.tls.certresolver=letsencrypt"
```

### 9.3 Update DNS

Point your domain to your server IP:
```
app.yourdomain.com  →  A  →  your-server-ip
```

## Step 10: Setup Backups (Recommended)

### 10.1 Configure Backup Service

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

### 10.2 Enable Backup

```bash
# Edit services.conf
nano /opt/infra/services.conf
# Set: backup=true

# Restart
./setup.sh
```

## Troubleshooting

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
| `./test.sh` | Validate configurations |
| `docker logs -f <name>` | View container logs |
| `docker stats` | Resource usage |

## Security Checklist

- [ ] Non-root user created
- [ ] SSH key authentication only
- [ ] Firewall enabled (ufw)
- [ ] Strong passwords in `.secrets`
- [ ] Database ports not exposed publicly (127.0.0.1 only)
- [ ] Traefik SSL configured for public services
- [ ] Fail2ban or Crowdsec enabled
- [ ] Regular backups configured

## Next Steps

1. **Monitor** - Check Grafana dashboards regularly
2. **Backup** - Verify backups are running
3. **Update** - Keep services updated with `docker compose pull`
4. **Scale** - Add more services as needed

## Getting Help

- Check service README: `services/<service>/README.md`
- View logs: `docker logs <container-name>`
- Run tests: `./test.sh --verbose`
