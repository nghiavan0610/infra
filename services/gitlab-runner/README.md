# GitLab CI/CD Self-Hosted Runner

Run GitLab CI/CD pipelines on your own infrastructure.

## Setup

### 1. Get Registration Token

```bash
# GitLab.com or self-hosted GitLab:
# Project → Settings → CI/CD → Runners → Expand → New project runner

# Copy the registration token (starts with glrt-...)
```

### 2. Register Runner

```bash
# Interactive registration
docker compose run --rm gitlab-runner register
```

You'll be prompted for:

| Prompt | Value |
|--------|-------|
| GitLab instance URL | `https://gitlab.com/` or your self-hosted URL |
| Registration token | `glrt-xxxxxxxxxxxx` |
| Description | `my-vps-runner` |
| Tags | `self-hosted,docker,production` |
| Executor | `docker` |
| Default Docker image | `docker:24.0` |

### 3. Configure Docker-in-Docker

Edit `config/config.toml` after registration:

```toml
[[runners]]
  name = "my-vps-runner"
  url = "https://gitlab.com/"
  token = "glrt-xxxxxxxxxxxx"
  executor = "docker"
  [runners.docker]
    image = "docker:24.0"
    privileged = false
    disable_entrypoint_overwrite = false
    oom_kill_disable = false
    disable_cache = false
    # Mount Docker socket for building images
    volumes = ["/var/run/docker.sock:/var/run/docker.sock", "/cache"]
    # Use host network for accessing infra services
    network_mode = "infra"
    shm_size = 0
```

### 4. Start Runner

```bash
docker compose up -d

# Check status
docker logs -f gitlab-runner
```

### 5. Verify

Go to GitLab → Project → Settings → CI/CD → Runners

You should see your runner with a green circle (online).

## Usage in .gitlab-ci.yml

```yaml
# .gitlab-ci.yml
stages:
  - build
  - deploy

build:
  stage: build
  # Use your self-hosted runner
  tags:
    - self-hosted
    - docker
  image: node:20
  script:
    - npm ci
    - npm run build

deploy:
  stage: deploy
  tags:
    - self-hosted
    - production
  script:
    # This runs on YOUR VPS, can access internal network
    - docker compose -f /path/to/app/docker-compose.yml up -d
  only:
    - main
```

## Runner Tags

Set during registration. Common tags:
- `self-hosted` - identifies as self-hosted
- `docker` - has Docker access
- `production` - production environment
- `linux` - Linux runner

Use in `.gitlab-ci.yml`:
```yaml
job:
  tags:
    - self-hosted
    - docker
```

## Multiple Runners

### Option 1: Multiple Registrations

```bash
# Register additional runners (creates new entries in config.toml)
docker compose run --rm gitlab-runner register
```

### Option 2: Concurrent Jobs

Edit `config/config.toml`:
```toml
concurrent = 4  # Run up to 4 jobs simultaneously
```

## Executors

| Executor | Use Case |
|----------|----------|
| `docker` | Most common, runs each job in a container |
| `shell` | Runs directly on host (less secure) |
| `docker+machine` | Auto-scales with Docker Machine |
| `kubernetes` | For K8s clusters |

## Security Considerations

### Protected Runners

In GitLab → Project → Settings → CI/CD → Runners:
- Enable "Protected" to only run on protected branches
- Enable "Run untagged jobs" carefully

### Docker Socket Access

Jobs can access Docker daemon. This allows:
- Building images
- Running containers
- Accessing other containers

**Only use for trusted projects!**

### Privileged Mode

```toml
[runners.docker]
  privileged = false  # Keep false unless needed
```

Only enable for Docker-in-Docker builds requiring it.

## Troubleshooting

### Runner not connecting

```bash
# Check logs
docker logs gitlab-runner

# Verify registration
docker compose exec gitlab-runner gitlab-runner verify
```

### Jobs stuck in "Pending"

- Check runner is online in GitLab UI
- Verify tags match your `.gitlab-ci.yml`
- Check runner isn't paused

### "No space left on device"

```bash
# Clean up Docker
docker system prune -af

# Or increase runner cache cleanup
# In config.toml:
[runners.docker]
  pull_policy = "if-not-present"
```

### Permission denied

```bash
# Check Docker socket permissions
ls -la /var/run/docker.sock

# May need to add gitlab-runner to docker group
```

## Unregister Runner

```bash
# List runners
docker compose exec gitlab-runner gitlab-runner list

# Unregister specific runner
docker compose exec gitlab-runner gitlab-runner unregister --name "my-vps-runner"

# Unregister all
docker compose exec gitlab-runner gitlab-runner unregister --all-runners
```
