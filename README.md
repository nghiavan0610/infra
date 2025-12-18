# Infrastructure Stack

Production-ready, self-hosted infrastructure with one-command setup.

## Quick Start

```bash
# On a new server (requires GitHub SSH key - see SETUP.md Step 0):
sudo mkdir -p /opt/infra && sudo chown $USER:$USER /opt/infra
git clone git@github.com:nghiavan0610/infra.git /opt/infra
cd /opt/infra

# Set admin password (first time)
./setup.sh --set-password

# Edit services to enable
nano services.conf

# Start everything
./setup.sh

# Secure file permissions (prevents other users from reading credentials)
./secure.sh
```

## Structure

```
infra/
├── setup.sh              # Start services
├── stop.sh               # Stop services
├── status.sh             # Check status
├── secure.sh             # Set file permissions
├── test.sh               # Validate all configurations
├── services.conf         # Enable/disable services
│
├── lib/                  # Shared code
│   ├── common.sh         # Logging, colors, utilities
│   ├── database.sh       # Database functions
│   ├── db-cli.sh         # Database management CLI
│   └── app-cli.sh        # Application registration CLI
│
├── scripts/              # Setup & utility scripts
│   ├── vps-initial-setup.sh    # First-time VPS hardening
│   ├── docker-install.sh       # Install Docker
│   ├── add-user.sh             # Add users (Developer/DevOps/Infra Admin)
│   ├── audit-access.sh         # Audit who has access to what
│   ├── reset-password.sh       # Reset admin password (requires sudo)
│   ├── production-checklist.sh # Verify production readiness
│   ├── vps-health-check.sh     # Server health monitoring
│   ├── db-cli.sh               # → lib/db-cli.sh (symlink)
│   └── app-cli.sh              # → lib/app-cli.sh (symlink)
│
└── services/             # All services (45+)
    ├── postgres/
    ├── redis/
    ├── mongo/
    ├── traefik/
    ├── observability/
    ├── langfuse/
    ├── github-runner/
    └── ...
```

## Commands

| Command | Description |
|---------|-------------|
| `./setup.sh` | Start services from services.conf |
| `./setup.sh --set-password` | Set admin password |
| `./setup.sh --minimal` | Start minimal preset |
| `./setup.sh --standard` | Start standard preset |
| `./stop.sh` | Stop all services |
| `./stop.sh --prune` | Stop all + clean unused images/containers |
| `./stop.sh --prune-all` | Stop all + clean images AND volumes (data loss!) |
| `./status.sh` | Check service status |
| `./secure.sh` | Secure file permissions (owner only) |
| `./secure.sh --group NAME` | Secure for admin group |
| `./secure.sh --check` | Audit current permissions |
| `./test.sh` | Validate all configurations |
| `./test.sh --verbose` | Detailed validation output |
| `bash scripts/production-checklist.sh` | Verify production readiness |

## Services

### Databases
| Service | Key | Containers | Description |
|---------|-----|------------|-------------|
| PostgreSQL | `postgres` | `postgres` | Single node database |
| PostgreSQL HA | `postgres-ha` | `postgres-master`, `postgres-replica` | Primary + replica |
| Redis | `redis` | `redis-cache`, `redis-queue` | Cache (LRU) + Queue (persistent) |
| MongoDB | `mongo` | `mongo-primary`, `mongo-secondary`, `mongo-arbiter` | Replica set |
| TimescaleDB | `timescaledb` | `timescaledb` | Time-series database |
| MySQL | `mysql` | `mysql` | MySQL 8.0 |
| ClickHouse | `clickhouse` | `clickhouse` | Analytics (OLAP) |

### Message Queues
| Service | Key | Description |
|---------|-----|-------------|
| NATS | `nats` | Lightweight messaging |
| Kafka | `kafka` | Event streaming |
| RabbitMQ | `rabbitmq` | Traditional MQ |
| Asynq | `asynq` | Redis task queue UI |

