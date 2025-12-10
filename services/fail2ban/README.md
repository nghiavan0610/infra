# Fail2ban - Brute-Force Protection

Intrusion prevention that bans IPs showing malicious signs (too many password failures, seeking exploits, etc.).

## Quick Start

```bash
cp .env.example .env
docker compose up -d
```

## What It Protects

| Service | Protection |
|---------|------------|
| SSH | Failed login attempts |
| Traefik | 401/403 responses |
| Docker apps | Auth failures in container logs |

## How It Works

```
Attacker tries 5 failed logins
         │
         ▼
Fail2ban detects pattern in logs
         │
         ▼
IP gets banned via iptables
         │
         ▼
Attacker blocked for 1 hour
```

## Configuration

### Adjust Ban Settings

Edit `config/jail.local`:

```ini
[DEFAULT]
bantime = 3600      # 1 hour ban
findtime = 600      # 10 minute window
maxretry = 5        # 5 attempts allowed
```

### Whitelist IPs

```ini
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1 YOUR.OFFICE.IP.HERE
```

### Enable/Disable Jails

```ini
[nginx-http-auth]
enabled = true   # Change to false to disable
```

## Commands

```bash
# Check status
docker exec fail2ban fail2ban-client status

# Check specific jail
docker exec fail2ban fail2ban-client status sshd

# Unban an IP
docker exec fail2ban fail2ban-client set sshd unbanip 1.2.3.4

# Ban an IP manually
docker exec fail2ban fail2ban-client set sshd banip 1.2.3.4

# View banned IPs
docker exec fail2ban fail2ban-client get sshd banned
```

## Add Custom Filter

1. Create filter in `config/filter.d/myapp.conf`:
```ini
[Definition]
failregex = ^<HOST>.*authentication failed
ignoreregex =
```

2. Add jail in `config/jail.local`:
```ini
[myapp]
enabled = true
port = http,https
filter = myapp
logpath = /var/log/myapp/access.log
maxretry = 5
```

3. Restart: `docker compose restart`

## Host-Based Installation (Alternative)

For better reliability, install directly on host:

```bash
# Ubuntu/Debian
sudo apt install fail2ban

# Copy config
sudo cp config/jail.local /etc/fail2ban/jail.local

# Restart
sudo systemctl restart fail2ban
```

## Monitoring

Check fail2ban in your observability stack:

```bash
# Add to observability/targets/applications.json
# Fail2ban exports metrics at localhost:9191 with fail2ban-exporter
```
