# Infrastructure Stack

Production-ready, self-hosted infrastructure with one-command setup.

## Quick Start

```bash
# On a new server:
git clone https://github.com/YOUR_USER/infra.git /opt/infra
cd /opt/infra

# Set admin password (first time)
./setup.sh --set-password

# Edit services to enable
nano services.conf

# Start everything
./setup.sh
```

## Structure

```
infra/
├── setup.sh              # Start services
├── stop.sh               # Stop services
├── status.sh             # Check status
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
│   ├── vps-initial-setup.sh  # First-time VPS hardening
│   ├── docker-install.sh     # Install Docker
│   ├── add-user.sh           # Add SSH users to server
│   ├── vps-health-check.sh   # Server health monitoring
│   ├── db-cli.sh             # → lib/db-cli.sh (symlink)
│   └── app-cli.sh            # → lib/app-cli.sh (symlink)
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
| `./status.sh` | Check service status |
| `./test.sh` | Validate all configurations |
| `./test.sh --verbose` | Detailed validation output |

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
# 1. Enable (requires postgres + redis)
# Edit services.conf: langfuse=true

# 2. Configure
cp services/langfuse/.env.example services/langfuse/.env
# Generate secrets:
echo "LANGFUSE_NEXTAUTH_SECRET=$(openssl rand -base64 32)" >> services/langfuse/.env
echo "LANGFUSE_SALT=$(openssl rand -base64 32)" >> services/langfuse/.env
echo "LANGFUSE_DB_PASS=$(openssl rand -base64 24)" >> services/langfuse/.env

# 3. Start
./setup.sh

# 4. Open http://localhost:3050 and create account
```

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

```bash
# Create user with database
./lib/db-cli.sh postgres create-user myapp secret123 mydb

# Create user with custom schema
./lib/db-cli.sh postgres create-user myapp secret123 mydb custom_schema

# List users
./lib/db-cli.sh postgres list-users

# Delete user (keeps database)
./lib/db-cli.sh postgres delete-user myapp

# Delete user AND drop owned databases/schemas
./lib/db-cli.sh postgres delete-user myapp --drop-schema

# Works with: postgres, postgres-ha, timescaledb, mysql, mongo
```

### Database CLI Commands

| Command | Description |
|---------|-------------|
| `create-user <user> <pass> [db] [schema]` | Create user with optional database |
| `delete-user <user>` | Delete user, reassign owned objects |
| `delete-user <user> --drop-schema` | Delete user AND drop owned databases/schemas |
| `list-users` | List all database users |

### Connection Strings

After creating a user, use these connection strings from your app:

```bash
# PostgreSQL
postgresql://myapp:secret@postgres:5432/mydb

# Redis Cache
redis://:password@redis-cache:6379

# Redis Queue
redis://:password@redis-queue:6379

# MongoDB
mongodb://myapp:secret@mongo-primary:27017/mydb?replicaSet=rs0

# MySQL
mysql://myapp:secret@mysql:3306/mydb

# TimescaleDB
postgresql://myapp:secret@timescaledb:5432/mydb
```

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
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
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
curl -fsSL https://raw.githubusercontent.com/YOUR_USER/infra/main/bootstrap.sh | bash
```

### Option 2: Manual
```bash
# 1. Clone
git clone https://github.com/YOUR_USER/infra.git /opt/infra
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
| Traefik | http://localhost:8080 |
| Uptime Kuma | http://localhost:3001 |
| LangFuse | http://localhost:3050 |

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
