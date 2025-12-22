# Add User Guide - Dev Team Management

Quick guide for adding users to your VPS, including your first Infra Admin.

---

## When to Use This Script

Use `add-user.sh` to:
- ✅ Create your first Infra Admin (after Docker is installed)
- ✅ Add new dev team members
- ✅ Update SSH keys for existing users
- ✅ Grant/manage sudo access
- ✅ Grant/manage Docker access
- ✅ Set up SSH key authentication
- ✅ Create tunnel-only users for dev partners

**Typical Flow:**
1. `vps-initial-setup.sh` → Hardens system (SSH, firewall, fail2ban)
2. `docker-install.sh` → Installs Docker (current user gets docker access)
3. `add-user.sh` → Create Infra Admin or add team members

---

## Quick Start

### Upload Script to VPS

```bash
# From your local machine
scp -P 2222 add-user.sh your-user@YOUR_VPS_IP:~/

# Or if using Oracle Cloud with opc user
scp -O add-user.sh opc@YOUR_VPS_IP:~/
```

### Add a New Team Member

```bash
# SSH to VPS
ssh -p 2222 your-user@YOUR_VPS_IP

# Make script executable
chmod +x add-user.sh

# Run script
sudo bash add-user.sh
```

---

## User Types

The script offers 5 user types:

| Type | SSH | Sudo | Docker | Apps | Use Case |
|------|-----|------|--------|------|----------|
| **1) Developer** | ✅ | ❌ | ❌ | ❌ | App deployment only |
| **2) DevOps** | ✅ | ✅ | ❌ | Optional | System management (NO Docker) |
| **3) Infra Admin** | ✅ | ✅ | ✅ | ✅ | Full infrastructure control |
| **4) Tunnel Only** | tunnel | ❌ | ❌ | ❌ | DB access from local (no shell) |
| **5) CI Runner** | ❌ | ❌ | ✅ | ✅ | GitLab runner service account |

---

## Interactive Prompts

The script will ask:

### 1. User Type
```
User Types:
  1) Developer   - SSH access only (application deployment)
  2) DevOps      - SSH + sudo (system management, NO docker)
  3) Infra Admin - SSH + sudo + docker (full infrastructure control)
  4) Tunnel Only - SSH tunnel only (access DB/Redis from local, no shell)
  5) CI Runner   - Docker + apps access (for gitlab-runner service, no SSH)

Select user type [1-5]: 1
```

### 2. Username
```
Enter username for new team member: alice
```
- Use lowercase letters, numbers, underscore, hyphen
- Example: `alice`, `bob_dev`, `charlie-admin`

### 3. Password (new users only, not for tunnel-only)
```
Enter password for alice: ********
Confirm password: ********
```
- Choose a strong password
- User can change it later with: `passwd`
- Tunnel-only users don't need passwords (SSH key only)

### 4. SSH Public Key
```
Paste the SSH public key (press Enter when done):
ssh-rsa AAAAB3NzaC1yc2EAAAA...
```
- Get from team member: `cat ~/.ssh/id_ed25519.pub` or `cat ~/.ssh/id_rsa.pub`
- Paste the entire key (starts with `ssh-rsa` or `ssh-ed25519`)

---

## Example Usage

### Example 1: Add Developer

```bash
$ sudo bash add-user.sh

==========================================
  Add New User - Dev Team Management
==========================================

User Types:
  1) Developer   - SSH access only (application deployment)
  2) DevOps      - SSH + sudo (system management, NO docker)
  3) Infra Admin - SSH + sudo + docker (full infrastructure control)
  4) Tunnel Only - SSH tunnel only (access DB/Redis from local, no shell)

Select user type [1-4]: 1

Enter username for new team member: alice
Enter password for alice: ********
Confirm password: ********

Please provide SSH public key for alice
Paste the SSH public key (press Enter when done):
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJx... alice@laptop

[INFO] User alice created
[INFO] SSH key configured

==========================================
[INFO] User Setup Complete!
==========================================

User Information:
  - Username: alice
  - Type: Developer
  - Home directory: /home/alice
  - Sudo access: NO
  - Docker access: NO
  - SSH key: CONFIGURED

[INFO] User can now connect with:
  ssh -p 2222 alice@YOUR_VPS_IP

==========================================
```

