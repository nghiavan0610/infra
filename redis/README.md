# Redis Production Configuration - Cache & Queue

Two isolated Redis instances optimized for different use cases.

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
    │   redis-cache   │           │   redis-queue   │
    │   Port: 6379    │           │   Port: 6380    │
    │                 │           │                 │
    │ • LRU eviction  │           │ • No eviction   │
    │ • No persistence│           │ • AOF + RDB     │
    │ • Volatile data │           │ • Durable data  │
    └─────────────────┘           └─────────────────┘
```

## Comparison

| Aspect | redis-cache | redis-queue |
|--------|-------------|-------------|
| **Port** | 6379 | 6380 |
| **Eviction** | `allkeys-lru` | `noeviction` |
| **Persistence** | None | AOF + RDB |
| **Data loss** | Acceptable | NOT acceptable |
| **Use case** | API cache, sessions | BullMQ, job queues |
| **Backup** | Not needed | Include in backups |

---

## Quick Start

### 1. Configure

```bash
cd redis

# Create environment file
cp .env.example .env

# Generate passwords
openssl rand -base64 32  # For REDIS_CACHE_PASSWORD
openssl rand -base64 32  # For REDIS_QUEUE_PASSWORD

# Edit .env with your passwords
nano .env
```

### 2. Start

```bash
# Start both instances
docker compose up -d

# Start only cache
docker compose up -d redis-cache

# Start only queue
docker compose up -d redis-queue

# Check status
docker compose ps
```

### 3. Connect

```bash
# Connect to cache
docker compose exec redis-cache redis-cli -a "$REDIS_CACHE_PASSWORD"

# Connect to queue
docker compose exec redis-queue redis-cli -a "$REDIS_QUEUE_PASSWORD"
```

---

## Directory Structure

```
redis/
├── docker-compose.yml      # Both Redis services
├── .env                    # Environment variables (DO NOT COMMIT)
├── .env.example            # Template for .env
└── config/
    ├── redis-cache.conf    # Cache configuration (no persistence)
    ├── redis-queue.conf    # Queue configuration (full persistence)
    └── redis.conf          # Legacy single-instance config (unused)
```

---

## Connection Strings

### Redis Cache (Port 6379)

```bash
# Local connection
redis://:PASSWORD@localhost:6379

# Docker internal (from other containers)
redis://:PASSWORD@redis-cache:6379

# With database number
redis://:PASSWORD@localhost:6379/0
```

### Redis Queue (Port 6380)

```bash
# Local connection
redis://:PASSWORD@localhost:6380

# Docker internal (from other containers)
redis://:PASSWORD@redis-queue:6379

# With database number
redis://:PASSWORD@localhost:6380/0
```

---

## Backend Usage

### Node.js with ioredis

```typescript
import Redis from 'ioredis';

// Cache connection (volatile)
const cacheRedis = new Redis({
  host: 'localhost',
  port: 6379,
  password: process.env.REDIS_CACHE_PASSWORD,
});

// Queue connection (persistent)
const queueRedis = new Redis({
  host: 'localhost',
  port: 6380,
  password: process.env.REDIS_QUEUE_PASSWORD,
});

// Use cache for temporary data
await cacheRedis.setex('api:users:123', 300, JSON.stringify(userData));

// Use queue for job data (handled by BullMQ internally)
```

### BullMQ

```typescript
import { Queue, Worker } from 'bullmq';

const connection = {
  host: 'localhost',
  port: 6380,  // Queue Redis, NOT cache
  password: process.env.REDIS_QUEUE_PASSWORD,
};

// Create queue
const emailQueue = new Queue('email', { connection });

// Add job
await emailQueue.add('send-welcome', {
  to: 'user@example.com',
  template: 'welcome',
});

// Process jobs
const worker = new Worker('email', async (job) => {
  await sendEmail(job.data);
}, { connection });
```

### NestJS with @nestjs/bullmq

```typescript
// app.module.ts
import { BullModule } from '@nestjs/bullmq';

