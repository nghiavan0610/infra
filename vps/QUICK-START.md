# VPS Setup - Quick Start Guide

## 🎯 The Simple 3-Step Process

This guide shows you exactly what to run and when for a production-ready VPS.

---

## Prerequisites

Before you start, make sure you have:

- [ ] Fresh VPS with root access
- [ ] VPS IP address
- [ ] Root password
- [ ] SSH key generated on your local machine (recommended)

**Generate SSH key** (if you don't have one):
```bash
# On your local machine
ssh-keygen -t ed25519 -C "your_email@example.com"
cat ~/.ssh/id_ed25519.pub  # Copy this
```

---

## Step 1: Initial VPS Setup (15 min)

### Connect as Root
```bash
# From your local machine
ssh root@YOUR_VPS_IP

# Upload the script
# Option A: Copy-paste the script content
# Option B: Use scp
scp vps-initial-setup.sh root@YOUR_VPS_IP:/root/
```

### Run Initial Setup
```bash
# On VPS as root
chmod +x vps-initial-setup.sh
bash vps-initial-setup.sh
```

### Interactive Prompts
The script will ask you:

1. **Enter new sudo username:** `myuser` (choose your username)
2. **Enter password:** `[create strong password]`
3. **Confirm password:** `[same password]`
4. **Enter SSH port:** `2222` (recommended, not default 22)
5. **Paste your SSH public key:** `[paste from ~/.ssh/id_ed25519.pub]`

### What This Does
- ✅ Creates non-root user with sudo privileges
- ✅ Configures SSH security (custom port, disables root)
- ✅ Enables firewall (ports: 2222, 80, 443)
- ✅ Installs fail2ban (brute-force protection)
- ✅ Enables automatic security updates
- ✅ Optimizes system for production

---

## ⚠️ CRITICAL: Test SSH Connection

**DO NOT close your root session yet!**

Open a **NEW terminal** and test:

```bash
# Test new SSH connection
ssh -p 2222 myuser@YOUR_VPS_IP

# Test sudo access
sudo whoami  # Should return: root
```

### If Successful ✅
- Close the root session
- Use your new user from now on

### If Failed ❌
- Keep root session open
- Check firewall: `sudo ufw status`
- Check SSH: `sudo systemctl status sshd`
- Fix issues before closing root session

---

## Step 2: Install Docker (10 min)

### Connect with New User
```bash
# From your local machine
ssh -p 2222 myuser@YOUR_VPS_IP
```

### Upload Docker Script
```bash
# Option A: Copy from /root/setup/
sudo cp /root/setup/docker-install-production.sh .

# Option B: Download
curl -O https://raw.githubusercontent.com/YOUR_REPO/docker-install-production.sh

# Option C: scp from local
# scp -P 2222 docker-install-production.sh myuser@YOUR_VPS_IP:~/
```

### Run Docker Installation
```bash
chmod +x docker-install-production.sh
bash docker-install-production.sh
```

### What This Does
- ✅ Auto-detects OS (Ubuntu/Debian/CentOS/Amazon Linux)
- ✅ Removes old Docker installations
- ✅ Installs Docker CE (latest stable)
- ✅ Installs Docker Compose v2 (plugin)
- ✅ Configures production settings
- ✅ Adds user to docker group

### Apply Changes (Required!)
```bash
# Log out
exit

# Log back in
ssh -p 2222 myuser@YOUR_VPS_IP

# Verify Docker works
docker run hello-world
docker compose version
```

**Expected Output:**
```
Docker version 24.x.x
Docker Compose version v2.x.x
```

---

## Step 3: Health Check (2 min)

### Run System Check
```bash
bash vps-health-check.sh
```

### What to Look For

**All Green ✅ = Ready for Production**

The script checks:
- ✅ User permissions
- ✅ SSH security (root disabled, custom port)
- ✅ Firewall active
- ✅ Fail2ban running
- ✅ Docker installed and working
- ✅ System resources (CPU, RAM, disk)
- ✅ Automatic updates enabled

**Yellow ⚠️ = Warnings** (optional improvements)

**Red ❌ = Failed** (must fix before production)

---

## Step 4: Deploy Your Services

### Prepare Directory Structure
```bash
# Create organized directories
mkdir -p ~/docker/{postgres,redis,mongo,nginx}
mkdir -p ~/backups
mkdir -p ~/logs
```

### Deploy Example Service
```bash
# Upload your docker-compose files
cd ~/docker/postgres-single

# Create .env file
nano .env
```

**Example `.env`:**
```env
POSTGRES_USER=admin
POSTGRES_PASSWORD=STRONG_RANDOM_PASSWORD_HERE
POSTGRES_DB=myapp
POSTGRES_PORT=5432
```

### Start Services
```bash
# Start in background
docker compose up -d

# Check status
docker compose ps

# View logs
docker compose logs -f

# Stop if needed
docker compose down
```

---

## 📋 Complete Checklist

### Pre-Setup
- [ ] VPS purchased, IP received
- [ ] SSH key generated locally
- [ ] Scripts downloaded/ready

### Step 1: Initial Setup
- [ ] Connected as root
- [ ] Ran `vps-initial-setup.sh`
- [ ] Created new sudo user
- [ ] Configured SSH (custom port, key auth)
- [ ] **Tested new SSH in separate terminal**
- [ ] Verified sudo access works

### Step 2: Docker
- [ ] Connected as new user (not root)
- [ ] Ran `docker-install-production.sh`
- [ ] Logged out and back in
- [ ] Verified: `docker run hello-world`
- [ ] Verified: `docker compose version`

### Step 3: Verification
- [ ] Ran `vps-health-check.sh`
- [ ] All critical checks passed (green ✅)
- [ ] Fixed any red ❌ issues
- [ ] Reviewed yellow ⚠️ warnings

### Step 4: Deployment
- [ ] Created directory structure
- [ ] Uploaded docker-compose files
- [ ] Created .env files (with strong passwords)
- [ ] Started services: `docker compose up -d`
- [ ] Verified services running: `docker compose ps`

---

## 🔒 Security Verification

After setup, verify these are configured:

```bash
# 1. Root login disabled
sudo grep "PermitRootLogin no" /etc/ssh/sshd_config*

# 2. Firewall active
sudo ufw status  # Ubuntu/Debian
sudo firewall-cmd --list-all  # CentOS/RHEL

# 3. Fail2ban protecting SSH
sudo fail2ban-client status sshd

# 4. SSH on custom port
sudo netstat -tulpn | grep sshd

# 5. Docker daemon running
sudo systemctl status docker

# 6. Automatic updates enabled
systemctl status unattended-upgrades  # Ubuntu/Debian
systemctl status yum-cron  # CentOS/RHEL
```

---

## ⏱️ Timeline Summary

| Step | Time | What Happens |
|------|------|--------------|
| Step 1: Initial Setup | 15 min | VPS secured, user created |
| Step 2: Docker Install | 10 min | Docker ready for use |
| Step 3: Health Check | 2 min | Verification complete |
| Step 4: Deploy Services | 5-10 min | Apps running |
| **TOTAL** | **~30-40 min** | **Production-Ready VPS** |

---

## 🆘 Common Issues & Fixes

### Issue 1: Can't SSH After Step 1

**Symptom:** Connection refused or timeout on new port

**Fix:**
1. Use VPS provider's console/web terminal
2. Check firewall: `sudo ufw status`
3. Check if SSH is running: `sudo systemctl status sshd`
4. Temporarily allow port: `sudo ufw allow 2222/tcp`
5. Restart SSH: `sudo systemctl restart sshd`

### Issue 2: Docker Permission Denied

**Symptom:** `permission denied while trying to connect to Docker daemon`

**Fix:**
```bash
# Verify docker group membership
groups

# If 'docker' is not listed, add it
sudo usermod -aG docker $USER

# MUST logout and login
exit
ssh -p 2222 myuser@YOUR_VPS_IP

# Now test
docker ps  # Should work without sudo
```

### Issue 3: Firewall Blocking Services

**Symptom:** Can't connect to database/service from outside

**Fix:**
```bash
# Check what's listening
sudo netstat -tulpn | grep LISTEN

# Allow specific port
sudo ufw allow 5432/tcp comment 'PostgreSQL'  # Example

# Verify
sudo ufw status
```

### Issue 4: Health Check Shows Red/Failed

**Fix:**
```bash
# Read the error message carefully
bash vps-health-check.sh

# Each failed check shows a "Fix:" suggestion
# Follow the suggested command

# Example: If Docker not running
sudo systemctl start docker
sudo systemctl enable docker
```

---

## 🚀 What's Next?

### Recommended Next Steps

1. **Setup SSL/TLS** (if running web services)
   ```bash
   sudo apt install certbot
   sudo certbot certonly --standalone -d yourdomain.com
   ```

2. **Configure Reverse Proxy**
   - Traefik (automatic SSL)
   - Nginx (traditional)
   - Caddy (simple)

3. **Setup Monitoring**
   - Deploy observability stack
   - Configure Prometheus alerts
   - Setup Grafana dashboards

4. **Configure Backups**
   ```bash
   # Create backup script
   mkdir ~/scripts
   # Add cron job for daily backups
   crontab -e
   ```

5. **Optimize for Your Workload**
   - Tune PostgreSQL for your data size
   - Configure Redis persistence
   - Adjust resource limits

---

## 📖 Additional Documentation

- **VPS-SETUP-GUIDE.md** - Comprehensive 60-page guide
  - Detailed explanations
  - Advanced configurations
  - Security best practices
  - Troubleshooting guide

- **README.md** - File descriptions and overview

- **Scripts:**
  - `vps-initial-setup.sh` - Step 1
  - `docker-install-production.sh` - Step 2
  - `vps-health-check.sh` - Step 3

---

## 💡 Pro Tips

1. **Save your SSH config** (`~/.ssh/config` on local machine):
   ```
   Host myvps
       HostName YOUR_VPS_IP
       User myuser
       Port 2222
       IdentityFile ~/.ssh/id_ed25519
   ```
   Then connect with: `ssh myvps`

2. **Use strong passwords:**
   ```bash
   # Generate random password
   openssl rand -base64 32
   ```

3. **Regular maintenance:**
   ```bash
   # Weekly
   docker system prune -f

   # Monthly
   sudo apt update && sudo apt upgrade  # Ubuntu
   sudo yum update  # CentOS
   ```

4. **Monitor logs:**
   ```bash
   # System logs
   sudo journalctl -f

   # Docker logs
   docker compose logs -f

   # SSH login attempts
   sudo grep "Failed password" /var/log/auth.log
   ```

---

## ✅ Success Criteria

Your VPS is ready for production when:

- ✅ Health check shows all green (or only yellow warnings)
- ✅ Can SSH with non-root user
- ✅ Docker runs without sudo
- ✅ Firewall is active
- ✅ Fail2ban is running
- ✅ Test container runs successfully
- ✅ Services deploy and run stable

---

## 🎉 You're Done!

If you've completed all steps and the health check passes, **congratulations!**

You now have a:
- 🔒 Secure VPS (hardened SSH, firewall, fail2ban)
- 🐳 Production-ready Docker environment
- 📊 Monitored system (health checks)
- 🚀 Ready to deploy applications

**Total setup time: ~30-40 minutes**

---

## Need Help?

- Review full guide: `VPS-SETUP-GUIDE.md`
- Check troubleshooting section above
- Run health check: `bash vps-health-check.sh`
- View logs: `sudo journalctl -xe`

---

**Last Updated:** 2025-11-22
**Version:** 1.0.0