### Example 2: Add DevOps User

```bash
$ sudo bash add-user.sh

Select user type [1-4]: 2

Enter username for new team member: bob
Enter password for bob: ********
Confirm password: ********

Paste the SSH public key (press Enter when done):
ssh-rsa AAAAB3NzaC1yc2EAAAA... bob@laptop

[INFO] User bob created
[INFO] Sudo privileges granted
[INFO] SSH key configured

User Information:
  - Username: bob
  - Type: DevOps
  - Sudo access: YES
  - Docker access: NO
  - SSH key: CONFIGURED

[INFO] User can now connect with:
  ssh -p 2222 bob@YOUR_VPS_IP

What bob can do:
  - SSH into the server
  - Run system commands with sudo
  - Manage system packages, services, firewall

What bob CANNOT do:
  - Control Docker containers (docker ps, docker stop, etc.)
  - Access infrastructure management scripts
```

### Example 3: Add Tunnel-Only User (Dev Partner)

```bash
$ sudo bash add-user.sh

Select user type [1-4]: 4

TUNNEL ONLY USER:
  This user can ONLY create SSH tunnels to access services.
  They cannot execute any commands on the server.
  Perfect for dev partners who need DB/Redis access from local.

Enter username for new team member: dev-partner

Please provide SSH public key for dev-partner
Paste the SSH public key (press Enter when done):
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINew... partner@laptop

[INFO] User dev-partner created (tunnel-only, no shell)
[INFO] SSH tunnel-only restrictions configured
[INFO] SSH service reloaded
[INFO] SSH key configured

==========================================
[INFO] User Setup Complete!
==========================================

User Information:
  - Username: dev-partner
  - Type: Tunnel Only
  - Home directory: /home/dev-partner

Permissions:
  - Sudo access: NO
  - Docker access: NO
  - SSH key: CONFIGURED

[INFO] Dev partner can create SSH tunnel with:

  # Create tunnel (run on local machine)
  ssh -N -p 2222 \
      -L 5432:localhost:5432 \
      -L 6379:localhost:6379 \
      -L 6380:localhost:6380 \
      dev-partner@YOUR_VPS_IP

  # Then connect to services locally:
  psql -h localhost -p 5432 -U postgres
  redis-cli -h localhost -p 6379

What dev-partner can do:
  - Create SSH tunnels to access PostgreSQL, Redis, etc.
  - Connect to databases from their local machine

What dev-partner CANNOT do:
  - Execute ANY commands on the server
  - Get a shell session
  - Access files on the server
  - Control Docker containers

==========================================
```

### Example 4: Add CI Runner (for GitLab Runner)

```bash
$ sudo bash add-user.sh

==========================================
  Add New User - Dev Team Management
==========================================

User Types:
  1) Developer   - SSH access only (application deployment)
  2) DevOps      - SSH + sudo (system management, NO docker)
  3) Infra Admin - SSH + sudo + docker (full infrastructure control)
  4) Tunnel Only - SSH tunnel only (access DB/Redis from local, no shell)
  5) CI Runner   - Docker + apps access (for gitlab-runner service, no SSH)

Select user type [1-5]: 5

CI RUNNER USER:
  This is a service account for CI/CD runners (e.g., gitlab-runner).
  It has Docker + apps group access but NO sudo and NO SSH access.
  Use this after installing gitlab-runner from official docs.

Enter username for CI runner [gitlab-runner]:

[INFO] User gitlab-runner created (CI runner service account, password locked)
[INFO] Docker access granted
[INFO] Apps group access granted

==========================================
[INFO] User Setup Complete!
==========================================

User Information:
  - Username: gitlab-runner
  - Type: CI Runner
  - Home directory: /home/gitlab-runner

Permissions:
  - Sudo access: NO
  - Docker access: YES (can manage all containers)
  - Apps group: YES (can access /opt/apps)
  - SSH key: N/A (service account)

[INFO] CI Runner service account configured!

Next steps:
  1. Install gitlab-runner (if not already installed):
     curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh | sudo bash
     sudo apt-get install gitlab-runner

  2. Register the runner:
     sudo gitlab-runner register

  3. Restart gitlab-runner service:
     sudo systemctl restart gitlab-runner

What gitlab-runner can do:
  - Run docker commands (docker ps, docker compose, etc.)
  - Write to /opt/apps directory
  - Deploy applications via CI/CD

What gitlab-runner CANNOT do:
  - SSH into the server (no password, no key)
  - Run commands as root (no sudo)
  - Access system configuration

==========================================
```

