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
| `09-rabbitmq.yml` | RabbitMQ | Connections, queues, memory |
| `app-{name}.yml` | Custom App | Per-app alerts via `app-cli.sh --alerts` |
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

**Application Alerts (per-app via `app-cli.sh --alerts`):**
- Create custom alerts for each app
- Template includes: error rate, latency, no-traffic alerts
- Customize with business-specific alerts

</details>

---

### Toggle Alert Categories

Alert rules are **automatically synced** with `services.conf` when you run `./setup.sh`. You can also manage them manually.

#### Automatic Sync (Recommended)

When you run `./setup.sh`, alert rules are automatically enabled/disabled based on which services are enabled in `services.conf`:

```
services.conf           →  Alert Rules
───────────────────────────────────────
postgres=true           →  04-postgresql.yml enabled
redis=true              →  05-redis.yml enabled
nats=false              →  06-nats.yml disabled
traefik=true            →  11-traefik.yml enabled
```

**Core alerts** (infrastructure, containers, observability) are **always enabled**.

**App instrumentation alerts** (task-queue, application) are **disabled by default** because they require code changes in your apps to expose metrics.

To manually re-sync:

```bash
cd /path/to/observability
./scripts/toggle-alerts.sh sync
```

#### Manual Control

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
#   [disabled] application
```

**Enable/Disable specific categories:**

```bash
# Disable alerts you don't need
./scripts/toggle-alerts.sh disable nats
./scripts/toggle-alerts.sh disable task-queue

# Enable alerts (e.g., after adding app instrumentation)
./scripts/toggle-alerts.sh enable application
./scripts/toggle-alerts.sh enable task-queue

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
| `rabbitmq` | 09-rabbitmq.yml |
| `mongodb`, `mongo` | 10-mongodb.yml |
| `traefik` | 11-traefik.yml |
| `garage` | 12-garage.yml |
| `security`, `authentik`, `vault` | 13-security.yml |
| `mysql` | 14-mysql.yml |
| `memcached` | 15-memcached.yml |
| `clickhouse` | 16-clickhouse.yml |
| `kafka` | 17-kafka.yml |
| `minio` | 18-minio.yml |

#### Legacy: Environment Variables

You can also configure in `.env` file and apply:

```bash
# .env
ALERTS_INFRASTRUCTURE=true
ALERTS_CONTAINERS=true
ALERTS_OBSERVABILITY=true
ALERTS_POSTGRESQL=true
ALERTS_REDIS=true
ALERTS_NATS=false           # Disabled - not using NATS
ALERTS_TASK_QUEUE=false     # Disabled - no background jobs yet
ALERTS_APPLICATION=false
```

```bash
# Apply settings from .env (legacy method)
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

### Connecting Your Applications

Use the `app-cli.sh connect` command from the infra root to connect your apps to observability:

```bash
cd /path/to/infra

# Option 1: Prometheus metrics only (simple)
# Your app exposes /metrics endpoint with Prometheus format
./scripts/app-cli.sh connect my-api --port 8080 --metrics

# Option 2: OpenTelemetry tracing (full observability)
# Your app sends traces via OTLP protocol
./scripts/app-cli.sh connect my-api --port 8080 --otel

# Option 3: Both metrics and tracing
./scripts/app-cli.sh connect my-api --port 8080 --metrics --otel

# Show environment variables to add to your app
./scripts/app-cli.sh connect my-api --otel --show-env
```

### Prometheus Metrics Setup

If using `--metrics`, your app must expose a `/metrics` endpoint in Prometheus format:

**Node.js (prom-client):**
```javascript
const client = require('prom-client');
const collectDefaultMetrics = client.collectDefaultMetrics;
collectDefaultMetrics();

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', client.register.contentType);
  res.end(await client.register.metrics());
});
```

**Go (prometheus/client_golang):**
```go
import "github.com/prometheus/client_golang/prometheus/promhttp"
http.Handle("/metrics", promhttp.Handler())
```

**Python (prometheus-client):**
```python
from prometheus_client import make_wsgi_app
app.wsgi_app = DispatcherMiddleware(app.wsgi_app, {'/metrics': make_wsgi_app()})
```

### OpenTelemetry Setup

If using `--otel`, configure your app with these environment variables:

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
OTEL_SERVICE_NAME=my-api
OTEL_TRACES_EXPORTER=otlp
```

**OTLP Endpoints:**
- gRPC: `localhost:4317`
- HTTP: `localhost:4318`

### Custom Dashboards & Alerts

Since each application has unique metrics, create custom Grafana dashboards and Prometheus alerts:

**1. Create your dashboard in Grafana:**
- Go to Grafana > Dashboards > New Dashboard
- Query your app's metrics using the `service` label
- Export as JSON when finished

**2. Copy files to the correct directories:**
```bash
# Dashboard (use app-{name}.json naming convention)
cp dashboard.json /opt/infra/services/observability/dashboards/app-myapi.json

# Alerts (use app-{name}.yml naming convention)
cp alerts.yml /opt/infra/services/observability/config/alerting-rules/app-myapi.yml
```

**3. Reload to apply changes:**
```bash
./scripts/app-cli.sh reload
```

