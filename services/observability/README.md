# Observability Stack

Complete observability solution with metrics, logs, traces, and alerting for production systems.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Your Applications                               │
│                    (Node.js, Python, Go, etc.)                              │
└───────────────────────────────┬─────────────────────────────────────────────┘
                                │ OTLP (gRPC/HTTP)
                                ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Grafana Alloy                                      │
│            (Unified collector: metrics, logs, traces)                        │
│   Replaces: node-exporter, cadvisor, redis-exporter, otel-collector, promtail│
└──────┬──────────────────┬──────────────────┬────────────────────────────────┘
       │                  │                  │
       ▼                  ▼                  ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│  Prometheus  │  │     Loki     │  │    Tempo     │
│   (Metrics)  │  │    (Logs)    │  │   (Traces)   │
└──────┬───────┘  └──────┬───────┘  └──────┬───────┘
       │                 │                  │
       └────────────────┬┴──────────────────┘
                        ▼
              ┌──────────────────┐
              │     Grafana      │
              │ (Visualization)  │
              └────────┬─────────┘
                       │
              ┌────────▼─────────┐
              │   Alertmanager   │
              │  (Notifications) │
              └──────────────────┘
```

## Quick Start

### 1. Configure Environment

```bash
cp .env.example .env
nano .env

# Required changes:
# - GRAFANA_ADMIN_PASSWORD (use strong password)
```

### 2. Create Required Network

```bash
# If NOT using setup.sh from the root directory:
docker network create infra
```

### 3. Start the Stack

```bash
docker compose up -d
```

### 4. Access Services

| Service | URL | Description |
|---------|-----|-------------|
| Grafana | http://localhost:3000 | Dashboards & visualization |
| Prometheus | http://127.0.0.1:9090 | Metrics & queries |
| Alertmanager | http://127.0.0.1:9093 | Alert management |

## Components

| Component | Port | Purpose |
|-----------|------|---------|
| Grafana Alloy | 4317 (gRPC), 4318 (HTTP), 12345 (UI) | Unified telemetry collector |
| Prometheus | 9090 | Metrics storage & alerting |
| Loki | 3100 | Log aggregation |
| Tempo | 3200 | Distributed tracing |
| Grafana | 3000 | Visualization |
| Alertmanager | 9093 | Alert routing & notifications |

**Alloy collects:**
- Host metrics (CPU, RAM, disk) - replaces node-exporter
- Container metrics - replaces cadvisor
- Redis metrics - replaces redis-exporter
- Docker logs - replaces promtail
- OTLP traces/metrics - replaces otel-collector

**External Services Monitored:**
| Service | Notes |
|---------|-------|
| PostgreSQL | Via Alloy (configure POSTGRES_DSN) |
| Redis | Via Alloy (configure REDIS_*) |
| NATS | Built-in monitoring port 8222 |
| MongoDB | Via Alloy (uncomment in alloy.river) |
| RabbitMQ | Built-in Prometheus plugin :15692 |
| Traefik | Built-in metrics :8080 |
| Garage | Bearer token required :3903 |

---

## Database Monitoring

### PostgreSQL & Redis (via Alloy)

PostgreSQL and Redis are monitored directly by Alloy. Configure in `.env`:

```bash
# PostgreSQL
POSTGRES_DSN=postgresql://user:pass@postgres:5432/dbname?sslmode=disable

# Redis
REDIS_PASSWORD=yourpassword
REDIS_CACHE_ADDR=redis-cache:6379
REDIS_QUEUE_ADDR=redis-queue:6379
```

### Other Services (via file_sd_configs)

Other services use dynamic JSON target files. Prometheus auto-reloads every 30 seconds.

```
targets/
├── nats.json        # NATS targets
├── rabbitmq.json    # RabbitMQ targets
├── mongodb.json     # MongoDB targets
├── traefik.json     # Traefik targets
└── garage.json      # Garage S3 targets
```

### Adding Targets

```bash
cd /path/to/observability

