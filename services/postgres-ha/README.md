# PostgreSQL Primary-Replica Setup - Production Configuration

Production-ready PostgreSQL streaming replication using Docker with Bitnami images.

## Features

- PostgreSQL 17 (latest stable)
- Streaming replication (asynchronous by default)
- Hot standby - read queries on replica
- scram-sha-256 authentication
- Resource limits (CPU/Memory)
- Health checks with dependency ordering
- User & schema management scripts
- Comprehensive logging
- TLS support (optional)

---

## Architecture

```
                    ┌─────────────────┐
                    │   Application   │
                    └────────┬────────┘
                             │
              ┌──────────────┴──────────────┐
              │                             │
              ▼                             ▼
    ┌─────────────────┐           ┌─────────────────┐
    │  postgres-master │           │ postgres-replica │
    │   (Read/Write)   │──────────▶│   (Read-Only)    │
    │    Port: 5432    │ Streaming │    Port: 5433    │
    └─────────────────┘ Replication└─────────────────┘
```

**Write operations** → Master (port 5432)
**Read operations** → Replica (port 5433) for load distribution

---

## Quick Start

### 1. Clone and Configure

```bash
cd postgres-replica

# Create environment file
cp .env.example .env

# Generate strong passwords
openssl rand -base64 32  # For POSTGRES_ADMIN_PASSWORD
openssl rand -base64 32  # For POSTGRES_REPLICATION_PASSWORD
openssl rand -base64 32  # For POSTGRES_PASSWORD

# Edit .env with your passwords
nano .env
```

### 2. Create Required Directories

```bash
# Create directories
mkdir -p logs/master logs/replica

# Set permissions for Bitnami (runs as user 1001)
sudo chown -R 1001:1001 logs

# Make scripts executable
chmod +x scripts/*.sh
```

### 3. Start the Cluster

```bash
# Start both master and replica
docker compose up -d

# Check status
docker compose ps

# View logs
docker compose logs -f
```

### 4. Verify Replication

```bash
# Check replication status
./scripts/check-replication.sh

# Or manually:
docker exec postgres-master psql -U postgres -c "SELECT * FROM pg_stat_replication;"
```

---

## Directory Structure

```
postgres-replica/
├── docker-compose.yml          # Main Docker configuration
├── .env                        # Environment variables (DO NOT COMMIT)
├── .env.example               # Template for .env
├── config/
│   ├── master-conf/
│   │   └── postgresql.conf    # Master configuration
│   ├── slave-conf/
│   │   └── postgresql.conf    # Replica configuration
│   └── pg_hba.conf            # Client authentication
├── scripts/
│   ├── check-replication.sh   # Monitor replication status
│   ├── create-user.sh         # Create user & schema
│   ├── list-users.sh          # List users & schemas
│   └── delete-user.sh         # Delete user & schema
├── certs/                     # TLS certificates (optional)
└── logs/
    ├── master/                # Master logs
    └── replica/               # Replica logs
```

---

## Configuration

### Memory Settings

Adjust in `config/master-conf/postgresql.conf` and `config/slave-conf/postgresql.conf`:

| VPS Size | RAM   | shared_buffers | effective_cache_size | work_mem |
|----------|-------|----------------|---------------------|----------|
| Small    | 2GB   | 512MB          | 1.5GB               | 4MB      |
| Medium   | 4-8GB | 1GB            | 3GB                 | 8MB      |
| Large    | 16GB  | 4GB            | 12GB                | 16MB     |
| XLarge   | 32GB+ | 8GB            | 24GB                | 32MB     |

### Resource Limits

Adjust in `docker-compose.yml`:

```yaml
deploy:
  resources:
    limits:
      cpus: '2'      # Adjust based on VPS
      memory: 2G     # Adjust based on VPS
```

### Synchronous Replication (Optional)

For zero data loss (at cost of write performance), enable in master config:

```conf
# In config/master-conf/postgresql.conf
synchronous_standby_names = 'postgres-replica'
```