### Storage
| Service | Key | Description |
|---------|-----|-------------|
| Garage | `garage` | S3-compatible (light) |
| MinIO | `minio` | S3-compatible (full) |

### Search & Vector
| Service | Key | Description |
|---------|-----|-------------|
| Meilisearch | `meilisearch` | Fast search |
| OpenSearch | `opensearch` | Elasticsearch fork |
| Qdrant | `qdrant` | Vector database (AI/embeddings) |

### AI / LLM
| Service | Key | Description |
|---------|-----|-------------|
| LangFuse | `langfuse` | LLM observability (traces, costs, prompts) |
| Faster Whisper | `faster-whisper` | Speech-to-text AI |

### Security
| Service | Key | Description |
|---------|-----|-------------|
| Fail2ban | `fail2ban` | Brute-force protection |
| Crowdsec | `crowdsec` | WAF + threat intel |
| Authentik | `authentik` | SSO provider |
| Vault | `vault` | Secrets management |

### Monitoring
| Service | Key | Description |
|---------|-----|-------------|
| Observability | `observability` | Grafana, Prometheus, Loki |
| Uptime Kuma | `uptime-kuma` | Status page |
| Backup | `backup` | Restic backups |

### Tools
| Service | Key | Description |
|---------|-----|-------------|
| Traefik | `traefik` | Reverse proxy + SSL |
| Portainer | `portainer` | Docker UI |
| n8n | `n8n` | Workflow automation |
| Registry | `registry` | Docker registry |

### CI/CD Runners
| Service | Key | Description |
|---------|-----|-------------|
| GitHub Runner | `github-runner` | GitHub Actions self-hosted runner |
| GitLab Runner | `gitlab-runner` | GitLab CI/CD self-hosted runner |
| Gitea | `gitea` | Self-hosted Git service |
| Drone | `drone` | CI/CD platform (works with Gitea) |

## CI/CD Runners

Self-hosted runners let you run CI/CD jobs on your own infrastructure with direct access to the `infra` network.

### GitHub Actions Runner

```bash
# 1. Enable
# Edit services.conf: github-runner=true

# 2. Get token from GitHub
# Repo → Settings → Actions → Runners → New self-hosted runner
# Copy token (starts with AAAAA...)

# 3. Configure
cp services/github-runner/.env.example services/github-runner/.env
nano services/github-runner/.env
# Set: GITHUB_RUNNER_TOKEN=AAAAA...
# Set: GITHUB_REPO_URL=https://github.com/username/repo

# 4. Start
./setup.sh
```

Use in workflow:
```yaml
# .github/workflows/deploy.yml
jobs:
  deploy:
    runs-on: self-hosted  # Uses your runner
    steps:
      - uses: actions/checkout@v4
      - run: docker compose up -d  # Direct access to VPS!
```

### GitLab CI/CD Runner

```bash
# 1. Enable
# Edit services.conf: gitlab-runner=true

# 2. Start container first
cd services/gitlab-runner
docker compose up -d

# 3. Register runner (interactive)
docker compose run --rm gitlab-runner register
# URL: https://gitlab.com/
# Token: glrt-xxx (from GitLab → Settings → CI/CD → Runners)
# Tags: self-hosted,docker
# Executor: docker
# Image: docker:24.0

# 4. Restart
docker compose restart
```

Use in `.gitlab-ci.yml`:
```yaml
deploy:
  tags:
    - self-hosted
    - docker
  script:
    - docker compose up -d  # Direct access to VPS!
```

### Why Self-Hosted?

| Feature | Cloud Runner | Self-Hosted |
|---------|--------------|-------------|
| Cost | Pay per minute | Free |
| Network | No internal access | Access `infra` network |
| Resources | Limited | Your hardware |
| Deploy | Need SSH/API keys | Direct Docker access |

## LLM Observability (LangFuse)

Track LLM calls, costs, and prompts for your AI applications.

### Setup

