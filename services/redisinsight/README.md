# RedisInsight

Official Redis GUI for managing and visualizing Redis data.

## Quick Start

```bash
# Start RedisInsight
docker compose up -d

# Access UI
open http://localhost:5540
```

## Connect to Redis

1. Open http://localhost:5540
2. Click "Add Redis Database"
3. Enter connection details:
   - **Host**: `redis` (or `host.docker.internal` for host Redis)
   - **Port**: `6379`
   - **Password**: Your Redis password
4. Click "Add Redis Database"

### Connect to Infrastructure Redis

If using the infra Redis service:
- Host: `redis`
- Port: `6379`
- Password: (from redis .env or .secrets)

## Features

### Browser
- View all keys with filtering and search
- Edit values for strings, hashes, lists, sets, sorted sets
- TTL management
- Key pattern analysis

### CLI
- Built-in Redis CLI
- Command history
- Auto-complete

### Workbench
- Write and execute Redis commands
- Save and share command snippets
- Visualize results

### Streams
- View stream entries
- Consumer group management
- Real-time stream monitoring

### Pub/Sub
- Subscribe to channels
- Publish messages
- Monitor real-time messages

### Slow Log
- View slow queries
- Identify performance bottlenecks

### Memory Analysis
- Analyze memory usage by key patterns
- Identify large keys
- Memory recommendations

## Configuration

Edit `.env`:
- `REDISINSIGHT_PORT` - Web UI port (default: 5540)
- `REDISINSIGHT_LOG_LEVEL` - Logging level

## Managing Multiple Redis Instances

RedisInsight can connect to multiple Redis instances:

1. Click "Add Redis Database" for each instance
2. Give each a descriptive name
3. Switch between databases in the sidebar

Common setups:
- Production vs Development
- Cache Redis vs Queue Redis
- Master vs Replicas

## Tips

### Keyboard Shortcuts
- `Ctrl/Cmd + K` - Quick search
- `Ctrl/Cmd + Enter` - Execute command in Workbench

### Key Patterns
Use wildcards to filter keys:
- `user:*` - All user keys
- `cache:*:data` - Specific pattern
- `*session*` - Contains "session"

### Bulk Operations
- Select multiple keys for bulk delete
- Use Workbench for bulk operations with Lua scripts

## Security

RedisInsight stores database credentials locally. For production:

1. Use Traefik for HTTPS access
2. Consider authentication via Authentik
3. Restrict network access

## Backup

```bash
# Backup RedisInsight settings and connections
docker run --rm -v redisinsight_data:/data -v $(pwd):/backup alpine \
    tar czf /backup/redisinsight-backup.tar.gz /data
```
