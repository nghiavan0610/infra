# Redis Production Setup

Production-ready Redis deployment using Docker.

## Features

- Redis 7 Alpine (lightweight)
- Password authentication
- Persistence (RDB + AOF hybrid)
- Memory limits with LRU eviction
- Dangerous commands disabled
- Resource limits (CPU/Memory)
- Health checks
- Slow query logging

---

## Quick Start

### 1. Configure

```bash
cd redis

# Create environment file
cp .env.example .env

# Generate strong password
openssl rand -base64 32

# Edit .env with your password
nano .env
```

### 2. Start Redis

```bash
# Fix config permissions
chmod 644 config/redis.conf

# Start container
docker compose up -d

# Check status
docker compose ps
docker compose logs -f
```

### 3. Verify Connection

```bash
# Connect with redis-cli
docker compose exec redis redis-cli -a YOUR_PASSWORD

# Test
127.0.0.1:6379> PING
PONG
127.0.0.1:6379> SET test "hello"
OK
127.0.0.1:6379> GET test
"hello"
```

---

## Directory Structure

```
redis/
├── docker-compose.yml    # Docker configuration
├── .env                  # Environment variables (DO NOT COMMIT)
├── .env.example         # Template for .env
├── config/
│   └── redis.conf       # Redis configuration
└── README.md
```

---

## Configuration

### Memory Settings

Adjust in `config/redis.conf`:

| VPS Size | RAM    | maxmemory | Container limit |
|----------|--------|-----------|-----------------|
| Small    | 1-2GB  | 256mb     | 384M            |
| Medium   | 4-8GB  | 1gb       | 1536M           |
| Large    | 16GB+  | 4gb       | 5G              |

```conf
# In redis.conf
maxmemory 1gb
```

```yaml
# In docker-compose.yml
deploy:
  resources:
    limits:
      memory: 1536M  # maxmemory + ~50% overhead
```

### Eviction Policies

```conf
# For cache (recommended)
maxmemory-policy allkeys-lru

# For persistent data (returns error when full)
maxmemory-policy noeviction

# For sessions (keys with TTL only)
maxmemory-policy volatile-lru
```

### Persistence

Current config uses **hybrid persistence** (RDB + AOF):

```conf
# RDB snapshots
save 900 1      # Save after 15 min if 1 key changed
save 300 10     # Save after 5 min if 10 keys changed
save 60 10000   # Save after 1 min if 10000 keys changed

# AOF (Append Only File)
appendonly yes
appendfsync everysec  # Sync every second
```

**Disable persistence** (for pure cache):
```conf
save ""
appendonly no
```

---

## Security

### Disabled Commands

These dangerous commands are disabled by default:

| Command | Status |
|---------|--------|
| FLUSHDB | Disabled |
| FLUSHALL | Disabled |
| DEBUG | Disabled |
| CONFIG | Renamed |
| SHUTDOWN | Renamed |

To use renamed commands:
```bash
# CONFIG is renamed to CONFIG_b4c9a2f8e7d1
redis-cli -a PASSWORD CONFIG_b4c9a2f8e7d1 GET maxmemory
```

### Network Security

Restrict access with firewall:
```bash
# Allow only from specific IPs
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.0.0.0/8" port port="6379" protocol="tcp" accept'
sudo firewall-cmd --reload
```

Or bind to localhost only in `docker-compose.yml`:
```yaml
ports:
  - "127.0.0.1:6379:6379"
```

---

## Monitoring

### Health Check

```bash
# Container health
docker inspect redis --format='{{.State.Health.Status}}'

# Redis info
docker compose exec redis redis-cli -a PASSWORD INFO
```

### Memory Usage

```bash
docker compose exec redis redis-cli -a PASSWORD INFO memory
```

Key metrics:
- `used_memory_human`: Current memory usage
- `used_memory_peak_human`: Peak memory usage
- `maxmemory_human`: Memory limit

### Slow Queries

