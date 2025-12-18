# PostgreSQL Single Node - Production Setup

Production-ready PostgreSQL single-node deployment using Docker.

## Features

- ✅ PostgreSQL 17 (latest stable)
- ✅ Optimized for production workloads
- ✅ Secure configuration (scram-sha-256)
- ✅ Resource limits (CPU/Memory)
- ✅ Comprehensive logging
- ✅ Health checks
- ✅ Non-root application user
- ✅ User & schema management scripts
- ✅ Custom schema support (for Prisma, etc.)

---

## Quick Start

### 1. Clone and Configure

```bash
cd postgres-single

# Create environment file
cp .env.example .env

# Generate strong passwords
openssl rand -base64 32  # For POSTGRES_PASSWORD
openssl rand -base64 32  # For POSTGRES_NON_ROOT_PASSWORD

# Edit .env with your passwords
nano .env

chmod 644 config/postgresql.conf config/pg_hba.conf
chmod 755 init-scripts/01-init-users.sh
```

### 2. Start PostgreSQL

```bash
# Create required directories
mkdir -p logs

# Start container
docker compose up -d

# Check status
docker compose ps
docker compose logs -f
```

### 3. Verify Connection

```bash
# Connect as admin
docker exec -it postgres psql -U postgres -d myapp

# Connect as app user
docker exec -it postgres psql -U app_user -d myapp

# From host (if port exposed)
psql -h localhost -p 54320 -U app_user -d myapp
```

---

## Directory Structure

```
postgres-single/
├── docker-compose.yml      # Main Docker configuration
├── .env                    # Environment variables (DO NOT COMMIT)
├── .env.example           # Template for .env
├── config/
│   ├── postgresql.conf    # PostgreSQL configuration
│   └── pg_hba.conf        # Client authentication
├── init-scripts/
│   └── 01-init-users.sh   # Creates application user on first start
├── scripts/
│   ├── create-user.sh     # Create new user + schema
│   ├── list-users.sh      # List all users & schemas
│   └── delete-user.sh     # Delete user
├── data/                  # PostgreSQL data (auto-created)
└── logs/                  # PostgreSQL logs
```

---

## Configuration

### Memory Settings

Adjust in `config/postgresql.conf` based on your VPS:

**Single-App Server (PostgreSQL is primary workload):**

| VPS Size | RAM | shared_buffers | effective_cache_size | work_mem |
|----------|-----|----------------|---------------------|----------|
| Small    | 2GB | 512MB          | 1.5GB               | 4MB      |
| Medium   | 4-8GB | 1GB          | 3GB                 | 8MB      |
| Large    | 16GB | 4GB           | 12GB                | 16MB     |
| XLarge   | 32GB+ | 8GB          | 24GB                | 32MB     |

**Multi-App Server (PostgreSQL + Redis + Apps + Workers):**

For servers running multiple services, use conservative settings:

| VPS RAM | shared_buffers | effective_cache_size | work_mem | maintenance_work_mem |
|---------|----------------|---------------------|----------|---------------------|
| 4GB | 512MB | 1.5GB | 4MB | 128MB |
| 8GB | 1GB | 3GB | 8MB | 256MB |
| 10GB | 1.5GB | 4GB | 8MB | 256MB |
| 16GB+ | 2GB | 6GB | 16MB | 512MB |

**Example for 10GB RAM multi-app server:**
```conf
# config/postgresql.conf
# Conservative for multi-app server (10GB RAM)
shared_buffers = 1536MB          # ~1.5GB
effective_cache_size = 4096MB    # ~4GB
work_mem = 8MB
maintenance_work_mem = 256MB
```

**Container limits (docker-compose.yml):**
```yaml
deploy:
  resources:
    limits:
      cpus: "2"
      memory: 2G    # shared_buffers (1.5GB) + overhead
    reservations:
      cpus: "0.25"
      memory: 512M
```

### Multi-App Server Memory Allocation Example

For a 10GB RAM server running PostgreSQL, Redis, observability, and app workers:

| Service | Memory Limit | Notes |
|---------|--------------|-------|
| PostgreSQL | 2GB | shared_buffers 1.5GB + overhead |
| Redis Cache | 768MB | maxmemory 512MB |
| Redis Queue | 768MB | maxmemory 512MB |
| Observability | ~2GB | Prometheus, Grafana, Loki |
| App Workers | 2-3GB | Your application |
| OS/Overhead | ~1GB | System processes |

### Resource Limits

Adjust in `docker-compose.yml`:

```yaml
deploy:
  resources:
    limits:
      cpus: '2'      # Adjust based on VPS
      memory: 2G     # Adjust based on VPS
```

---

## User & Schema Management

### Create New User

```bash
# User with public schema (default)
./scripts/create-user.sh myuser mypassword

# User with custom schema
./scripts/create-user.sh api_user secret123 api
./scripts/create-user.sh admin_user secret456 admin

# Example: Create user for new microservice
./scripts/create-user.sh orders_svc password123 orders
```

### List Users & Schemas

```bash
./scripts/list-users.sh
```

Output shows:
- All database users
- All schemas and their owners
- Permission mappings

### Delete User

```bash
# Delete user only (keeps schema, reassigns objects to postgres)
./scripts/delete-user.sh myuser

# Delete user AND their owned schema (DESTRUCTIVE)
./scripts/delete-user.sh myuser --drop-schema
```

### Initial User (via Init Script)

The `init-scripts/01-init-users.sh` runs **only on first startup** and creates:
- User: `POSTGRES_NON_ROOT_USER`
- Schema: `POSTGRES_APP_SCHEMA` (defaults to `public`)

Configure in `.env`:
```env
POSTGRES_NON_ROOT_USER=dev
POSTGRES_NON_ROOT_PASSWORD=your_password
POSTGRES_APP_SCHEMA=app
```

## Backups

Backups are handled by the **centralized backup system** in `../backup/`.

```bash
# Run backup
../backup/scripts/backup.sh

# Restore PostgreSQL
../backup/scripts/restore.sh postgres
```

See `../backup/README.md` for full documentation.

---

## Security Best Practices

### 1. Strong Passwords

```bash
# Generate strong password
openssl rand -base64 32
```

### 2. Firewall Configuration

```bash
# Allow PostgreSQL only from specific IPs
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.0.0.0/8" port port="54320" protocol="tcp" accept'
sudo firewall-cmd --reload
```

### 3. Use Application User

Always use `POSTGRES_NON_ROOT_USER` for application connections:
- Limited privileges (no DROP, no CREATE USER)
- Can't access other databases
- Safer for application bugs/SQL injection

### 4. Network Isolation

If PostgreSQL doesn't need external access:

```yaml
# In docker-compose.yml, change:
ports:
  - "54320:5432"

# To (internal only):
ports:
  - "127.0.0.1:54320:5432"
```

---

## Monitoring

### Health Check

```bash
# Check container health
docker inspect postgres --format='{{.State.Health.Status}}'

# Check PostgreSQL status
docker exec postgres pg_isready -U postgres
```

### Logs

```bash
# Docker logs
docker compose logs -f postgres

# PostgreSQL logs
tail -f logs/postgresql-$(date +%Y-%m-%d).log
```

### Useful Queries

```sql
-- Active connections
SELECT * FROM pg_stat_activity;

-- Database sizes
SELECT pg_database.datname, pg_size_pretty(pg_database_size(pg_database.datname))
FROM pg_database ORDER BY pg_database_size(pg_database.datname) DESC;

-- Table sizes
SELECT relname, pg_size_pretty(pg_total_relation_size(relid))
FROM pg_catalog.pg_statio_user_tables
ORDER BY pg_total_relation_size(relid) DESC;

-- Long-running queries
SELECT pid, now() - pg_stat_activity.query_start AS duration, query
FROM pg_stat_activity
WHERE state != 'idle' AND now() - pg_stat_activity.query_start > interval '5 minutes';

-- Kill a query
SELECT pg_terminate_backend(pid);
```