# Add NATS target
./scripts/manage-targets.sh add nats \
  --name nats-main \
  --host host.docker.internal \
  --port 9187

# Verify
./scripts/manage-targets.sh list postgres
```

**Multiple PostgreSQL instances:**

| Database | Exporter Port | Example |
|----------|---------------|---------|
| postgres-single | 9187 | `--port 9187` |
| postgres-master | 9188 | `--port 9188` |
| postgres-slave | 9189 | `--port 9189` |
| timescaledb | 9190 | `--port 9190` |

### Redis Monitoring

Redis uses multi-target mode - one exporter scrapes all Redis instances.

```bash
# Add Redis targets
./scripts/manage-targets.sh add redis \
  --name redis-cache \
  --host host.docker.internal \
  --port 6379 \
  --type cache

./scripts/manage-targets.sh add redis \
  --name redis-queue \
  --host host.docker.internal \
  --port 6380 \
  --type queue
```

### Garage (S3 Storage) Monitoring

Garage is the only service requiring bearer token authentication for metrics.

```bash
# 1. Copy token from garage to observability .env
cat ../../storage/garage/.env | grep GARAGE_METRICS_TOKEN
nano .env  # Add: GARAGE_METRICS_TOKEN=<paste-token>

# 2. Initialize the token (creates secrets/garage-metrics-token)
./scripts/init-garage-token.sh

# 3. Add target (same as other services)
./scripts/manage-targets.sh add garage --name garage-main --host garage

# 4. Restart Prometheus
docker compose restart prometheus
```

Alerts are enabled by default (`ALERTS_GARAGE=true` in .env).

### Managing Targets

```bash
# List all targets
./scripts/manage-targets.sh list postgres
./scripts/manage-targets.sh list redis

# Add new target
./scripts/manage-targets.sh add postgres --name my-db --host host.docker.internal --port 9187
./scripts/manage-targets.sh add redis --name my-redis --host host.docker.internal --port 6379

# Remove target
./scripts/manage-targets.sh remove postgres --name my-db
./scripts/manage-targets.sh remove redis --name my-redis
```

### Target File Format

You can also edit the JSON files directly:

**targets/postgres.json:**
```json
[
  {
    "targets": ["host.docker.internal:9187"],
    "labels": {
      "database": "postgres-single",
      "instance_type": "single",
      "service": "postgresql"
    }
  }
]
```

**targets/redis.json:**
```json
[
  {
    "targets": ["host.docker.internal:6379"],
    "labels": {
      "database": "redis-cache",
      "instance_type": "cache",
      "service": "redis"
    }
  }
]
```

---

## Alerting

### Alertmanager Configuration

Edit `config/alertmanager.yml` to configure notification channels:

```yaml
receivers:
  - name: 'slack-alerts'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/xxx/xxx/xxx'
        channel: '#alerts'
        send_resolved: true