```bash
# 1. Enable (uses shared postgres + redis)
# Edit services.conf:
#   postgres=true
#   redis=true
#   langfuse=true

# 2. Start (setup.sh auto-generates secrets and creates database)
./setup.sh

# 3. Open http://localhost:3050 and create account
```

> **Note:** LangFuse uses shared PostgreSQL and Redis. The database `langfuse` is automatically created by setup.sh.

### Integration (Python)

```python
from langfuse.callback import CallbackHandler

handler = CallbackHandler(
    host="http://langfuse:3000",  # From Docker network
    public_key="pk-lf-...",
    secret_key="sk-lf-..."
)

# LangChain
chain.run("Hello", callbacks=[handler])

# Or add to your .env:
# LANGFUSE_HOST=http://langfuse:3000
# LANGFUSE_PUBLIC_KEY=pk-lf-...
# LANGFUSE_SECRET_KEY=sk-lf-...
```

### What It Tracks

| Feature | Description |
|---------|-------------|
| Traces | Full LLM call chains |
| Costs | Token usage, API costs |
| Latency | Response times |
| Prompts | Version control |
| Scores | User feedback |

## Database Management

Unified CLI to manage users across all database types.

### Usage

```bash
# Syntax
./lib/db-cli.sh <database-type> <command> [args...]

# Or use the symlink
./scripts/db-cli.sh <database-type> <command> [args...]
```

### Supported Databases

| Type | Container | Description |
|------|-----------|-------------|
| `postgres` | postgres | PostgreSQL single node |
| `postgres-ha` | postgres-master | PostgreSQL with replica |
| `timescaledb` | timescaledb | TimescaleDB (time-series) |
| `mysql` | mysql | MySQL 8.0 |
| `mongo` | mongo | MongoDB replica set |
| `clickhouse` | clickhouse | ClickHouse (analytics) |

### Commands

| Command | Description |
|---------|-------------|
| `create-user <user> <pass> [db] [schema]` | Create user with optional database |
| `delete-user <user>` | Delete user, reassign owned objects |
| `delete-user <user> --drop-schema` | Delete user AND drop owned databases/schemas |
| `list-users` | List all database users |

### Examples

```bash
# PostgreSQL
./lib/db-cli.sh postgres create-user myapp secret123 mydb
./lib/db-cli.sh postgres list-users
./lib/db-cli.sh postgres delete-user myapp --drop-schema

# MySQL
./lib/db-cli.sh mysql create-user myapp secret123 mydb

# MongoDB
./lib/db-cli.sh mongo create-user myapp secret123 mydb

# TimescaleDB
./lib/db-cli.sh timescaledb create-user myapp secret123 mydb

# ClickHouse
./lib/db-cli.sh clickhouse create-user myapp secret123 mydb
```

### Connection Strings

After creating a user, use these connection strings from your app:

| Database | Connection String |
|----------|-------------------|
| PostgreSQL | `postgresql://myapp:secret@postgres:5432/mydb` |
| PostgreSQL HA | `postgresql://myapp:secret@postgres-master:5432/mydb` |
| TimescaleDB | `postgresql://myapp:secret@timescaledb:5432/mydb` |
| MySQL | `mysql://myapp:secret@mysql:3306/mydb` |
| MongoDB | `mongodb://myapp:secret@mongo-primary:27017/mydb?replicaSet=rs0` |
| Redis Cache | `redis://:password@redis-cache:6379` |
| Redis Queue | `redis://:password@redis-queue:6379` |

## Shared Services Architecture

Services use shared databases instead of bundling their own. This reduces resource usage and simplifies management.

### Shared Databases

| Shared Service | Used By |
|----------------|---------|
| **postgres** | Authentik, Gitea, Healthchecks, LangFuse, Plausible, GlitchTip, n8n |
| **redis** | Authentik, LangFuse, GlitchTip, Asynq |
| **clickhouse** | Plausible, LangFuse (optional) |

### How It Works

1. **setup.sh** automatically creates databases for each service in the shared postgres/clickhouse
2. Services connect via Docker network using container names (e.g., `postgres:5432`)
3. Credentials are shared via `.env` files (generated from `.env.example`)

