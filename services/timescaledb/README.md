# TimescaleDB Production Configuration

Production-ready TimescaleDB deployment for time-series data.

## Features

- TimescaleDB HA image (PostgreSQL 17 + TimescaleDB)
- Optimized for time-series workloads
- Automatic compression policies
- Data retention policies
- Continuous aggregates support
- User & schema management scripts
- Hypertable management tools

---

## Use Cases

- **IoT sensor data** - Device readings, telemetry
- **Metrics & monitoring** - Application metrics, infrastructure monitoring
- **Financial data** - Stock prices, transactions, trading data
- **Log analytics** - Application logs, audit trails
- **Event tracking** - User events, clickstreams

---

## Quick Start

### 1. Configure

```bash
cd timescaledb

# Create environment file
cp .env.example .env

# Generate strong password
openssl rand -base64 32

# Edit .env with your password
nano .env
```

### 2. Start TimescaleDB

```bash
# Make scripts executable
chmod +x scripts/*.sh
chmod +x init-scripts/*.sh

# Start container
docker compose up -d

# Check status
docker compose ps

# View logs
docker compose logs -f
```

### 3. Create Application User

```bash
# Create user with dedicated schema
./scripts/create-user.sh metrics_user "$(openssl rand -base64 32)" metrics
```

### 4. Create Your First Hypertable

```bash
# Connect to TimescaleDB
docker compose exec timescaledb psql -U postgres -d timeseries

# Create a hypertable
CREATE TABLE metrics.readings (
    time TIMESTAMPTZ NOT NULL,
    device_id TEXT NOT NULL,
    temperature DOUBLE PRECISION,
    humidity DOUBLE PRECISION
);

SELECT create_hypertable('metrics.readings', 'time');

# Exit
\q
```

### 5. Enable Compression & Retention

```bash
# Compress data older than 7 days
./scripts/manage-hypertable.sh compress metrics.readings "7 days"

# Drop data older than 90 days
./scripts/manage-hypertable.sh retention metrics.readings "90 days"
```

---

## Directory Structure

```
timescaledb/
├── docker-compose.yml          # Docker configuration
├── .env                        # Environment variables (DO NOT COMMIT)
├── .env.example                # Template for .env
├── config/
│   ├── postgresql.conf         # PostgreSQL/TimescaleDB configuration
│   └── pg_hba.conf             # Client authentication
├── init-scripts/
│   └── 01-init-timescaledb.sh  # Initialization script
└── scripts/
    ├── create-user.sh          # Create user & schema
    ├── list-users.sh           # List users, schemas, hypertables
    ├── delete-user.sh          # Delete user
    └── manage-hypertable.sh    # Manage compression & retention
```

---

## Connection Strings

### Admin

```bash
# Local
postgresql://postgres:PASSWORD@localhost:5433/timeseries

# Docker internal
postgresql://postgres:PASSWORD@timescaledb:5432/timeseries
```

### Application User

```bash
# Local
postgresql://metrics_user:PASSWORD@localhost:5433/timeseries?schema=metrics

# Docker internal
postgresql://metrics_user:PASSWORD@timescaledb:5432/timeseries?schema=metrics
```

---

## Hypertables

Hypertables are TimescaleDB's core abstraction for time-series data.

### Create Hypertable

```sql
-- Create table
CREATE TABLE metrics.sensor_data (
    time TIMESTAMPTZ NOT NULL,
    sensor_id TEXT NOT NULL,
    value DOUBLE PRECISION,
    metadata JSONB
);

-- Convert to hypertable (partitioned by time)
SELECT create_hypertable('metrics.sensor_data', 'time');

-- With custom chunk interval (default is 7 days)
SELECT create_hypertable('metrics.sensor_data', 'time',
    chunk_time_interval => INTERVAL '1 day'
);
```

### Insert Data

```sql
-- Single insert
INSERT INTO metrics.sensor_data (time, sensor_id, value)
VALUES (NOW(), 'sensor-1', 23.5);

-- Bulk insert (recommended)
INSERT INTO metrics.sensor_data (time, sensor_id, value)
VALUES
    (NOW(), 'sensor-1', 23.5),
    (NOW(), 'sensor-2', 45.2),
    (NOW(), 'sensor-3', 67.8);
```