This reloads Prometheus (for alerts) and Grafana (for dashboards) without restarting containers.

**Example query for your app:**
```promql
rate(http_requests_total{service="my-api"}[5m])
```

### Manual Target Registration

You can also manually add targets to `targets/applications.json`:

```json
[
  {
    "targets": ["host.docker.internal:8080"],
    "labels": {
      "service": "my-api",
      "env": "production"
    }
  }
]
```

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
| **Backup** | backup.json | Restic backup status & snapshots |
| Observability Overview | observability-overview.json | Stack health status |
| Host Metrics | node-exporter.json | Host metrics (CPU, RAM, disk) via Alloy |
| Docker Containers | docker-containers.json | Container resources via Alloy |
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

> **Note:** Application-specific dashboards should be created per-app since each has unique metrics. See [Application Monitoring](#application-monitoring).

### Pre-configured Datasources

- **Prometheus** - Metrics (default)
- **Loki** - Logs
- **Tempo** - Traces
- **Alertmanager** - Alerts

All datasources are linked for seamless navigation between metrics, logs, and traces.

---

## Configuration

### Resource Limits

Optimized for small VPS (2 OCPU, 10GB RAM). Total observability stack: ~2GB RAM.

**Default limits (configured in docker-compose.yml):**

| Component | Memory | CPU | Notes |
|-----------|--------|-----|-------|
| Alloy | 384M | 1.0 | Unified collector |
| Prometheus | 768M | 1.0 | Metrics storage |
| Loki | 384M | 0.5 | Log aggregation |
| Tempo | 256M | 0.5 | Tracing (optional) |
| Grafana | 256M | 0.5 | Visualization |
| Alertmanager | 256M | 0.5 | Alert routing |

**Adjust in `.env` for larger VPS:**

```bash
# Small VPS (4-10GB RAM) - Default
PROMETHEUS_MEMORY_LIMIT=768M
LOKI_MEMORY_LIMIT=384M
GRAFANA_MEMORY_LIMIT=256M
ALLOY_MEMORY_LIMIT=384M

# Medium VPS (16GB+ RAM)
PROMETHEUS_MEMORY_LIMIT=2G
LOKI_MEMORY_LIMIT=1G
GRAFANA_MEMORY_LIMIT=512M
ALLOY_MEMORY_LIMIT=512M

# Large VPS (32GB+ RAM)
PROMETHEUS_MEMORY_LIMIT=4G
LOKI_MEMORY_LIMIT=2G
GRAFANA_MEMORY_LIMIT=1G
ALLOY_MEMORY_LIMIT=1G
```

### Tempo (Distributed Tracing)

Tempo is **optional** and disabled by default to save resources. Enable it when you need distributed tracing:

```bash
# Start with tracing support
docker compose --profile tracing up -d

# Or start with all optional components
docker compose --profile full up -d
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
# Start core services (without Tempo tracing)
docker compose up -d

# Start with tracing support (includes Tempo)
docker compose --profile tracing up -d

# Start all optional components
docker compose --profile full up -d

# Stop all services
docker compose down

# View logs
docker compose logs -f
docker compose logs grafana
docker compose logs alloy

# Restart specific service
docker compose restart prometheus
docker compose restart alloy

# Check health
docker compose ps
```

### App CLI Commands (from infra root)

```bash
# Connect an app with Prometheus metrics
./scripts/app-cli.sh connect my-api --port 8080 --metrics

# Connect an app with OTEL tracing
./scripts/app-cli.sh connect my-api --port 8080 --otel

# Create template alert rules for customization
./scripts/app-cli.sh connect my-api --alerts

# Show environment variables needed
./scripts/app-cli.sh connect my-api --otel --show-env

# Reload after adding custom dashboards/alerts
./scripts/app-cli.sh reload
```

---

## File Structure

```
observability/
├── config/
│   ├── alertmanager.yml        # Alert routing & notifications
│   ├── alerting-rules/         # Modular alert rules (auto-synced with services.conf)
│   │   ├── 01-infrastructure.yml
│   │   ├── 02-containers.yml
│   │   ├── 03-observability.yml
│   │   ├── 04-postgresql.yml
│   │   ├── 05-redis.yml
│   │   ├── 06-nats.yml
│   │   ├── 07-task-queue.yml
│   │   └── app-{name}.yml      # Custom app alerts (via app-cli.sh --alerts)
│   ├── alloy.river             # Alloy unified collector config
│   ├── grafana-datasources.yaml # Grafana datasource config
│   ├── loki-config.yaml        # Loki configuration
│   ├── prometheus.yml          # Prometheus configuration
│   └── tempo-config.yaml       # Tempo configuration
├── targets/
│   ├── applications.json       # Custom app targets (via app-cli.sh connect)
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
│   ├── backup.json                  # Restic backup dashboard
│   ├── observability-overview.json  # Stack health dashboard
│   ├── node-exporter.json           # Host metrics dashboard
│   ├── docker-containers.json       # Container metrics dashboard
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
│   ├── vault.json                   # HashiCorp Vault dashboard
│   └── app-{name}.json              # Custom app dashboards (user-created)
├── docker-compose.yml
├── .env.example
└── README.md
```
