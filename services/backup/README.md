# Backup System

Production-grade backup solution using Restic with automatic scheduling, notifications, and selective backup support.

## Quick Start (Automated)

The backup system is **automatically configured** by `setup-all.sh`:

```bash
# In your infra directory
./setup-all.sh
```

This will:
1. Build the backup container with all database clients
2. Configure credentials from enabled services
3. Set up daily backups at 2 AM
4. Enable Ntfy notifications (if ntfy service enabled)

**That's it!** Backups run automatically.

### Manual Commands

```bash
# Trigger backup now
docker exec backup /app/scripts/backup.sh

# Backup specific service only
docker exec backup /app/scripts/backup.sh postgres
docker exec backup /app/scripts/backup.sh mysql
docker exec backup /app/scripts/backup.sh redis

# View logs
docker logs backup
tail -f tools/backup/logs/backup_*.log

# List snapshots
docker exec backup restic snapshots

# Check backup status
docker exec backup restic stats
```

### Selective Backup

Edit `config/*.json` to enable/disable specific targets:

```bash
# Disable PostgreSQL backup
nano tools/backup/config/postgres.json
# Set "enabled": false
```

---

## Features

- **Automated**: Runs daily at 2 AM (configurable)
- **Multi-mode**: Docker, Kubernetes, External/Network databases
- **Encrypted**: AES-256 encryption via Restic
- **Deduplicated**: Only stores changes between backups
- **Multiple backends**: S3, MinIO, Garage, Backblaze B2, SFTP
- **Services**: PostgreSQL, MySQL, TimescaleDB, Redis, MongoDB, NATS, Volumes
- **Notifications**: Ntfy, Slack, Discord

## Installation

```bash
# 1. Run setup wizard
./setup.sh

# Or manually:
cp .env.example .env
nano .env
```

### Required .env Settings

```bash
# Restic repository (where backups are stored)
RESTIC_REPOSITORY=s3:http://minio:9000/backups
RESTIC_PASSWORD=your-strong-password

# S3/MinIO credentials
AWS_ACCESS_KEY_ID=minioadmin
AWS_SECRET_ACCESS_KEY=minioadmin

# Database passwords (add as needed)
POSTGRES_PASSWORD=xxx
REDIS_PASSWORD=xxx
MONGO_PASSWORD=xxx
```

## Usage

### Step 1: Add Backup Targets

Use the CLI to add services you want to backup:

```bash
# Add PostgreSQL
./scripts/manage-targets.sh add postgres \
    --name pg-main \
    --container postgres \
    --databases mydb \
    --password-env POSTGRES_PASSWORD

# Add Redis
./scripts/manage-targets.sh add redis \
    --name redis-main \
    --container redis \
    --password-env REDIS_PASSWORD

# Add MongoDB
./scripts/manage-targets.sh add mongo \
    --name mongo-main \
    --container mongo \
    --databases myapp \
    --password-env MONGO_PASSWORD

# Add Docker Volume
./scripts/manage-targets.sh add volumes \
    --name grafana-data \
    --mode docker \
    --container observability_grafana_data
```

### Step 2: Run Backup

```bash
# Backup everything
./scripts/backup.sh

# Backup specific service
./scripts/backup.sh postgres
./scripts/backup.sh redis
./scripts/backup.sh mongo
./scripts/backup.sh volumes
```

### Step 3: Verify

```bash
# List snapshots
./scripts/restore.sh list

# Show snapshot contents
./scripts/restore.sh show latest
```

## Adding Backup Targets

### PostgreSQL

```bash
# Docker container
./scripts/manage-targets.sh add postgres \
    --name pg-main \
    --container postgres \
    --databases mydb,analytics \
    --password-env POSTGRES_PASSWORD

# Multiple databases
./scripts/manage-targets.sh add postgres \
    --name pg-main \
    --container postgres \
    --databases db1,db2,db3 \
    --password-env POSTGRES_PASSWORD

# External database (RDS, etc)
./scripts/manage-targets.sh add postgres \
    --name pg-rds \
    --mode network \
    --host mydb.rds.amazonaws.com \
    --port 5432 \
    --databases production \
    --user admin \
    --password-env PG_RDS_PASSWORD \
    --tls

# Kubernetes
./scripts/manage-targets.sh add postgres \
    --name pg-k8s \
    --mode kubectl \
    --namespace database \
    --pod postgres-0 \
    --databases app \
    --password-env PG_K8S_PASSWORD
```