```

### Alert Rules

Alerts are organized into **modular files** in `config/alerting-rules/`:

| File | Category | What it monitors |
|------|----------|------------------|
| `01-infrastructure.yml` | Infrastructure | CPU, memory, disk, network (Node Exporter) |
| `02-containers.yml` | Containers | Container resources, restarts (cAdvisor) |
| `03-observability.yml` | Observability | Prometheus, Loki, Tempo health |
| `04-postgresql.yml` | PostgreSQL | Connections, deadlocks, replication |
| `05-redis.yml` | Redis | Memory, connections, replication |
| `06-nats.yml` | NATS | JetStream, consumers, connections |
| `07-task-queue.yml` | Task Queue | Asynq/BullMQ queue health |
| `08-application.yml` | Application | HTTP error rate, latency |
| `09-rabbitmq.yml` | RabbitMQ | Connections, queues, memory |
| `10-mongodb.yml` | MongoDB | Connections, replication, storage |
| `11-traefik.yml` | Traefik | Requests, errors, certificates |
| `12-garage.yml` | Garage | S3 storage, replication, latency |

<details>
<summary><b>View all alerts by category</b></summary>

**Infrastructure (01-infrastructure.yml):**
- HighCPUUsage / CriticalCPUUsage (>80%, >95%)
- HighMemoryUsage / CriticalMemoryUsage (>85%, >95%)
- DiskSpaceLow / CriticalDiskSpace (<15%, <5%)
- HighDiskIOUtilization (>90%)
- NetworkInterfaceDown
- HighNetworkBandwidth (>100MB/s)
- HostOutOfInodes (<10%)
- ClockSkewDetected (>50ms)

**Containers (02-containers.yml):**
- ContainerHighCPU / ContainerHighMemory (>80%)
- ContainerMemoryNearLimit (>95%)
- ContainerRestarted
- ContainerNotRunning
- ContainerNetworkErrors
- ContainerCPUThrottled

**Observability (03-observability.yml):**
- PrometheusTargetDown
- PrometheusConfigReloadFailed
- LokiRequestErrors
- TempoIngesterUnhealthy

**PostgreSQL (04-postgresql.yml):**
- PostgreSQLDown
- PostgreSQLTooManyConnections / PostgreSQLConnectionsCritical (>80%, >95%)
- PostgreSQLDeadlock
- PostgreSQLSlowQueries (>5min)
- PostgreSQLHighRollbackRate (>10%)
- PostgreSQLReplicationLag / PostgreSQLReplicationLagCritical (>30s, >120s)
- PostgreSQLLowCacheHitRate (<90%)
- PostgreSQLTableBloat (>1M dead tuples)

**Redis (05-redis.yml):**
- RedisDown
- RedisHighMemoryUsage / RedisMemoryCritical (>80%, >95%)
- RedisTooManyConnections (>80%)
- RedisBlockedClients (>10)
- RedisRejectedConnections
- RedisHighLatency (>1ms)
- RedisReplicationBroken
- RedisRDBSnapshotFailed / RedisAOFRewriteFailed
- RedisHighEvictionRate (>100/sec)
- RedisClusterSlotsUnassigned

**NATS (06-nats.yml):**
- NATSDown
- NATSHighCPU / NATSHighMemory (>80%, >1GB)
- NATSTooManyConnections (>8000)
- NATSSlowConsumers
- NATSJetStreamStorageHigh / NATSJetStreamMemoryHigh (>80%)
- NATSStreamPendingHigh (>10k messages)

**Task Queue (07-task-queue.yml):**
- TaskQueueBacklog / TaskQueueBacklogCritical (>1000, >5000)
- TaskFailureRateHigh (>10%)
- TasksInDeadQueue
- TaskWorkersIdle
- TaskProcessingLatencyHigh (p95 >60s)
- ScheduledTasksBacklog (>10000)
- RetryQueueGrowing (>100)
- BullMQQueueBacklog / BullMQFailedJobs (Node.js)

**Application (08-application.yml):**
- HighErrorRate (>5% 5xx errors)
- HighLatency (p95 >1s)

</details>

---

### Toggle Alert Categories

You can enable/disable alert categories using **two methods**:

#### Method 1: CLI Script (Recommended)

```bash
cd /path/to/observability

# View current status of all alerts
./scripts/toggle-alerts.sh list

# Output:
# Alert Categories:
#   [enabled]  infrastructure
#   [enabled]  containers
#   [enabled]  observability
#   [enabled]  postgresql
#   [enabled]  redis
#   [disabled] nats
#   [disabled] task-queue
#   [enabled]  application
```

**Enable/Disable specific categories:**

```bash
# Disable alerts you don't need
./scripts/toggle-alerts.sh disable nats
./scripts/toggle-alerts.sh disable task-queue

# Enable alerts
./scripts/toggle-alerts.sh enable postgresql
./scripts/toggle-alerts.sh enable redis