---

## Connection Strings

### Application (Write - Master)

```
postgresql://app_user:PASSWORD@localhost:5432/myapp
```

### Application (Read - Replica)

```
postgresql://app_user:PASSWORD@localhost:5433/myapp
```

### Admin (Superuser)

```
postgresql://postgres:ADMIN_PASSWORD@localhost:5432/myapp
```

### Docker Internal

```
# Master
postgresql://app_user:PASSWORD@postgres-master:5432/myapp

# Replica
postgresql://app_user:PASSWORD@postgres-replica:5432/myapp
```

---

## User & Schema Management

All changes are made on the master and automatically replicate to the replica.

### Create User & Schema

```bash
# Create user with public schema (default)
./scripts/create-user.sh app_user "$(openssl rand -base64 32)"

# Create user with dedicated schema (recommended for Prisma)
./scripts/create-user.sh app_user "$(openssl rand -base64 32)" app

# For Prisma shadow database, also create migration schema:
./scripts/create-user.sh app_user "$(openssl rand -base64 32)" migration
```

### List Users & Schemas

```bash
./scripts/list-users.sh
```

### Delete User

```bash
# Delete user only (reassigns objects to postgres)
./scripts/delete-user.sh app_user

# Delete user and owned schemas
./scripts/delete-user.sh app_user --drop-schema
```

### Prisma Connection Strings

```bash
# Master (read-write)
DATABASE_MASTER_URL="postgresql://app_user:PASSWORD@localhost:5432/myapp?schema=app"

# Replica (read-only)
DATABASE_REPLICA_URL="postgresql://app_user:PASSWORD@localhost:5433/myapp?schema=app"

# Shadow database for migrations
DATABASE_SHADOW_URL="postgresql://app_user:PASSWORD@localhost:5432/myapp?schema=migration"
```

---

## Backups

Backups are handled by the centralized backup system. See `../backup/README.md` for documentation.

```bash
# Run backup manually
../backup/scripts/backup-postgres.sh

# Backups are stored in ../backup/data/postgres/
```

---

## Monitoring

### Replication Status

```bash
# Quick check
./scripts/check-replication.sh

# Detailed replication lag
docker exec postgres-master psql -U postgres -c "
SELECT
    client_addr,
    state,
    pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) as replication_lag
FROM pg_stat_replication;
"
```

### Health Check

```bash
# Check container health
docker inspect postgres-master --format='{{.State.Health.Status}}'
docker inspect postgres-replica --format='{{.State.Health.Status}}'

# Check PostgreSQL status
docker exec postgres-master pg_isready -U postgres
docker exec postgres-replica pg_isready -U postgres
```

### Logs

```bash
# Docker logs
docker compose logs -f postgres-master
docker compose logs -f postgres-replica

# PostgreSQL logs
tail -f logs/master/postgresql-$(date +%Y-%m-%d).log
tail -f logs/replica/postgresql-slave-$(date +%Y-%m-%d).log
```

### Useful Queries

```sql
-- Active connections (run on master or replica)
SELECT * FROM pg_stat_activity WHERE state = 'active';

-- Database sizes
SELECT pg_database.datname, pg_size_pretty(pg_database_size(pg_database.datname))
FROM pg_database ORDER BY pg_database_size(pg_database.datname) DESC;

-- Replication slots (master only)
SELECT slot_name, slot_type, active, restart_lsn FROM pg_replication_slots;

-- Is this a replica?
SELECT pg_is_in_recovery();
```

---

## TLS Configuration (Optional)

### 1. Generate Certificates

```bash
cd certs

# Create CA
openssl genrsa -out ca.key 2048
openssl req -x509 -new -nodes -key ca.key -sha256 -days 1024 -out ca.pem \
    -subj "/CN=postgres-ca"

# Create Server Certificate
openssl genrsa -out postgres.key 2048
openssl req -new -key postgres.key -out postgres.csr \
    -subj "/CN=postgres.yourdomain.com"
openssl x509 -req -in postgres.csr -CA ca.pem -CAkey ca.key \
    -CAcreateserial -out postgres.crt -days 500 -sha256

# Set permissions
chmod 600 postgres.key
chown 1001:1001 postgres.key postgres.crt ca.pem
```

