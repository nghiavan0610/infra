# Drone CI

Container-native CI/CD platform with Git integration.

## Quick Start

```bash
# Generate RPC secret
echo "DRONE_RPC_SECRET=$(openssl rand -hex 16)" >> .env

# Configure Git provider (see below)
# Then start Drone
docker compose up -d

# Access UI
open http://localhost:8080
```

## Git Provider Setup

### Option 1: Gitea Integration

1. In Gitea, go to **Settings** > **Applications**
2. Create new **OAuth2 Application**:
   - Application Name: `Drone CI`
   - Redirect URI: `http://localhost:8080/login`
3. Copy Client ID and Secret to `.env`:
   ```bash
   DRONE_GITEA_CLIENT_ID=your-client-id
   DRONE_GITEA_CLIENT_SECRET=your-client-secret
   ```

### Option 2: GitHub Integration

1. Go to GitHub **Settings** > **Developer settings** > **OAuth Apps**
2. Create new OAuth App:
   - Application Name: `Drone CI`
   - Homepage URL: `http://localhost:8080`
   - Authorization callback URL: `http://localhost:8080/login`
3. Update `.env`:
   ```bash
   # Comment out Gitea vars, add:
   DRONE_GITHUB_CLIENT_ID=your-client-id
   DRONE_GITHUB_CLIENT_SECRET=your-client-secret
   ```
4. Update docker-compose.yml to use GitHub environment variables

### Option 3: GitLab Integration

1. In GitLab, go to **Preferences** > **Applications**
2. Create new application:
   - Name: `Drone CI`
   - Redirect URI: `http://localhost:8080/login`
   - Scopes: `api`, `read_user`
3. Update `.env` and docker-compose.yml accordingly

## First Login

1. Open http://localhost:8080
2. Login with your Git provider account
3. Authorize Drone access
4. Sync repositories

## Pipeline Configuration

Create `.drone.yml` in your repository:

```yaml
kind: pipeline
type: docker
name: default

steps:
  - name: test
    image: node:20
    commands:
      - npm install
      - npm test

  - name: build
    image: node:20
    commands:
      - npm run build
    depends_on:
      - test

  - name: deploy
    image: docker:dind
    commands:
      - docker build -t myapp .
      - docker push myapp
    depends_on:
      - build
    when:
      branch:
        - main
```

## Pipeline Examples

### Node.js
```yaml
kind: pipeline
type: docker
name: nodejs

steps:
  - name: install
    image: node:20
    commands:
      - npm ci

  - name: lint
    image: node:20
    commands:
      - npm run lint

  - name: test
    image: node:20
    commands:
      - npm test
```

### Go
```yaml
kind: pipeline
type: docker
name: golang

steps:
  - name: test
    image: golang:1.22
    commands:
      - go test ./...

  - name: build
    image: golang:1.22
    commands:
      - go build -o app
```

### Python
```yaml
kind: pipeline
type: docker
name: python

steps:
  - name: test
    image: python:3.12
    commands:
      - pip install -r requirements.txt
      - pytest
```

### Docker Build & Push
```yaml
kind: pipeline
type: docker
name: docker

steps:
  - name: build
    image: plugins/docker
    settings:
      repo: registry.example.com/myapp
      registry: registry.example.com
      username:
        from_secret: docker_username
      password:
        from_secret: docker_password
      tags:
        - latest
        - ${DRONE_COMMIT_SHA:0:8}
```

## Secrets

Store sensitive data as secrets:

1. Go to repository settings in Drone
2. Add secrets (e.g., `docker_password`)
3. Reference in pipeline:
   ```yaml
   settings:
     password:
       from_secret: docker_password
   ```

## Services

Run services alongside your build:

```yaml
kind: pipeline
type: docker
name: default

services:
  - name: postgres
    image: postgres:16
    environment:
      POSTGRES_PASSWORD: test

  - name: redis
    image: redis:7

steps:
  - name: test
    image: node:20
    environment:
      DATABASE_URL: postgres://postgres:test@postgres:5432/postgres
      REDIS_URL: redis://redis:6379
    commands:
      - npm test
```

## Conditional Steps

```yaml
steps:
  - name: deploy-staging
    when:
      branch:
        - develop

  - name: deploy-production
    when:
      branch:
        - main
      event:
        - push

  - name: notify
    when:
      status:
        - success
        - failure
```

## Cron Jobs

Schedule pipelines:

1. Go to repository settings
2. Add cron job with schedule (e.g., `0 0 * * *` for daily)

## Configuration

Edit `.env`:
- `DRONE_RPC_SECRET` - Shared secret between server and runner
- `DRONE_RUNNER_CAPACITY` - Concurrent builds (default: 2)
- `DRONE_ADMIN_USER` - Admin username from Git provider

## Multiple Runners

Scale with more runners:

```bash
docker run -d \
  --name drone-runner-2 \
  -e DRONE_RPC_HOST=drone \
  -e DRONE_RPC_SECRET=your-secret \
  -e DRONE_RUNNER_NAME=runner-2 \
  -e DRONE_RUNNER_CAPACITY=2 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --network infra-network \
  drone/drone-runner-docker:1
```

## Exposing via Traefik

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.drone.rule=Host(`ci.example.com`)"
  - "traefik.http.routers.drone.entrypoints=websecure"
  - "traefik.http.routers.drone.tls.certresolver=letsencrypt"
```

Update `.env`:
```bash
DRONE_SERVER_HOST=ci.example.com
DRONE_SERVER_PROTO=https
```

Update Git provider OAuth redirect URI to `https://ci.example.com/login`

## Troubleshooting

### Builds not starting
- Check runner is connected: `docker logs drone-runner`
- Verify RPC_SECRET matches between server and runner

### OAuth errors
- Verify redirect URI matches exactly
- Check client ID/secret are correct

### Permission denied
- Ensure admin user matches your Git username
- Check DRONE_USER_FILTER if set
