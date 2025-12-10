# Watchtower

Automatically update Docker containers when new images are available.

## Quick Start

```bash
# Start Watchtower
docker compose up -d

# Check logs
docker compose logs -f
```

## How It Works

1. Watchtower monitors running containers
2. Checks for new image versions on schedule
3. Pulls new images and recreates containers
4. Cleans up old images

Default: Checks daily at 4 AM.

## Configuration

Edit `.env`:

```bash
# Check every 6 hours
WATCHTOWER_SCHEDULE=0 0 */6 * * *

# Check daily at 3 AM
WATCHTOWER_SCHEDULE=0 0 3 * * *

# Check every hour
WATCHTOWER_SCHEDULE=0 0 * * * *
```

## Selective Updates

By default, Watchtower updates ALL containers. For more control:

### Option 1: Label-based (Opt-in)

Set in `.env`:
```bash
WATCHTOWER_LABEL_ENABLE=true
```

Then add labels to containers you want updated:
```yaml
services:
  myapp:
    labels:
      - "com.centurylinklabs.watchtower.enable=true"
```

### Option 2: Exclude specific containers

Add to containers you DON'T want updated:
```yaml
services:
  database:
    labels:
      - "com.centurylinklabs.watchtower.enable=false"
```

## Notifications

### Ntfy (recommended with infra stack)

```bash
WATCHTOWER_NOTIFICATIONS=shoutrrr
WATCHTOWER_NOTIFICATION_URL=ntfy://localhost:8090/watchtower
```

### Slack

```bash
WATCHTOWER_NOTIFICATIONS=shoutrrr
WATCHTOWER_NOTIFICATION_URL=slack://token-a/token-b/token-c
```

### Email

```bash
WATCHTOWER_NOTIFICATIONS=shoutrrr
WATCHTOWER_NOTIFICATION_URL=smtp://user:pass@smtp.gmail.com:587/?from=alerts@example.com&to=admin@example.com
```

### Discord

```bash
WATCHTOWER_NOTIFICATIONS=shoutrrr
WATCHTOWER_NOTIFICATION_URL=discord://token@webhookid
```

## Manual Update

Force immediate check:

```bash
docker exec watchtower /watchtower --run-once
```

## View Update History

```bash
docker compose logs watchtower | grep "Updated"
```

## Best Practices

1. **Production databases**: Disable auto-updates
   ```yaml
   labels:
     - "com.centurylinklabs.watchtower.enable=false"
   ```

2. **Use specific tags**: Avoid `latest` tag for critical services
   ```yaml
   image: postgres:16.2  # Specific version
   # NOT: image: postgres:latest
   ```

3. **Rolling restarts**: Enable for zero-downtime
   ```bash
   WATCHTOWER_ROLLING_RESTART=true
   ```

4. **Monitor notifications**: Set up alerts to know when updates happen

## Security Considerations

- Watchtower has full Docker access via socket
- Updates happen automatically - ensure you trust image sources
- Consider label-based opt-in for critical infrastructure
- Test updates in staging first for production apps
