# Vaultwarden

Self-hosted Bitwarden-compatible password manager.

## Quick Start

```bash
# Generate admin token
echo "VAULTWARDEN_ADMIN_TOKEN=$(openssl rand -base64 48)" >> .env

# Start Vaultwarden
docker compose up -d

# Access web vault
open http://localhost:8222
```

## First Setup

1. Open http://localhost:8222
2. Click "Create Account"
3. Create your master password (REMEMBER THIS - cannot be recovered!)
4. Start adding passwords

## Clients

Vaultwarden works with all official Bitwarden clients:

### Browser Extensions
- [Chrome](https://chrome.google.com/webstore/detail/bitwarden/nngceckbapebfimnlniiiahkandclblb)
- [Firefox](https://addons.mozilla.org/firefox/addon/bitwarden-password-manager/)
- [Safari](https://apps.apple.com/app/bitwarden/id1352778147)
- [Edge](https://microsoftedge.microsoft.com/addons/detail/bitwarden/jbkfoedolllekgbhcbcoahefnbanhhlh)

### Desktop Apps
- [Windows/Mac/Linux](https://bitwarden.com/download/)

### Mobile Apps
- [iOS](https://apps.apple.com/app/bitwarden/id1137397744)
- [Android](https://play.google.com/store/apps/details?id=com.x8bit.bitwarden)

### CLI
```bash
npm install -g @bitwarden/cli
bw config server http://localhost:8222
bw login
```

## Configure Clients

When setting up clients, change the server URL:

1. On login screen, click "Self-hosted"
2. Enter: `http://localhost:8222`
3. For production with SSL: `https://vault.yourdomain.com`

## Admin Panel

Access admin settings at: http://localhost:8222/admin

Use the `VAULTWARDEN_ADMIN_TOKEN` from `.env` to login.

Admin panel allows:
- View/delete users
- Invite users
- View organizations
- Server configuration

## Configuration

Edit `.env`:

```bash
# Disable new signups after creating your accounts
SIGNUPS_ALLOWED=false

# Require email verification
SIGNUPS_VERIFY=true
```

## Email Setup

Required for:
- Password reset
- Email verification
- User invitations

### Gmail Example
```bash
VAULTWARDEN_SMTP_HOST=smtp.gmail.com
VAULTWARDEN_SMTP_PORT=587
VAULTWARDEN_SMTP_FROM=your-email@gmail.com
VAULTWARDEN_SMTP_SECURITY=starttls
VAULTWARDEN_SMTP_USERNAME=your-email@gmail.com
VAULTWARDEN_SMTP_PASSWORD=your-app-password
```

### With Mailpit (local testing)
```bash
VAULTWARDEN_SMTP_HOST=mailpit
VAULTWARDEN_SMTP_PORT=1025
VAULTWARDEN_SMTP_FROM=vaultwarden@localhost
VAULTWARDEN_SMTP_SECURITY=off
```

## Exposing via Traefik (Production)

1. Edit docker-compose.yml - uncomment Traefik labels
2. Set domain in `.env`:
   ```bash
   VAULTWARDEN_DOMAIN=https://vault.example.com
   VAULTWARDEN_HOST=vault.example.com
   ```
3. Restart: `docker compose up -d`

## Organizations (Teams)

Share passwords with team members:

1. Create Organization in web vault
2. Invite team members
3. Create collections for different access levels
4. Assign passwords to collections

## Security Best Practices

1. **Use strong master password** - This is the only password you need to remember

2. **Enable 2FA** - Go to Settings > Two-step Login

3. **Disable signups after setup**:
   ```bash
   SIGNUPS_ALLOWED=false
   ```

4. **Use HTTPS** - Always use SSL in production

5. **Regular backups** - Backup the data volume

## Backup

```bash
# Backup data
docker run --rm -v vaultwarden_data:/data -v $(pwd):/backup alpine \
    tar czf /backup/vaultwarden-backup.tar.gz /data

# The most important files:
# - db.sqlite3 (database)
# - rsa_key.pem, rsa_key.pub.pem (encryption keys)
# - attachments/ (file attachments)
```

## Restore

```bash
# Stop Vaultwarden
docker compose down

# Restore data
docker run --rm -v vaultwarden_data:/data -v $(pwd):/backup alpine \
    tar xzf /backup/vaultwarden-backup.tar.gz -C /

# Start Vaultwarden
docker compose up -d
```

## Import from Other Password Managers

1. Export from old password manager (1Password, LastPass, etc.)
2. In Vaultwarden web vault: Tools > Import Data
3. Select format and upload file

## Vaultwarden vs Bitwarden

| Feature | Vaultwarden | Bitwarden (Official) |
|---------|-------------|---------------------|
| Cost | Free (self-hosted) | Free tier + paid plans |
| Hosting | Your server | Their cloud |
| Resources | ~50MB RAM | ~2GB RAM (self-hosted) |
| Features | Most features | All features |
| Support | Community | Official support |

Vaultwarden is ideal for self-hosting due to its lightweight footprint.