# Bulk operations
./scripts/toggle-alerts.sh disable-all    # Disable everything
./scripts/toggle-alerts.sh enable-all     # Enable everything
```

**Category aliases:**

| Alias | File |
|-------|------|
| `infrastructure` | 01-infrastructure.yml |
| `containers` | 02-containers.yml |
| `observability` | 03-observability.yml |
| `postgresql`, `postgres` | 04-postgresql.yml |
| `redis` | 05-redis.yml |
| `nats` | 06-nats.yml |
| `task-queue`, `taskqueue`, `asynq`, `bullmq` | 07-task-queue.yml |
| `application`, `app` | 08-application.yml |

#### Method 2: Environment Variables

Configure in `.env` file and apply:

```bash
# .env
ALERTS_INFRASTRUCTURE=true
ALERTS_CONTAINERS=true
ALERTS_OBSERVABILITY=true
ALERTS_POSTGRESQL=true
ALERTS_REDIS=true
ALERTS_NATS=false           # Disabled - not using NATS
ALERTS_TASK_QUEUE=false     # Disabled - no background jobs yet
ALERTS_APPLICATION=true
```

```bash
# Apply settings from .env
./scripts/toggle-alerts.sh apply

# Output:
# Applying alert settings from .env...
# Enabled  infrastructure (already)
# Enabled  containers (already)
# Enabled  observability (already)
# Enabled  postgresql (already)
# Enabled  redis (already)
# Disabled nats (ALERTS_NATS=false)
# Disabled task-queue (ALERTS_TASK_QUEUE=false)
# Enabled  application (already)
# Reloading Prometheus configuration...
# Prometheus reloaded successfully
```

#### How It Works

Behind the scenes, the script simply renames files:
- **Enabled:** `07-task-queue.yml` (Prometheus loads it)
- **Disabled:** `07-task-queue.yml.disabled` (Prometheus ignores it)

You can also manually rename files if you prefer.

#### After Toggling

Prometheus automatically reloads when you use the script. If you manually rename files:

```bash
# Hot reload Prometheus (no restart needed)
curl -X POST http://localhost:9090/-/reload

# Or restart the container
docker compose restart prometheus
```

---

### Testing Alerts

```bash
# View active alerts in Prometheus
curl http://localhost:9090/api/v1/alerts

# View alerts in Alertmanager
curl http://localhost:9093/api/v2/alerts
```

---

## Application Monitoring

### Registering Applications with Prometheus

**Method 1: File-based**

Add to `targets/applications.json`:
```json
[
  {
    "targets": ["host.docker.internal:3000"],
    "labels": { "service": "my-api", "env": "production" }
  }
]
```

**Method 2: Docker labels (auto-discovery)**

```yaml
services:
  my-api:
    labels:
      - "prometheus.scrape=true"
      - "prometheus.port=3000"
