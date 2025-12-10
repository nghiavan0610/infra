# GitHub Actions Self-Hosted Runner

Run GitHub Actions workflows on your own infrastructure.

## Why Self-Hosted?

| GitHub-Hosted | Self-Hosted |
|---------------|-------------|
| Pay per minute | Free unlimited |
| 2 vCPU, 7GB RAM | Your hardware |
| No network access | Access to infra |
| Clean environment | Persistent tools |

## Setup

### 1. Get Registration Token

```bash
# Go to your GitHub repo or org:
# Repo:  Settings → Actions → Runners → New self-hosted runner
# Org:   Settings → Actions → Runners → New runner

# Copy the token (starts with AAAAA...)
```

### 2. Configure

```bash
cp .env.example .env

# Edit .env:
GITHUB_RUNNER_TOKEN=AAAAA...your-token
GITHUB_REPO_URL=https://github.com/username/repo
```

### 3. Start

```bash
docker compose up -d

# Check status
docker logs -f github-runner
```

### 4. Verify

Go to GitHub → Settings → Actions → Runners

You should see your runner with status "Idle".

## Usage in Workflows

```yaml
# .github/workflows/deploy.yml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    # Use your self-hosted runner
    runs-on: self-hosted
    # Or with specific labels:
    # runs-on: [self-hosted, linux, docker]

    steps:
      - uses: actions/checkout@v4

      - name: Deploy to production
        run: |
          # This runs on YOUR VPS, can access internal network
          docker compose -f /path/to/app/docker-compose.yml up -d
```

## Runner Labels

Default labels (automatic):
- `self-hosted`
- `linux`
- `x64`

Custom labels (set in .env):
- `docker` - has Docker access
- `production` - production environment

Use in workflow:
```yaml
runs-on: [self-hosted, docker, production]
```

## Security Considerations

### Ephemeral Mode (Recommended)

```bash
# .env
GITHUB_RUNNER_EPHEMERAL=true
```

Runner exits after each job, preventing:
- State leakage between jobs
- Malicious code persistence

### Public Repos Warning

**Don't use self-hosted runners for public repos!**

Anyone can submit a PR that runs code on your runner.

### Docker Socket Access

The runner has access to Docker socket. Jobs can:
- Run any container
- Access other containers on the network
- Mount host volumes

Only allow trusted workflows.

## Multiple Runners

For multiple runners, use different names:

```bash
# Runner 1
GITHUB_RUNNER_NAME=runner-1

# Runner 2 (copy docker-compose.yml, change container_name)
GITHUB_RUNNER_NAME=runner-2
```

Or use Docker Compose scale:
```bash
docker compose up -d --scale github-runner=3
```

## Troubleshooting

### Runner not showing in GitHub

```bash
# Check logs
docker logs github-runner

# Common issues:
# - Invalid token (tokens expire after 1 hour)
# - Wrong REPO_URL format
```

### Jobs stuck in "Queued"

- Check runner is online in GitHub UI
- Verify `runs-on` labels match your runner
- Check runner isn't busy with another job

### Permission denied on Docker

```bash
# Runner needs access to Docker socket
# Check socket permissions:
ls -la /var/run/docker.sock
```