### Query Data

```sql
-- Last hour
SELECT * FROM metrics.sensor_data
WHERE time > NOW() - INTERVAL '1 hour';

-- Time bucket aggregation (average per 5 minutes)
SELECT
    time_bucket('5 minutes', time) AS bucket,
    sensor_id,
    AVG(value) AS avg_value,
    COUNT(*) AS readings
FROM metrics.sensor_data
WHERE time > NOW() - INTERVAL '24 hours'
GROUP BY bucket, sensor_id
ORDER BY bucket DESC;
```

---

## Compression

TimescaleDB compresses old data to save disk space (up to 90% reduction).

### Enable Compression

```bash
# Via script
./scripts/manage-hypertable.sh compress metrics.sensor_data "7 days"

# Or manually
docker compose exec timescaledb psql -U postgres -d timeseries -c "
    ALTER TABLE metrics.sensor_data SET (timescaledb.compress);
    SELECT add_compression_policy('metrics.sensor_data', INTERVAL '7 days');
"
```

### Check Compression Stats

```bash
./scripts/manage-hypertable.sh stats metrics.sensor_data
```

### Manual Compression

```sql
-- Compress all chunks older than 7 days
SELECT compress_chunk(c.chunk_name)
FROM timescaledb_information.chunks c
WHERE c.hypertable_name = 'sensor_data'
  AND c.range_end < NOW() - INTERVAL '7 days'
  AND NOT c.is_compressed;
```

---

## Retention Policies

Automatically drop old data to manage storage.

### Enable Retention

```bash
# Via script (drop data older than 90 days)
./scripts/manage-hypertable.sh retention metrics.sensor_data "90 days"

# Or manually
docker compose exec timescaledb psql -U postgres -d timeseries -c "
    SELECT add_retention_policy('metrics.sensor_data', INTERVAL '90 days');
"
```

### Remove Retention Policy

```sql
SELECT remove_retention_policy('metrics.sensor_data');
```

---

## Continuous Aggregates

Pre-computed aggregations that update automatically.

### Create Continuous Aggregate

```sql
-- Create materialized view with automatic refresh
CREATE MATERIALIZED VIEW metrics.sensor_data_hourly
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 hour', time) AS bucket,
    sensor_id,
    AVG(value) AS avg_value,
    MIN(value) AS min_value,
    MAX(value) AS max_value,
    COUNT(*) AS readings
FROM metrics.sensor_data
GROUP BY bucket, sensor_id;

-- Add refresh policy (refresh every hour, for data up to 1 hour old)
SELECT add_continuous_aggregate_policy('metrics.sensor_data_hourly',
    start_offset => INTERVAL '3 hours',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour'
);
```

### Query Continuous Aggregate

```sql
-- Much faster than querying raw data
SELECT * FROM metrics.sensor_data_hourly
WHERE bucket > NOW() - INTERVAL '24 hours'
ORDER BY bucket DESC;
```

---

## Backend Usage

### Node.js with pg

```typescript
import { Pool } from 'pg';

const pool = new Pool({
  host: 'localhost',
  port: 5433,
  database: 'timeseries',
  user: 'metrics_user',
  password: process.env.TIMESCALE_PASSWORD,
});

// Insert data
await pool.query(
  'INSERT INTO metrics.sensor_data (time, sensor_id, value) VALUES ($1, $2, $3)',
  [new Date(), 'sensor-1', 23.5]
);

// Query with time bucket
const result = await pool.query(`
  SELECT
    time_bucket('5 minutes', time) AS bucket,
    AVG(value) AS avg_value
  FROM metrics.sensor_data
  WHERE time > NOW() - INTERVAL '1 hour'
  GROUP BY bucket
  ORDER BY bucket DESC
`);
```

### Python with psycopg2

