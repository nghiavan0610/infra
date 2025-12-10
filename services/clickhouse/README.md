# ClickHouse

High-performance columnar OLAP database for analytics workloads.

## Quick Start

```bash
# Start ClickHouse
docker compose up -d

# Check status
docker compose ps
docker compose logs -f
```

## Create User & Database

```bash
# Create user with new database
./scripts/create-user.sh analytics_user password123 analytics

# Create user for existing database
./scripts/create-user.sh analytics_user password123
```

## Connect

```bash
# HTTP interface (browser or curl)
curl "http://localhost:8123/?query=SELECT%201"

# CLI client
docker exec -it clickhouse clickhouse-client

# With credentials
docker exec -it clickhouse clickhouse-client --user default --password yourpassword
```

## Connection Strings

```
# HTTP
http://user:password@localhost:8123/database

# Native protocol
clickhouse://user:password@localhost:9000/database
```

## Basic Queries

```sql
-- Create table (MergeTree for analytics)
CREATE TABLE events (
    event_date Date,
    event_time DateTime,
    user_id UInt64,
    event_type String,
    properties String
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_date)
ORDER BY (event_date, user_id);

-- Insert data
INSERT INTO events VALUES
    ('2024-01-15', '2024-01-15 10:30:00', 123, 'click', '{}');

-- Query with aggregation
SELECT
    toDate(event_time) as date,
    count() as events,
    uniq(user_id) as users
FROM events
GROUP BY date
ORDER BY date;
```

## Configuration

Edit `.env`:
- `CLICKHOUSE_DB` - Default database
- `CLICKHOUSE_USER` - Default username
- `CLICKHOUSE_PASSWORD` - Default password
- `CLICKHOUSE_HTTP_PORT` - HTTP interface port (default: 8123)
- `CLICKHOUSE_NATIVE_PORT` - Native protocol port (default: 9000)

## Monitoring

Built-in Prometheus metrics at `http://localhost:8123/metrics`

Key metrics:
- `ClickHouseProfileEvents_Query` - Query count
- `ClickHouseMetrics_Query` - Active queries
- `ClickHouseAsyncMetrics_MaxPartCountForPartition` - Partition health
- `ClickHouseMetrics_MemoryTracking` - Memory usage

## Use Cases

ClickHouse excels at:
- **Analytics dashboards** - Fast aggregations over billions of rows
- **Log analytics** - Store and query application logs
- **Time-series data** - IoT, metrics, events
- **Real-time reporting** - Sub-second query response

## ClickHouse vs PostgreSQL

| Feature | ClickHouse | PostgreSQL |
|---------|------------|------------|
| Type | Columnar OLAP | Row-based OLTP |
| Best for | Analytics, aggregations | Transactions, CRUD |
| Insert speed | Very fast (batch) | Fast (row-by-row) |
| Query speed | Extremely fast for aggregations | Fast for point queries |
| Updates/Deletes | Limited | Full support |

## Performance Tips

1. **Use appropriate table engines**
   - `MergeTree` for most analytics
   - `SummingMergeTree` for pre-aggregated data
   - `AggregatingMergeTree` for incremental aggregations

2. **Partition wisely**
   - Partition by time (month/day) for time-series
   - Don't over-partition (aim for parts > 1GB)

3. **Choose good ORDER BY**
   - Most filtered columns first
   - Affects data compression and query speed

4. **Batch inserts**
   - Insert thousands of rows at once
   - Avoid single-row inserts