```

### OpenTelemetry Endpoints

For distributed tracing:
- gRPC: `localhost:4317`
- HTTP: `localhost:4318`

---

## Grafana Dashboards

### Import Recommended Dashboards

Go to Grafana > Dashboards > Import, use these IDs:

| Dashboard | ID | Description |
|-----------|-----|-------------|
| Node Exporter Full | 1860 | Host metrics |
| Docker Container | 893 | Container metrics |
| PostgreSQL | 9628 | PostgreSQL metrics |
| Redis | 763 | Redis metrics |
| Loki Logs | 13639 | Log exploration |

**Pre-installed Dashboards (auto-provisioned):**
| Dashboard | File | Description |
|-----------|------|-------------|
| **Logs** | logs.json | Log search, volume, errors (Loki) |
| **Alertmanager** | alertmanager.json | Active alerts, silences, history |
| **Application** | application.json | HTTP requests, latency, errors |
| **Backend - API** | backend-api.json | API performance by endpoint (OTEL) |
| **Backend - Dependencies** | backend-dependencies.json | External APIs, DB, cache metrics |
| **Backend - Business** | backend-business.json | Custom KPIs, orders, users, events |
| **Backend - Runtime** | backend-runtime.json | GC, memory, event loop, goroutines |
| **Monolith Overview** | monolith-overview.json | All-in-one app dashboard (Prometheus metrics) |
| **Security** | security.json | Fail2ban & Crowdsec intrusion prevention |
| **Backup** | backup.json | Restic backup status & snapshots |
| Observability Overview | observability-overview.json | Stack health status |
| Host Metrics | node-exporter.json | Host metrics (CPU, RAM, disk) via Alloy |
| Docker Containers | docker-containers.json | Container resources via Alloy |
| Task Queue | task-queue.json | Asynq/BullMQ metrics |
| PostgreSQL | postgresql.json | Connections, transactions, I/O |
| Redis | redis.json | Memory, operations, keys |
| MongoDB | mongodb.json | Operations, connections, replication |
| MySQL | mysql.json | Queries, connections, InnoDB |
| NATS | nats.json | Messages, JetStream, connections |
| RabbitMQ | rabbitmq.json | Queues, messages, consumers |
| Kafka | kafka.json | Topics, consumer lag, partitions |
| Traefik | traefik.json | Requests, latency, certificates |
| S3 Storage | s3-storage.json | MinIO/Garage storage metrics |
| ClickHouse | clickhouse.json | OLAP queries, MergeTree ops |
| Qdrant | qdrant.json | Vector search, collections |
| Meilisearch | meilisearch.json | Search engine metrics |
| OpenSearch | opensearch.json | Cluster health, JVM, shards |
| LangFuse | langfuse.json | LLM traces, costs, latency |
| Vault | vault.json | Secrets, tokens, leases |

### Pre-configured Datasources

- **Prometheus** - Metrics (default)
- **Loki** - Logs
- **Tempo** - Traces
- **Alertmanager** - Alerts

All datasources are linked for seamless navigation between metrics, logs, and traces.

---

## Configuration

### Resource Limits

Adjust in `.env` based on your VPS:

```bash
# Small VPS (4GB RAM)
PROMETHEUS_MEMORY_LIMIT=1G
LOKI_MEMORY_LIMIT=512M
GRAFANA_MEMORY_LIMIT=256M

# Medium VPS (8-16GB RAM) - Default
PROMETHEUS_MEMORY_LIMIT=2G
LOKI_MEMORY_LIMIT=1G
GRAFANA_MEMORY_LIMIT=512M

# Large VPS (32GB+ RAM)
PROMETHEUS_MEMORY_LIMIT=4G
LOKI_MEMORY_LIMIT=2G
GRAFANA_MEMORY_LIMIT=1G
```

### Data Retention

```bash
# Prometheus (in .env)
PROMETHEUS_RETENTION_TIME=15d
PROMETHEUS_RETENTION_SIZE=10GB

# Loki (in config/loki-config.yaml)
retention_period: 168h  # 7 days
```

---

## Security

### Production Checklist

- [ ] Change `GRAFANA_ADMIN_PASSWORD`
- [ ] Internal ports bound to `127.0.0.1` (already configured)
- [ ] Set up Grafana users/roles
- [ ] Configure Alertmanager authentication
- [ ] Use Traefik for HTTPS (optional)

### Port Bindings

| Port | Binding | Access |
|------|---------|--------|
| 3000 (Grafana) | 0.0.0.0 | Public (with auth) |
| 4317, 4318 (OTLP) | 0.0.0.0 | Apps send telemetry |
| 9090, 9093, 3100, etc. | 127.0.0.1 | Internal only |

---

## Troubleshooting

### Services not starting

```bash
# Check logs
docker compose logs -f

# Check specific service
docker compose logs prometheus
docker compose logs alertmanager
```

### Targets not appearing

```bash
# Check Prometheus targets
curl http://localhost:9090/api/v1/targets | jq

# Verify target files
cat targets/postgres.json
cat targets/redis.json