### Redis

```bash
# Docker container
./scripts/manage-targets.sh add redis \
    --name redis-cache \
    --container redis \
    --password-env REDIS_PASSWORD

# Kubernetes
./scripts/manage-targets.sh add redis \
    --name redis-k8s \
    --mode kubectl \
    --namespace cache \
    --pod redis-master-0 \
    --password-env REDIS_K8S_PASSWORD
```

### MongoDB

```bash
# Docker container
./scripts/manage-targets.sh add mongo \
    --name mongo-main \
    --container mongo \
    --databases myapp,logs \
    --password-env MONGO_PASSWORD

# With replica set and TLS
./scripts/manage-targets.sh add mongo \
    --name mongo-rs \
    --container mongo-primary \
    --databases app \
    --replica-set rs0 \
    --tls \
    --password-env MONGO_PASSWORD
```

### NATS JetStream

```bash
# Docker container
./scripts/manage-targets.sh add nats \
    --name nats-main \
    --container nats
```

### Docker Volumes

```bash
# Docker volume
./scripts/manage-targets.sh add volumes \
    --name grafana-data \
    --mode docker \
    --container observability_grafana_data

# Local path
./scripts/manage-targets.sh add volumes \
    --name config-backup \
    --mode path \
    --host /opt/myapp/config
```

## Managing Targets

```bash
# List all targets
./scripts/manage-targets.sh list

# List specific service
./scripts/manage-targets.sh list postgres

# Show target details
./scripts/manage-targets.sh show postgres pg-main

# Enable/disable target
./scripts/manage-targets.sh enable postgres pg-main
./scripts/manage-targets.sh disable postgres pg-main

# Remove target
./scripts/manage-targets.sh remove postgres pg-main
```

## Restore

```bash
# List available snapshots
./scripts/restore.sh list

# Show snapshot contents
./scripts/restore.sh show latest
./scripts/restore.sh show abc123

# Restore PostgreSQL
./scripts/restore.sh postgres latest pg-main mydb

# Restore Redis
./scripts/restore.sh redis latest redis-main

# Restore MongoDB
./scripts/restore.sh mongo latest mongo-main myapp

# Restore NATS
./scripts/restore.sh nats latest nats-main

# Restore Volume
./scripts/restore.sh volume latest grafana-data

# Restore specific files
./scripts/restore.sh files latest "*/postgres/*"
```

## Edit Config Directly (Alternative)

Instead of using CLI, you can edit JSON files directly:

### config/postgres.json

```json
{
  "targets": [
    {
      "name": "pg-main",
      "enabled": true,
      "mode": "docker",
      "container": "postgres",
      "databases": ["mydb", "analytics"],
      "user": "postgres",
      "password_env": "POSTGRES_PASSWORD"
    }
  ]
}
```

### config/redis.json

```json
{
  "targets": [
    {
      "name": "redis-main",
      "enabled": true,
      "mode": "docker",
      "container": "redis",
      "password_env": "REDIS_PASSWORD"
    }
  ]
}
```

### config/mongo.json

```json
{
  "targets": [
    {
      "name": "mongo-main",
      "enabled": true,
      "mode": "docker",
      "container": "mongo",
      "databases": ["myapp"],
      "user": "admin",
      "password_env": "MONGO_PASSWORD",
      "auth_db": "admin"
    }
  ]
}
```

### config/volumes.json

```json
{
  "targets": [
    {
      "name": "grafana-data",
      "enabled": true,
      "mode": "docker",
      "volume": "observability_grafana_data"
    }
  ]
}
```

## Storage Backends

Configure `RESTIC_REPOSITORY` in `.env`:

```bash
# MinIO (local S3)
RESTIC_REPOSITORY=s3:http://minio:9000/backups
AWS_ACCESS_KEY_ID=minioadmin
AWS_SECRET_ACCESS_KEY=minioadmin

# AWS S3
RESTIC_REPOSITORY=s3:s3.amazonaws.com/bucket-name/backups
AWS_ACCESS_KEY_ID=your-key
AWS_SECRET_ACCESS_KEY=your-secret

# Backblaze B2
RESTIC_REPOSITORY=b2:bucket-name:backups
B2_ACCOUNT_ID=your-account-id
B2_ACCOUNT_KEY=your-account-key

# SFTP
RESTIC_REPOSITORY=sftp:user@host:/backups

# Local path
RESTIC_REPOSITORY=/mnt/backup-drive/restic
```

## Scheduling

### Cron (Daily at 2 AM)

```bash
sudo cp cron/backup-cron /etc/cron.d/infra-backup
```

### Systemd Timer

```bash
sudo cp cron/backup.service /etc/systemd/system/
sudo cp cron/backup.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now backup.timer

# Check status
systemctl status backup.timer
journalctl -u backup.service
```

## Notifications

Add to `.env` for alerts:

```bash
# Ntfy (recommended - auto-configured if ntfy service enabled)
NTFY_URL=http://ntfy:80/backups

# Slack
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/xxx

# Discord
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/xxx
```

Notifications are sent on:
- Backup success (with duration and size)
- Backup failure (with error details)

## Retention Policy

Configure in `.env`:

```bash
RETENTION_HOURLY=24    # Keep 24 hourly snapshots
RETENTION_DAILY=7      # Keep 7 daily snapshots
RETENTION_WEEKLY=4     # Keep 4 weekly snapshots
RETENTION_MONTHLY=6    # Keep 6 monthly snapshots
RETENTION_YEARLY=2     # Keep 2 yearly snapshots
```

## Directory Structure

```
backup/
├── setup.sh              # Setup wizard
├── .env.example          # Config template
├── .env                  # Your configuration
├── config/               # Target configs (JSON)
│   ├── postgres.json
│   ├── redis.json
│   ├── mongo.json
│   ├── nats.json
│   └── volumes.json
├── scripts/
│   ├── backup.sh         # Run backups
│   ├── restore.sh        # Restore data
│   ├── manage-targets.sh # Manage targets
│   └── lib-common.sh     # Shared functions
├── cron/                 # Scheduling
└── logs/                 # Backup logs
```

## CLI Reference

### manage-targets.sh

| Command | Description |
|---------|-------------|
| `list` | List all targets |
| `list <service>` | List targets for service |
| `show <service> <name>` | Show target details |
| `add <service> [options]` | Add new target |
| `remove <service> <name>` | Remove target |
| `enable <service> <name>` | Enable target |
| `disable <service> <name>` | Disable target |

### Add Options

| Option | Description |
|--------|-------------|
| `--name` | Target name (required) |
| `--mode` | `docker`, `kubectl`, `network`, `path` |
| `--container` | Docker container name |
| `--host` | Hostname for network mode |
| `--port` | Port number |
| `--user` | Database username |
| `--password-env` | Env variable for password |
| `--databases` | Comma-separated database list |
| `--namespace` | Kubernetes namespace |
| `--pod` | Kubernetes pod name |
| `--replica-set` | MongoDB replica set |
| `--tls` | Enable TLS |

### backup.sh

| Command | Description |
|---------|-------------|
| `./backup.sh` | Backup all enabled targets |
| `./backup.sh databases` | Backup all databases |
| `./backup.sh volumes` | Backup all volumes |
| `./backup.sh postgres` | Backup PostgreSQL only |
| `./backup.sh mysql` | Backup MySQL only |
| `./backup.sh redis` | Backup Redis only |
| `./backup.sh mongo` | Backup MongoDB only |
| `./backup.sh nats` | Backup NATS only |

### restore.sh

| Command | Description |
|---------|-------------|
| `list` | List snapshots |
| `show <id>` | Show snapshot contents |
| `postgres <id> <target> <db>` | Restore PostgreSQL |
| `redis <id> <target>` | Restore Redis |
| `mongo <id> <target> <db>` | Restore MongoDB |
| `nats <id> <target>` | Restore NATS |
| `volume <id> <target>` | Restore volume |
| `files <id> <pattern>` | Restore files |

## Requirements

- **restic**: Backup tool
- **jq**: JSON parsing
- **docker**: For Docker mode
- **kubectl**: For Kubernetes mode