### Dependency Legend (in services.conf)

```
[standalone]     - No dependencies on other services
[requires: X]    - Must enable service X for this to work
[uses: X]        - Optionally connects to service X if enabled
```

Example: `plausible=false  # [requires: postgres, clickhouse]`

## Network Architecture

All services connect to a shared `infra` network for inter-service communication:

```
┌─────────────────────────────────────────────────────────────────┐
│                        infra network                            │
├─────────────────────────────────────────────────────────────────┤
│  Databases:                                                     │
│    postgres, redis-cache, redis-queue, mongo-primary,           │
│    timescaledb, mysql, clickhouse                               │
│                                                                 │
│  Your Apps:                                                     │
│    Connect with: networks: [infra] (external: true)             │
│                                                                 │
│  Monitoring:                                                    │
│    prometheus, grafana, loki (can scrape all services)          │
└─────────────────────────────────────────────────────────────────┘
```

Services are accessible by container name within the network:
- `postgres:5432` - PostgreSQL
- `redis-cache:6379` - Redis for caching
- `redis-queue:6379` - Redis for job queues
- `mongo-primary:27017` - MongoDB primary
- `langfuse:3000` - LangFuse API

## Connect Your Backend

### Option 1: Manual (You create .env + docker-compose)

**Step 1:** Create your `.env`:
```env
APP_NAME=myapi
PORT=8080
DATABASE_URL=postgresql://myapi:secret@postgres:5432/myapi_db
OTEL_EXPORTER_OTLP_ENDPOINT=http://alloy:4317
OTEL_SERVICE_NAME=myapi
```

**Step 2:** Create your `docker-compose.yml`:
```yaml
services:
  myapi:
    image: myapi:latest
    env_file:
      - .env
    networks:
      - infra

networks:
  infra:
    external: true
```

**Step 3:** Start and connect to observability:
```bash
docker compose up -d
/opt/infra/lib/app-cli.sh connect myapi --port 8080
```

Done! Your app now has logging, metrics, tracing, and alerting.

### Option 2: Auto-generate everything

```bash
# In your project folder - creates .env + docker-compose.yml
/opt/infra/lib/app-cli.sh init myapi --db postgres
/opt/infra/lib/app-cli.sh init myapi --db postgres --redis --domain api.example.com

# Then start
docker compose up -d
```

### App CLI Commands

| Command | Description |
|---------|-------------|
| `./lib/app-cli.sh connect <name> --port 8080` | Connect existing container to observability |
| `./lib/app-cli.sh init <name> --db postgres` | Generate .env + docker-compose.yml |
| `./lib/app-cli.sh list` | List registered apps |
| `./lib/app-cli.sh remove <name> --drop-db` | Remove app & database |

### What's Automatic

| Component | Monitoring | Action needed |
|-----------|------------|---------------|
| Infra DBs (postgres, redis, mongo) | ✅ Auto | None |
| Your Backend | ⚠️ Manual | Run `connect` command |

| Feature | How |
|---------|-----|
| Logging | Automatic - stdout/stderr → Loki |
| Metrics | `connect` command registers with Prometheus |
| Tracing | Add `OTEL_*` env vars to your .env |
| Alerting | Automatic if metrics are scraped |

## Deploy to New Server

### Option 1: One Command
```bash
curl -fsSL https://raw.githubusercontent.com/nghiavan0610/infra/main/bootstrap.sh | bash
```

### Option 2: Manual
```bash
# 1. Setup GitHub SSH key (see SETUP.md Step 0), then clone
sudo mkdir -p /opt/infra && sudo chown $USER:$USER /opt/infra
git clone git@github.com:nghiavan0610/infra.git /opt/infra
cd /opt/infra

# 2. (Optional) Setup VPS
sudo bash scripts/vps-initial-setup.sh

# 3. Install Docker
bash scripts/docker-install.sh

# 4. Configure & Start
./setup.sh --set-password
nano services.conf
./setup.sh
```