### 2. Enable TLS in docker-compose.yml

Uncomment the TLS sections in `docker-compose.yml`:

```yaml
environment:
  - POSTGRESQL_ENABLE_TLS=yes
  - POSTGRESQL_TLS_CERT_FILE=/opt/bitnami/postgresql/certs/postgres.crt
  - POSTGRESQL_TLS_KEY_FILE=/opt/bitnami/postgresql/certs/postgres.key

volumes:
  - ./certs:/opt/bitnami/postgresql/certs:ro
```

---

## Failover Procedures

### Manual Failover (Replica to Master)

If master fails and you need to promote replica:

```bash
# 1. Stop the failed master
docker compose stop postgres-master

# 2. Promote replica to master
docker exec postgres-replica touch /tmp/pg_failover_trigger

# 3. Update your application connection strings to point to replica

# 4. Later: Rebuild original master as new replica
```

### Planned Switchover

```bash
# 1. Stop writes to master
docker exec postgres-master psql -U postgres -c "SELECT pg_switch_wal();"

# 2. Wait for replica to catch up
./scripts/check-replication.sh

# 3. Promote replica
docker exec postgres-replica pg_ctl promote

# 4. Reconfigure old master as replica
```

---

## Troubleshooting

### Replica Not Syncing

```bash
# Check replication status
./scripts/check-replication.sh

# Check replica logs
docker compose logs postgres-replica

# Common issues:
# - Incorrect replication password
# - Network connectivity
# - pg_hba.conf doesn't allow replication
```

### Replication Lag

```bash
# Check lag
docker exec postgres-master psql -U postgres -c "
SELECT pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) as lag
FROM pg_stat_replication;
"

# If lag is growing:
# - Check replica resources (CPU/memory/disk I/O)
# - Reduce max_standby_streaming_delay
# - Check network bandwidth
```

### Connection Refused

```bash
# Check containers are running
docker compose ps

# Check health status
docker inspect postgres-master --format='{{.State.Health.Status}}'

# Check pg_hba.conf allows your connection
cat config/pg_hba.conf
```

### Out of WAL Space

```bash
# Check WAL directory size
docker exec postgres-master du -sh /bitnami/postgresql/data/pg_wal

# Check replication slots (inactive slots prevent WAL cleanup)
docker exec postgres-master psql -U postgres -c "SELECT * FROM pg_replication_slots;"

# Drop inactive slot if needed
docker exec postgres-master psql -U postgres -c "SELECT pg_drop_replication_slot('slot_name');"
```

---

## Security Checklist

- [ ] Strong passwords (32+ characters) for all users
- [ ] .env not in version control
- [ ] Firewall restricts database ports
- [ ] Use application user (not postgres) for apps
- [ ] Centralized backups configured (../backup/)
- [ ] TLS enabled for remote connections
- [ ] Replication user has minimal privileges

---

## Performance Checklist

- [ ] Memory settings match VPS RAM
- [ ] SSD settings configured (random_page_cost=1.1)
- [ ] Connection pooling for high-traffic (PgBouncer)
- [ ] Read queries directed to replica
- [ ] Monitor replication lag
- [ ] Regular VACUUM ANALYZE

---

## Files NOT to Commit

Add to `.gitignore`:

```
.env
logs/
certs/*.key
certs/*.pem
certs/*.crt
```

---

## Support

- [PostgreSQL Documentation](https://www.postgresql.org/docs/17/)
- [Bitnami PostgreSQL Image](https://hub.docker.com/r/bitnami/postgresql)
- [PGTune - Configuration Calculator](https://pgtune.leopard.in.ua/)
- [PostgreSQL Streaming Replication](https://www.postgresql.org/docs/17/warm-standby.html)