---

## Maintenance

### Update PostgreSQL

```bash
# Pull latest image
docker compose pull

# Recreate container (data preserved in volume)
docker compose up -d
```

### Vacuum & Analyze

```bash
# Run vacuum (reclaim space)
docker exec postgres psql -U postgres -c "VACUUM ANALYZE;"

# Full vacuum (locks tables - run during maintenance window)
docker exec postgres psql -U postgres -c "VACUUM FULL ANALYZE;"
```

### Reindex

```bash
# Reindex database
docker exec postgres psql -U postgres -d myapp -c "REINDEX DATABASE myapp;"
```

---

## Troubleshooting

### Container Won't Start

```bash
# Check logs
docker compose logs postgres

# Common issues:
# - Port already in use: Change POSTGRES_PORT
# - Permission issues: Check data directory ownership
# - Config errors: Check postgresql.conf syntax
```

### Connection Refused

```bash
# Check if container is running
docker compose ps

# Check if PostgreSQL is ready
docker exec postgres pg_isready

# Check pg_hba.conf for your IP
cat config/pg_hba.conf
```

### Slow Queries

```bash
# Enable query logging temporarily
docker exec postgres psql -U postgres -c "ALTER SYSTEM SET log_min_duration_statement = 100;"
docker exec postgres psql -U postgres -c "SELECT pg_reload_conf();"

# Check slow query log
tail -f logs/postgresql-$(date +%Y-%m-%d).log | grep duration
```

### Out of Disk Space

```bash
# Check disk usage
docker exec postgres psql -U postgres -c "SELECT pg_size_pretty(pg_database_size('myapp'));"

# Vacuum to reclaim space
docker exec postgres psql -U postgres -c "VACUUM FULL;"

# Check for bloated tables
docker exec postgres psql -U postgres -d myapp -c "
SELECT schemaname, tablename,
       pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables WHERE schemaname = 'public' ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC LIMIT 10;"
```

---

## Connection Strings

### Application (Non-Root User)

```
postgresql://app_user:PASSWORD@localhost:54320/myapp
```

### Admin (Superuser)

```
postgresql://postgres:PASSWORD@localhost:54320/myapp
```

### Docker Internal

```
postgresql://app_user:PASSWORD@postgres:5432/myapp
```

---

## Upgrade Path

### Minor Version Upgrade (17.1 → 17.2)

```bash
docker compose pull
docker compose up -d
```

### Major Version Upgrade (17 → 18)

Major upgrades require data migration:

```bash
# 1. Backup everything
../backup/scripts/backup.sh

# 2. Stop old container
docker compose down

# 3. Update image version in docker-compose.yml
# Change: postgres:17-alpine → postgres:18-alpine

# 4. Use pg_upgrade or restore from backup
# Option A: Fresh start with restore
docker volume rm postgres_data
docker compose up -d
../backup/scripts/restore.sh postgres

# Option B: Use pg_upgrade (more complex)
# See PostgreSQL documentation
```

---

## Security Checklist

- [ ] Strong passwords (32+ characters)
- [ ] Non-root user for applications
- [ ] Firewall restricts PostgreSQL port
- [ ] .env not in version control
- [ ] Regular backups configured
- [ ] Log rotation enabled
- [ ] SSL/TLS for remote connections (optional)

---

## Performance Checklist

- [ ] Memory settings match VPS RAM
- [ ] SSD settings if using SSD (random_page_cost=1.1)
- [ ] Connection pooling for high-traffic apps (PgBouncer)
- [ ] Indexes on frequently queried columns
- [ ] Regular VACUUM ANALYZE
- [ ] Monitor slow queries

---

## Files NOT to Commit

Add to `.gitignore`:

```
.env
data/
logs/
```

---

## Support

- [PostgreSQL Documentation](https://www.postgresql.org/docs/17/)
- [Docker Hub - PostgreSQL](https://hub.docker.com/_/postgres)
- [PGTune - Configuration Calculator](https://pgtune.leopard.in.ua/)