## Presets

| Preset | Services |
|--------|----------|
| `--minimal` | traefik, postgres, redis, observability, backup |
| `--standard` | minimal + garage, fail2ban, crowdsec, uptime-kuma |
| `--all` | Everything except alternatives |

## Configuration

### Enable a Service
```bash
# Edit services.conf
nano services.conf

# Change:
mongo=false
# To:
mongo=true

# Apply
./setup.sh
```

### Access Points
| Service | URL |
|---------|-----|
| Grafana | http://localhost:3000 |
| Prometheus | http://localhost:9090 |
| Traefik Dashboard | http://localhost:8080 |
| Uptime Kuma | http://localhost:3001 |
| Gitea | http://localhost:3002 |
| LangFuse | http://localhost:3050 |
| Plausible | http://localhost:8003 |
| GlitchTip | http://localhost:8001 |
| Healthchecks | http://localhost:8002 |
| Drone CI | http://localhost:8082 |
| Authentik | http://localhost:9000 |
| Portainer | http://localhost:9444 |
| Ntfy | http://localhost:8090 |
| Vaultwarden | http://localhost:8222 |
| ClickHouse | http://localhost:8123 |
| Adminer | http://localhost:8081 |

### Credentials
After setup, credentials are saved to `.secrets`:
```bash
cat .secrets
```

## Validation & Testing

Run the test script to validate all configurations before deploying:

```bash
# Run all tests
./test.sh

# Verbose output
./test.sh --verbose

# Quick syntax check only
./test.sh --quick
```

### What It Tests

| Test | Description |
|------|-------------|
| Docker | Docker and Docker Compose installed |
| Required files | setup.sh, stop.sh, services.conf exist |
| Compose syntax | All docker-compose.yml files valid |
| Network consistency | Services use infra network |
| Port conflicts | No duplicate port mappings |
| Script syntax | All bash scripts valid |

## Files Not in Git
```
.env              # Service configs
.secrets          # Generated passwords
.password_hash    # Admin password
*/data/           # Runtime data
*/certs/          # SSL certificates
```

## Security

### Security Model Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Security Layers                              │
├─────────────────────────────────────────────────────────────────┤
│ Layer 1: File Permissions (secure.sh)                          │
│   - /opt/infra = 700 (owner only)                              │
│   - .env files = 600                                           │
│   - Scripts = 700                                              │
├─────────────────────────────────────────────────────────────────┤
│ Layer 2: Script Authentication (require_auth)                   │
│   - All management scripts require password                     │
│   - Even with file access, still need password                  │
├─────────────────────────────────────────────────────────────────┤
│ Layer 3: Docker Access Control (add-user.sh)                   │
│   - Only "Infra Admin" type gets docker group access            │
│   - DevOps users can't run docker commands                      │
│   - Developers can't do anything privileged                     │
└─────────────────────────────────────────────────────────────────┘
```

### User Types

Add team members with appropriate access levels:

```bash
sudo bash scripts/add-user.sh
```

| Type | SSH | Sudo | Docker | Use Case |
|------|-----|------|--------|----------|
| **Developer** | ✅ | ❌ | ❌ | Application deployment only |
| **DevOps** | ✅ | ✅ | ❌ | System management (no container control) |
| **Infra Admin** | ✅ | ✅ | ✅ | Full infrastructure control |
| **Tunnel Only** | tunnel | ❌ | ❌ | DB access from local (no shell) |

**Important:** Only grant "Infra Admin" to trusted administrators. Users with Docker access can:
- Start/stop/remove ANY container
- Read secrets from running containers
- Access all databases directly

### Audit Access

Check who has access to what:

```bash
sudo bash scripts/audit-access.sh
```

Output shows:
- Users in docker group (can control containers)
- Users with sudo access
- Infrastructure directory permissions
- Security recommendations

### Password Protection

All scripts require admin password authentication:

```bash
./setup.sh --set-password  # Set password (first time)
./setup.sh                 # Requires password
./stop.sh                  # Requires password
./status.sh                # Requires password
./secure.sh                # Requires password
```

**Forgot your password?** Reset it with root access:

```bash
sudo bash scripts/reset-password.sh
```

### File Permissions

Run `./secure.sh` after setup to restrict access:

```bash
# Only your user can access (strictest)
./secure.sh