```python
import psycopg2
from datetime import datetime, timedelta

conn = psycopg2.connect(
    host='localhost',
    port=5433,
    database='timeseries',
    user='metrics_user',
    password='your_password'
)

cursor = conn.cursor()

# Insert data
cursor.execute(
    "INSERT INTO metrics.sensor_data (time, sensor_id, value) VALUES (%s, %s, %s)",
    (datetime.now(), 'sensor-1', 23.5)
)
conn.commit()

# Query
cursor.execute("""
    SELECT time_bucket('5 minutes', time) AS bucket, AVG(value)
    FROM metrics.sensor_data
    WHERE time > NOW() - INTERVAL '1 hour'
    GROUP BY bucket
    ORDER BY bucket DESC
""")
```

---

## Monitoring

### Health Check

```bash
docker compose ps
docker compose exec timescaledb pg_isready -U postgres
```

### Database Size

```bash
docker compose exec timescaledb psql -U postgres -d timeseries -c "
    SELECT
        hypertable_schema,
        hypertable_name,
        pg_size_pretty(hypertable_size(format('%I.%I', hypertable_schema, hypertable_name)::regclass)) AS size
    FROM timescaledb_information.hypertables;
"
```

### Compression Ratio

```bash
./scripts/manage-hypertable.sh stats metrics.sensor_data
```

### Background Jobs

```sql
-- View scheduled jobs
SELECT * FROM timescaledb_information.jobs;

-- View job stats
SELECT * FROM timescaledb_information.job_stats;
```

---

## Configuration Tuning

### Memory Settings

Edit `config/postgresql.conf` based on VPS RAM:

| VPS RAM | shared_buffers | effective_cache_size | work_mem |
|---------|----------------|---------------------|----------|
| 2GB | 512MB | 1.5GB | 32MB |
| 4GB | 1GB | 3GB | 64MB |
| 8GB | 2GB | 6GB | 128MB |
| 16GB | 4GB | 12GB | 256MB |

### Resource Limits

Edit `docker-compose.yml`:

```yaml
deploy:
  resources:
    limits:
      cpus: '4'
      memory: 8G
```

---

## Backups

Backups are handled by the centralized backup system.

```bash
# See ../backup/README.md
../backup/scripts/backup-timescaledb.sh
```

For TimescaleDB-specific backup:

```bash
# Dump with TimescaleDB pre/post data scripts
docker compose exec timescaledb pg_dump -U postgres -Fc \
    --pre-data --post-data \
    timeseries > backup.dump

# Restore
docker compose exec -T timescaledb pg_restore -U postgres -d timeseries < backup.dump
```

---

## Troubleshooting

### Slow Queries

```sql
-- Enable timing
\timing on

-- Check query plan
EXPLAIN ANALYZE SELECT ...;

-- Check chunk exclusion is working
EXPLAIN SELECT * FROM metrics.sensor_data
WHERE time > NOW() - INTERVAL '1 hour';
```

### Compression Not Working

```bash
# Check compression policy
./scripts/list-users.sh

# Check job errors
docker compose exec timescaledb psql -U postgres -d timeseries -c "
    SELECT * FROM timescaledb_information.job_errors ORDER BY finish_time DESC LIMIT 10;
"
```

### Out of Disk Space

```bash
# Check chunk sizes
./scripts/manage-hypertable.sh chunks metrics.sensor_data

# Manually compress old chunks
docker compose exec timescaledb psql -U postgres -d timeseries -c "
    SELECT compress_chunk(chunk_name)
    FROM timescaledb_information.chunks
    WHERE hypertable_name = 'sensor_data'
      AND NOT is_compressed;
"

# Drop old data manually
SELECT drop_chunks('metrics.sensor_data', INTERVAL '30 days');
```

---

## Security Checklist

- [ ] Strong passwords (32+ characters)
- [ ] `.env` not in version control
- [ ] Firewall restricts port 5433
- [ ] Use application user (not postgres) for apps
- [ ] Backups configured
- [ ] Retention policies set to prevent unbounded growth

---

## Files NOT to Commit

Add to `.gitignore`:

```
.env
```

---

## Support

- [TimescaleDB Documentation](https://docs.timescale.com/)
- [TimescaleDB GitHub](https://github.com/timescale/timescaledb)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/17/)
- [TimescaleDB Slack Community](https://timescaledb.slack.com/)