### Example 5: Update SSH Key for Existing User

```bash
$ sudo bash add-user.sh

Enter username for new team member: alice
[ERROR] User alice already exists!
Do you want to update this user's SSH key? (y/n): y
Grant sudo privileges to alice? (y/n): y

Paste the SSH public key (press Enter when done):
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINew... alice@new-laptop

[INFO] Updating existing user: alice
[INFO] Sudo privileges granted
[INFO] SSH key added to existing authorized_keys
```

---

## What This Script Does

✅ **For New Users:**
1. Creates user account with appropriate shell
2. Sets password (except for tunnel-only users)
3. Grants sudo access (for DevOps and Infra Admin)
4. Grants Docker access (for Infra Admin only)
5. Adds SSH public key
6. Sets correct file permissions
7. Configures SSH restrictions for tunnel-only users

✅ **For Existing Users:**
1. Optionally updates SSH key
2. Updates sudo/Docker access based on new user type
3. Appends new key to authorized_keys (doesn't overwrite)

✅ **For Tunnel-Only Users:**
1. Creates user with `/usr/sbin/nologin` shell
2. Configures SSH Match block for tunnel-only restrictions
3. Reloads SSH service automatically

❌ **What It Does NOT Do:**
- Modify system-wide SSH config (except for tunnel-only Match blocks)
- Change firewall rules
- Modify system limits

---

## /opt/apps Directory Setup

The `/opt/apps` directory is where CI/CD deploys applications. It's created by `docker-install.sh` with proper permissions.

### If /opt/apps Doesn't Exist

```bash
# Create directory with proper permissions
sudo mkdir -p /opt/apps
sudo chown root:apps /opt/apps
sudo chmod 2775 /opt/apps

# Set ACL for group write on existing and future files
sudo setfacl -R -m g::rwx /opt/apps
sudo setfacl -R -d -m g::rwx /opt/apps
```

### If CI/CD Fails with Permission Denied

```bash
# Fix permissions on existing files
sudo setfacl -R -m g::rwx /opt/apps
sudo setfacl -R -d -m g::rwx /opt/apps

# Verify
getfacl /opt/apps
```

### Why ACL?

| Method | Existing Files | Future Files |
|--------|----------------|--------------|
| `chmod g+w` | ✅ | ❌ (depends on umask) |
| `setfacl` | ✅ | ✅ (default ACL) |

ACL ensures all users in the `apps` group can always write, regardless of who creates the file.

---

## Security Best Practices

### 1. Get SSH Keys from Team Members

Ask each team member to run on **their local machine**:

```bash
# If they don't have a key, generate one
ssh-keygen -t ed25519 -C "their_email@example.com"

# Display public key
cat ~/.ssh/id_ed25519.pub
```

They send you the **public key only** (starts with `ssh-ed25519` or `ssh-rsa`)

### 2. Use Strong Passwords

```bash
# Generate random password
openssl rand -base64 16
```

### 3. Grant Access Sparingly

- **Docker access**: Only grant to trusted Infra Admins (can control all containers)
- **Sudo access**: Only for DevOps and Infra Admins
- **Tunnel-only**: Prefer for dev partners who just need database access
- **Developer**: For team members who only need to deploy apps

### 4. Regular Audits

```bash
# List all users
cat /etc/passwd | grep /home

# List sudo users
grep '^sudo:' /etc/group  # Ubuntu/Debian
grep '^wheel:' /etc/group  # CentOS/Oracle Linux

# Check who can SSH
ls -la /home/*/.ssh/authorized_keys
```

---

## Common Tasks

### Remove a User

```bash
# Remove user and their home directory
sudo userdel -r username

# Or keep home directory
sudo userdel username
```

### Disable User (Keep Account)

```bash
# Lock account (disable password)
sudo passwd -l username

# Disable SSH
sudo mv /home/username/.ssh/authorized_keys /home/username/.ssh/authorized_keys.disabled
```

### Change User Password

```bash
# As root/sudo
sudo passwd username

# As the user themselves
passwd
```

### Add Existing User to Sudo

```bash
# Ubuntu/Debian
sudo usermod -aG sudo username

# CentOS/Oracle Linux
sudo usermod -aG wheel username
```

### List All SSH Keys for a User

```bash
cat /home/username/.ssh/authorized_keys
```

---

## Troubleshooting

### Issue: "User already exists"

**Solution:**
- Choose a different username, or
- Answer `y` to update the existing user's SSH key

### Issue: User can't SSH

**Check:**
```bash
# 1. Verify SSH key is configured
sudo cat /home/username/.ssh/authorized_keys

# 2. Check permissions
sudo ls -la /home/username/.ssh/
# Should be: drwx------ (700) for .ssh
#            -rw------- (600) for authorized_keys

# 3. Fix permissions if needed
sudo chmod 700 /home/username/.ssh
sudo chmod 600 /home/username/.ssh/authorized_keys
sudo chown -R username:username /home/username/.ssh
```

### Issue: User can't use sudo

**Solution:**
```bash
# Check if user is in sudo/wheel group
groups username

# Add to sudo group (Ubuntu/Debian)
sudo usermod -aG sudo username

# Add to wheel group (Oracle Linux/CentOS)
sudo usermod -aG wheel username

# User needs to logout and login again
```

### Issue: "Permission denied (publickey)"

**Check on team member's machine:**
```bash
# 1. Verify they're using the correct key
ssh -v -p 2222 username@YOUR_VPS_IP
# Look for "Offering public key" messages

# 2. Verify key matches
cat ~/.ssh/id_ed25519.pub
# Compare with authorized_keys on server
```

---

## Integration with Your Workflow

### 1. Onboarding Checklist

- [ ] Get new team member's SSH public key
- [ ] Run `add-user.sh` on VPS
- [ ] Decide on sudo access (y/n)
- [ ] Send connection details to team member
- [ ] Verify they can connect
- [ ] Verify sudo works (if granted)

### 2. Offboarding Checklist

```bash
# Disable user immediately
sudo passwd -l username
sudo mv /home/username/.ssh/authorized_keys /home/username/.ssh/authorized_keys.disabled

# After handover period, remove user
sudo userdel -r username

# Audit other access (databases, services, etc.)
```

---

## Comparison: add-user.sh vs vps-initial-setup.sh

| Task | add-user.sh | vps-initial-setup.sh |
|------|-------------|----------------------|
| **Purpose** | User management | System hardening |
| **Run frequency** | Many times | Once |
| **Creates users** | ✅ (with full permissions) | ❌ |
| **SSH hardening** | ❌ | ✅ |
| **Configures firewall** | ❌ | ✅ |
| **Configures fail2ban** | ❌ | ✅ |
| **Grants Docker access** | ✅ (Infra Admin type) | ❌ |
| **Safe to run repeatedly** | ✅ | ✅ |

**Note:** `vps-initial-setup.sh` focuses only on system hardening. All user creation (including your first Infra Admin) is done via `add-user.sh`.

---

## Tips

1. **Keep the script on the VPS** for easy access:
   ```bash
   sudo cp add-user.sh /usr/local/bin/add-user
   sudo chmod +x /usr/local/bin/add-user
   # Now run from anywhere: sudo add-user
   ```

2. **Document your team**:
   ```bash
   # Create a team roster
   cat > /root/team-roster.txt <<EOF
   alice - alice@company.com - sudo - added 2025-11-22
   bob - bob@company.com - no sudo - added 2025-11-23
   EOF
   ```

3. **Rotate SSH keys** periodically for security

4. **Use descriptive usernames** that match real names or roles

---

## Next Steps

After adding users, consider:

1. **Setup project directories**
   ```bash
   sudo mkdir -p /var/www/project
   sudo chown -R alice:alice /var/www/project
   ```

2. **Configure Git** access for deployments

3. **Setup monitoring** to track user activity

4. **Document team access** in your internal wiki

---

**Last Updated:** 2025-12-18
**Version:** 2.0.0