# Allow a group of admins
./secure.sh --group infra-admins

# Check current permissions
./secure.sh --check
```

| File Type | Permission | Description |
|-----------|------------|-------------|
| Directories | 700 | Owner only |
| Scripts (*.sh) | 700 | Owner execute only |
| Config files (*.yml, *.conf) | 644 | Readable (Docker needs this) |
| Sensitive files (.env, .secrets) | 600 | Owner only |

**Why config files are 644:** Docker containers run as different users (postgres, redis, etc.) and need to read mounted config files.

### Recommended Setup Flow

```bash
# 1. Initial VPS setup (hardens SSH, firewall, fail2ban)
sudo bash scripts/vps-initial-setup.sh

# 2. Install Docker (current user gets docker access)
bash scripts/docker-install.sh
exit  # Logout and login again for docker group

# 3. Setup infrastructure
cd /opt/infra
./setup.sh --set-password
./setup.sh
./secure.sh

# 4. Add team members (use appropriate type!)
sudo bash scripts/add-user.sh
#   - Developers: type 1 (SSH only)
#   - DevOps: type 2 (sudo, no docker)
#   - Infra Admins: type 3 (full access)
#   - Tunnel Only: type 4 (DB access from local)

# 5. Audit access periodically
sudo bash scripts/audit-access.sh

# 6. Run production checklist before going live
bash scripts/production-checklist.sh
```

### Dev Partner Access (SSH Tunnel)

Allow dev partners to access production databases from their local machine without shell access:

```bash
# 1. Add tunnel-only user
sudo bash scripts/add-user.sh
# Select: 4) Tunnel Only
# Enter username and SSH public key

# 2. Dev partner creates tunnel from their local machine
ssh -N -p 2222 \
    -L 5432:localhost:5432 \
    -L 6379:localhost:6379 \
    -L 6380:localhost:6380 \
    dev-partner@your-server-ip

# 3. Dev partner connects to services locally
psql -h localhost -p 5432 -U postgres
redis-cli -h localhost -p 6379
```

**What tunnel-only users can do:**
- Create SSH tunnels to access PostgreSQL, Redis, etc.
- Connect to databases from their local machine

**What tunnel-only users CANNOT do:**
- Execute any commands on the server
- Get a shell session
- Access files on the server

## Production Readiness

Before going live, run the production checklist:

```bash
bash scripts/production-checklist.sh
```

This checks:

| Category | Checks |
|----------|--------|
| **Security** | Admin password, file permissions, SSH hardening, firewall, fail2ban/crowdsec |
| **Services** | Enabled containers running and healthy |
| **Backups** | Backup service configured with repository and password |
| **Monitoring** | Prometheus, Grafana, Alertmanager, Loki running |
| **SSL/TLS** | Let's Encrypt email configured, ACME store exists |
| **Resources** | Disk and memory usage within limits |
| **Updates** | Auto security updates enabled |

Example output:

```
==========================================
  Production Readiness Checklist
==========================================

━━━ 1. Security ━━━
  ✓ Admin password configured
  ✓ Directory permissions secured (700)
  ✓ SSH root login disabled
  ✓ Firewall (UFW) enabled
  ✓ Fail2ban running

━━━ 2. Core Services ━━━
  ✓ postgres running
  ✓ redis-cache running
  ✓ traefik running

━━━ 3. Backups ━━━
  ✓ Backup service running
  ✓ Backup password configured
  ✓ Backup repository configured

━━━ Summary ━━━
  Total checks: 15
  Passed: 14
  Failed: 0
  Warnings: 1

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  READY FOR PRODUCTION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