@Module({
  imports: [
    BullModule.forRoot({
      connection: {
        host: 'localhost',
        port: 6380,
        password: process.env.REDIS_QUEUE_PASSWORD,
      },
    }),
    BullModule.registerQueue({
      name: 'email',
    }),
  ],
})
export class AppModule {}
```

---

## Monitoring

### Health Check

```bash
# Check both instances
docker compose ps

# Check cache
docker compose exec redis-cache redis-cli -a "$REDIS_CACHE_PASSWORD" ping

# Check queue
docker compose exec redis-queue redis-cli -a "$REDIS_QUEUE_PASSWORD" ping
```

### Memory Usage

```bash
# Cache memory
docker compose exec redis-cache redis-cli -a "$REDIS_CACHE_PASSWORD" INFO memory

# Queue memory
docker compose exec redis-queue redis-cli -a "$REDIS_QUEUE_PASSWORD" INFO memory
```

### Key Statistics

```bash
# Cache stats
docker compose exec redis-cache redis-cli -a "$REDIS_CACHE_PASSWORD" INFO stats

# Queue stats
docker compose exec redis-queue redis-cli -a "$REDIS_QUEUE_PASSWORD" INFO stats
```

### Slow Queries

```bash
# Cache slow log
docker compose exec redis-cache redis-cli -a "$REDIS_CACHE_PASSWORD" SLOWLOG GET 10

# Queue slow log
docker compose exec redis-queue redis-cli -a "$REDIS_QUEUE_PASSWORD" SLOWLOG GET 10
```

---

## Backups

### Queue Redis (Important!)

Queue data must be backed up. Backups are handled by the centralized backup system.

```bash
# See ../backup/README.md for documentation
../backup/scripts/backup-redis.sh
```

### Cache Redis

Cache doesn't need backups - data is volatile and can be regenerated.

---

## Configuration Tuning

### Memory Settings

Edit `config/redis-cache.conf` or `config/redis-queue.conf`:

| VPS RAM | Cache maxmemory | Queue maxmemory |
|---------|-----------------|-----------------|
| 2GB | 256mb | 256mb |
| 4GB | 512mb | 512mb |
| 8GB | 1gb | 1gb |
| 16GB+ | 2-4gb | 2-4gb |

### Resource Limits

Edit `docker-compose.yml`:

```yaml
deploy:
  resources:
    limits:
      cpus: '2'      # Adjust based on VPS
      memory: 1G     # maxmemory + ~50% overhead
```

---

## Troubleshooting

### OOM (Out of Memory) - Cache

Cache will evict old keys automatically (LRU). If you see evictions:

```bash
# Check evicted keys
docker compose exec redis-cache redis-cli -a "$REDIS_CACHE_PASSWORD" INFO stats | grep evicted
```

If too many evictions, increase `maxmemory` in `redis-cache.conf`.

### OOM (Out of Memory) - Queue

Queue returns errors instead of evicting. This means your queue is too full.

```bash
# Check memory usage
docker compose exec redis-queue redis-cli -a "$REDIS_QUEUE_PASSWORD" INFO memory | grep used_memory_human
```

Solutions:
1. Increase `maxmemory` in `redis-queue.conf`
2. Process jobs faster (add more workers)
3. Reduce job payload sizes
4. Clean up completed/failed jobs

### Connection Refused

```bash
# Check containers are running
docker compose ps

# Check logs
docker compose logs redis-cache
docker compose logs redis-queue
```

### Persistence Issues (Queue)

```bash
# Check AOF status
docker compose exec redis-queue redis-cli -a "$REDIS_QUEUE_PASSWORD" INFO persistence

# Check last save time
docker compose exec redis-queue redis-cli -a "$REDIS_QUEUE_PASSWORD" LASTSAVE
```

---

## Security Checklist

- [ ] Strong passwords (32+ characters) for both instances
- [ ] `.env` not in version control
- [ ] Firewall restricts Redis ports (6379, 6380)
- [ ] Different passwords for cache and queue
- [ ] Queue Redis included in backup strategy

---

## Files NOT to Commit

Add to `.gitignore`:

```
.env
```

---

## Support

- [Redis Documentation](https://redis.io/docs/)
- [BullMQ Documentation](https://docs.bullmq.io/)
- [ioredis Documentation](https://github.com/redis/ioredis)
