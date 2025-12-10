# Memcached

High-performance distributed memory caching system.

## Quick Start

```bash
# Start Memcached
docker compose up -d

# Check status
docker compose ps
```

## Connect

```bash
# Using telnet
telnet localhost 11211

# Using netcat
echo "stats" | nc localhost 11211
```

## Basic Commands

```bash
# Set a value (telnet)
set mykey 0 3600 5
hello

# Get a value
get mykey

# Delete a value
delete mykey

# View stats
stats
stats items
stats slabs
```

## Client Libraries

### Python
```python
import memcache
mc = memcache.Client(['localhost:11211'])
mc.set('key', 'value', time=3600)
value = mc.get('key')
```

### Node.js
```javascript
const Memcached = require('memcached');
const memcached = new Memcached('localhost:11211');
memcached.set('key', 'value', 3600, (err) => {});
memcached.get('key', (err, data) => {});
```

### PHP
```php
$memcached = new Memcached();
$memcached->addServer('localhost', 11211);
$memcached->set('key', 'value', 3600);
$value = $memcached->get('key');
```

## Configuration

Edit `.env`:
- `MEMCACHED_MEMORY` - Memory limit in MB (default: 64)
- `MEMCACHED_MAX_CONNECTIONS` - Max connections (default: 1024)
- `MEMCACHED_THREADS` - Worker threads (default: 4)

## Monitoring

Metrics exported on port 9150 for Prometheus.

Key metrics:
- `memcached_up` - Server availability
- `memcached_current_connections` - Active connections
- `memcached_commands_total` - Command counts (get, set, delete)
- `memcached_current_bytes` - Memory usage
- `memcached_items_current` - Stored items count
- `memcached_get_hits_total` / `memcached_get_misses_total` - Cache hit ratio

## Performance Tuning

For production:
```bash
# Increase memory (25% of available RAM for caching)
MEMCACHED_MEMORY=512

# Increase connections for high traffic
MEMCACHED_MAX_CONNECTIONS=4096

# Match threads to CPU cores
MEMCACHED_THREADS=8
```

## Memcached vs Redis

| Feature | Memcached | Redis |
|---------|-----------|-------|
| Data types | Simple key-value | Rich (lists, sets, hashes) |
| Persistence | No | Yes |
| Memory efficiency | Better for simple caching | More features, more overhead |
| Multi-threaded | Yes | Single-threaded (mostly) |
| Use case | Pure caching | Caching + data structures |

Use Memcached when you need simple, fast caching without persistence.
Use Redis when you need data structures, persistence, or pub/sub.
