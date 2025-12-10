# Gitea

Lightweight self-hosted Git service - GitHub/GitLab alternative.

## Quick Start

```bash
# Generate security keys
echo "GITEA_SECRET_KEY=$(openssl rand -hex 32)" >> .env
echo "GITEA_INTERNAL_TOKEN=$(openssl rand -hex 32)" >> .env

# Start Gitea
docker compose up -d

# Access UI
open http://localhost:3000
```

## First Setup

1. Open http://localhost:3000
2. Complete the installation wizard
3. Create admin account

## Features

- **Git Hosting** - Repositories, branches, tags
- **Pull Requests** - Code review, merge strategies
- **Issues** - Issue tracking, labels, milestones
- **CI/CD** - Gitea Actions (GitHub Actions compatible)
- **Wiki** - Per-repository documentation
- **Packages** - Container registry, npm, pip, etc.
- **Organizations** - Team management
- **Webhooks** - Integration with external services

## Git Operations

### Clone Repository
```bash
# HTTPS
git clone http://localhost:3000/user/repo.git

# SSH
git clone ssh://git@localhost:2222/user/repo.git
```

### SSH Keys
1. Go to Settings > SSH/GPG Keys
2. Add your public key (`~/.ssh/id_rsa.pub`)

## Configuration

Edit `.env`:
- `GITEA_ROOT_URL` - Public URL for Gitea
- `GITEA_HTTP_PORT` - Web interface port (default: 3000)
- `GITEA_SSH_PORT` - SSH port (default: 2222)
- `GITEA_DISABLE_REGISTRATION` - Disable new user registration
- `GITEA_REQUIRE_SIGNIN` - Require login to view anything

## Using Shared PostgreSQL

To use the shared infra PostgreSQL instead of dedicated:

1. Create database and user:
   ```bash
   cd ../databases/postgres-single
   ./scripts/create-user.sh gitea gitea_password gitea
   ```

2. Update `.env`:
   ```bash
   GITEA_DB_HOST=postgres:5432
   ```

3. Comment out `gitea-db` service in docker-compose.yml

## Gitea Actions (CI/CD)

Gitea Actions is compatible with GitHub Actions.

1. Enable Actions in admin settings
2. Set up a runner:
   ```bash
   docker run -d --name gitea-runner \
     -v /var/run/docker.sock:/var/run/docker.sock \
     gitea/act_runner:latest
   ```

3. Create `.gitea/workflows/ci.yml` in your repo:
   ```yaml
   name: CI
   on: [push, pull_request]
   jobs:
     test:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v4
         - run: npm test
   ```

## Webhooks

### Integrate with Drone CI
1. Go to Repository > Settings > Webhooks
2. Add webhook URL: `http://drone:80/hook`
3. Select events: Push, Pull Request

### Other Integrations
- Discord notifications
- Slack notifications
- Custom webhooks

## Mirror Repositories

Mirror from GitHub/GitLab:

1. New Repository > Migration
2. Enter source URL
3. Enable "This repository will be a mirror"

## Backup

```bash
# Backup all data
docker run --rm \
  -v gitea_data:/data \
  -v gitea_config:/config \
  -v $(pwd):/backup \
  alpine tar czf /backup/gitea-backup.tar.gz /data /config

# Backup database
docker exec gitea-db pg_dump -U gitea gitea > gitea-db-backup.sql
```

## Security Best Practices

1. **Disable Registration** after creating needed accounts:
   ```bash
   GITEA_DISABLE_REGISTRATION=true
   ```

2. **Require Sign-in** to view repositories:
   ```bash
   GITEA_REQUIRE_SIGNIN=true
   ```

3. **Use SSH Keys** instead of passwords for Git operations

4. **Enable 2FA** for all users in user settings

## Exposing via Traefik

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.gitea.rule=Host(`git.example.com`)"
  - "traefik.http.routers.gitea.entrypoints=websecure"
  - "traefik.http.routers.gitea.tls.certresolver=letsencrypt"
```

Update `.env`:
```bash
GITEA_ROOT_URL=https://git.example.com
GITEA_SSH_DOMAIN=git.example.com
```
