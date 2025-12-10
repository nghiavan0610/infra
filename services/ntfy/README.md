# Ntfy

Simple push notification service for alerts and notifications.

## Quick Start

```bash
# Start Ntfy
docker compose up -d

# Access web UI
open http://localhost:8090

# Send a test notification
curl -d "Hello from infrastructure!" http://localhost:8090/test
```

## How It Works

1. Create a topic (any name you want)
2. Subscribe to the topic on your phone/browser
3. Send messages to the topic via API
4. Receive push notifications

## Mobile Apps

- [Android](https://play.google.com/store/apps/details?id=io.heckel.ntfy)
- [iOS](https://apps.apple.com/app/ntfy/id1625396347)
- [F-Droid](https://f-droid.org/packages/io.heckel.ntfy/)

## Subscribe to Topic

### Mobile App
1. Install ntfy app
2. Add subscription
3. Enter server URL: `http://your-server:8090`
4. Enter topic name: `alerts`

### Web Browser
1. Open http://localhost:8090
2. Click "Subscribe to topic"
3. Enter topic name

## Send Notifications

### Simple Message
```bash
curl -d "Server backup completed" http://localhost:8090/alerts
```

### With Title
```bash
curl -H "Title: Backup Complete" \
     -d "All databases backed up successfully" \
     http://localhost:8090/alerts
```

### With Priority
```bash
# Priorities: min, low, default, high, urgent
curl -H "Priority: urgent" \
     -H "Title: Server Down!" \
     -d "Web server is not responding" \
     http://localhost:8090/alerts
```

### With Tags/Emoji
```bash
curl -H "Tags: warning,skull" \
     -H "Title: High CPU Usage" \
     -d "Server CPU at 95%" \
     http://localhost:8090/alerts
```

### With Click Action
```bash
curl -H "Click: https://grafana.example.com" \
     -H "Title: Alert Triggered" \
     -d "Click to view dashboard" \
     http://localhost:8090/alerts
```

### With Attachment
```bash
curl -H "Filename: error.log" \
     -T /var/log/error.log \
     http://localhost:8090/alerts
```

## Integration Examples

### Alertmanager

In `alertmanager.yml`:
```yaml
receivers:
  - name: 'ntfy'
    webhook_configs:
      - url: 'http://ntfy:80/alertmanager'
        send_resolved: true
```

### Prometheus Alert Rules

Configure Alertmanager to send to ntfy webhook.

### Shell Script
```bash
#!/bin/bash
# Send notification on script completion
do_backup() {
    # backup logic
}

if do_backup; then
    curl -H "Tags: white_check_mark" \
         -d "Backup completed successfully" \
         http://localhost:8090/backups
else
    curl -H "Priority: high" \
         -H "Tags: x" \
         -d "Backup FAILED!" \
         http://localhost:8090/backups
fi
```

### Watchtower
```bash
WATCHTOWER_NOTIFICATION_URL=ntfy://localhost:8090/watchtower
```

### Cron Jobs
```bash
0 2 * * * /scripts/backup.sh && curl -d "Backup done" http://localhost:8090/cron
```

### Healthchecks.io Integration
Configure healthchecks to notify via ntfy on failures.

## User Management

Create admin user:
```bash
docker exec -it ntfy ntfy user add --role=admin admin
```

Create regular user:
```bash
docker exec -it ntfy ntfy user add user1
```

Set topic permissions:
```bash
# Allow user1 to read/write to 'alerts' topic
docker exec -it ntfy ntfy access user1 alerts rw
```

## Topic Access Control

### Public Topics (default)
Anyone can subscribe and publish.

### Private Topics
1. Disable default access in config
2. Create users
3. Assign permissions per topic

```bash
# Make 'alerts' topic private
docker exec -it ntfy ntfy access '*' alerts deny-all
docker exec -it ntfy ntfy access admin alerts rw
```

## Configuration

Edit `.env`:
```bash
# Disable anonymous access
NTFY_AUTH_DEFAULT_ACCESS=deny-all

# Enable behind Traefik
NTFY_BEHIND_PROXY=true
```

## Common Topics Setup

| Topic | Use Case |
|-------|----------|
| `alerts` | General system alerts |
| `backups` | Backup notifications |
| `deployments` | CI/CD notifications |
| `errors` | Application errors |
| `watchtower` | Container updates |
| `cron` | Scheduled job status |

## Security

### For Production

1. Set up authentication:
   ```bash
   NTFY_AUTH_DEFAULT_ACCESS=deny-all
   NTFY_ENABLE_SIGNUP=false
   ```

2. Create admin user:
   ```bash
   docker exec -it ntfy ntfy user add --role=admin admin
   ```

3. Use HTTPS via Traefik

### Topic Tokens

Generate tokens for scripts:
```bash
docker exec -it ntfy ntfy token add user1
```

Use in scripts:
```bash
curl -H "Authorization: Bearer tk_xxx" \
     -d "Message" \
     http://localhost:8090/alerts
```

## Backup

```bash
docker run --rm \
  -v ntfy_data:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/ntfy-backup.tar.gz /data
```