```bash
# View slow queries (> 10ms)
docker compose exec redis redis-cli -a PASSWORD SLOWLOG GET 10
```

### Connected Clients

```bash
docker compose exec redis redis-cli -a PASSWORD CLIENT LIST
```

### Statistics

```bash
# All stats
docker compose exec redis redis-cli -a PASSWORD INFO stats

# Key metrics
docker compose exec redis redis-cli -a PASSWORD INFO keyspace
```

---

## Backup & Restore

### Manual Backup

```bash
# Trigger RDB save
docker compose exec redis redis-cli -a PASSWORD BGSAVE_b4c9a2f8e7d1

# Copy RDB file
docker cp redis:/data/dump.rdb ./backups/dump_$(date +%Y%m%d).rdb
```

### Automated Backup (Cron)

```bash
crontab -e

# Daily backup at 3 AM
0 3 * * * docker cp redis:/data/dump.rdb /path/to/backups/dump_$(date +\%Y\%m\%d).rdb
```

### Restore

```bash
# Stop Redis
docker compose down

# Copy backup to volume
docker run --rm -v redis_data:/data -v $(pwd)/backups:/backups alpine \
  cp /backups/dump_20250101.rdb /data/dump.rdb

# Start Redis
docker compose up -d
```

---

## Connection Strings

### Application

```
redis://:PASSWORD@localhost:6379/0
```

### Docker Internal

```
redis://:PASSWORD@redis:6379/0
```

### With Database Number

```
redis://:PASSWORD@localhost:6379/1
```

### Node.js Example

```javascript
const Redis = require('ioredis');
const redis = new Redis({
  host: 'localhost',
  port: 6379,
  password: 'YOUR_PASSWORD',
  db: 0,
});
```

### Python Example

```python
import redis
r = redis.Redis(
    host='localhost',
    port=6379,
    password='YOUR_PASSWORD',
    db=0,
    decode_responses=True
)
```

---

## Troubleshooting

### Connection Refused

```bash
# Check if container is running
docker compose ps

# Check logs
docker compose logs redis

# Test connection
docker compose exec redis redis-cli -a PASSWORD PING
```

### Out of Memory

```bash
# Check memory usage
docker compose exec redis redis-cli -a PASSWORD INFO memory

# Check eviction stats
docker compose exec redis redis-cli -a PASSWORD INFO stats | grep evicted
```

If `evicted_keys` is high, increase `maxmemory` or change eviction policy.

### Slow Performance

```bash
# Check slow queries
docker compose exec redis redis-cli -a PASSWORD SLOWLOG GET 20

# Check client connections
docker compose exec redis redis-cli -a PASSWORD CLIENT LIST | wc -l

# Check if persistence is causing issues
docker compose exec redis redis-cli -a PASSWORD INFO persistence
```

### Data Loss After Restart

Ensure persistence is enabled:
```conf
# In redis.conf
appendonly yes
save 900 1
```

Check if data directory has proper permissions:
```bash
docker compose exec redis ls -la /data
```

---

## Performance Tuning

### For High Traffic

```conf
# In redis.conf - enable I/O threads
io-threads 4
io-threads-do-reads yes
```

### For Large Keys

```conf
# Increase client buffer
client-output-buffer-limit normal 256mb 128mb 60
```

### TCP Tuning

On the host:
```bash
# Increase somaxconn
echo 'net.core.somaxconn=65535' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

---

## Security Checklist

- [ ] Strong password (32+ characters)
- [ ] .env not in version control
- [ ] Firewall restricts Redis port
- [ ] Dangerous commands disabled
- [ ] Not exposed to public internet
- [ ] TLS enabled for remote connections (optional)

---

## Files NOT to Commit

Add to `.gitignore`:

```
.env
```

---

## Support

- [Redis Documentation](https://redis.io/docs/)
- [Redis Configuration](https://redis.io/docs/management/config/)
- [Docker Hub - Redis](https://hub.docker.com/_/redis)