# Check file permissions
ls -la targets/
```

### Exporter can't connect to database

```bash
# Test connectivity from inside observability network
docker compose exec alloy wget -qO- http://host.docker.internal:6379

# Check Alloy logs (unified collector)
docker logs alloy

# Check postgres exporter logs
docker logs postgres-single-exporter
```

### Reload Prometheus config

```bash
# Hot reload (no restart)
curl -X POST http://localhost:9090/-/reload
```

---

## CLI Commands

```bash
# Start all services
docker compose up -d

# Stop all services
docker compose down

# View logs
docker compose logs -f
docker compose logs grafana
docker compose logs prometheus

# Restart specific service
docker compose restart prometheus

# Check health
docker compose ps
```

---

## File Structure

```
observability/
├── config/
│   ├── alertmanager.yml        # Alert routing & notifications
│   ├── alerting-rules/         # Modular alert rules (toggle via .env)
│   │   ├── 01-infrastructure.yml
│   │   ├── 02-containers.yml
│   │   ├── 03-observability.yml
│   │   ├── 04-postgresql.yml
│   │   ├── 05-redis.yml
│   │   ├── 06-nats.yml
│   │   ├── 07-task-queue.yml
│   │   └── 08-application.yml
│   ├── alloy.river             # Alloy unified collector config
│   ├── grafana-datasources.yaml # Grafana datasource config
│   ├── loki-config.yaml        # Loki configuration
│   ├── prometheus.yml          # Prometheus configuration
│   └── tempo-config.yaml       # Tempo configuration
├── targets/
│   ├── nats.json               # NATS targets (dynamic)
│   ├── rabbitmq.json           # RabbitMQ targets
│   ├── garage.json             # Garage S3 storage targets
│   └── ...                     # Other service targets
├── secrets/
│   └── garage-metrics-token    # Garage bearer token (gitignored)
├── scripts/
│   ├── manage-targets.sh       # Add/remove monitoring targets
│   ├── toggle-alerts.sh        # Enable/disable alert categories
│   └── init-garage-token.sh    # Initialize Garage metrics token
├── dashboards/
│   ├── logs.json                    # Log search & analysis (Loki)
│   ├── alertmanager.json            # Active alerts & history
│   ├── application.json             # HTTP metrics for your apps
│   ├── backend-api.json             # API performance (OTEL)
│   ├── backend-dependencies.json    # External APIs, DB, cache
│   ├── backend-business.json        # Custom business KPIs
│   ├── backend-runtime.json         # GC, memory, concurrency
│   ├── monolith-overview.json       # All-in-one app dashboard
│   ├── security.json                # Fail2ban & Crowdsec dashboard
│   ├── backup.json                  # Restic backup dashboard
│   ├── observability-overview.json  # Stack health dashboard
│   ├── node-exporter.json           # Host metrics dashboard
│   ├── docker-containers.json       # Container metrics dashboard
│   ├── task-queue.json              # Asynq/BullMQ dashboard
│   ├── postgresql.json              # PostgreSQL dashboard
│   ├── redis.json                   # Redis dashboard
│   ├── mongodb.json                 # MongoDB dashboard
│   ├── mysql.json                   # MySQL dashboard
│   ├── nats.json                    # NATS messaging dashboard
│   ├── rabbitmq.json                # RabbitMQ dashboard
│   ├── kafka.json                   # Kafka streaming dashboard
│   ├── traefik.json                 # Traefik proxy dashboard
│   ├── s3-storage.json              # MinIO/Garage S3 dashboard
│   ├── clickhouse.json              # ClickHouse OLAP dashboard
│   ├── qdrant.json                  # Qdrant vector DB dashboard
│   ├── meilisearch.json             # Meilisearch search dashboard
│   ├── opensearch.json              # OpenSearch cluster dashboard
│   ├── langfuse.json                # LangFuse LLM observability
│   └── vault.json                   # HashiCorp Vault dashboard
├── docker-compose.yml
├── .env.example
└── README.md
```
