# Healthchecks

Cron job and scheduled task monitoring - know when your jobs fail.

## Quick Start

```bash
# Generate secret key
echo "HEALTHCHECKS_SECRET_KEY=$(openssl rand -base64 32)" >> .env
echo "HEALTHCHECKS_DB_PASSWORD=$(openssl rand -hex 16)" >> .env

# Start Healthchecks
docker compose up -d

# Access UI
open http://localhost:8000
```

## First Setup

1. Open http://localhost:8000
2. Click "Sign Up" to create admin account
3. After creating account, disable registration:
   ```bash
   HEALTHCHECKS_REGISTRATION_OPEN=false
   ```
4. Restart: `docker compose up -d`

## How It Works

1. Create a check (get a unique ping URL)
2. Add ping to your cron job / script
3. If ping doesn't arrive on schedule → alert

## Creating Checks

1. Click "Add Check"
2. Set schedule:
   - Period: How often job runs (e.g., every 1 hour)
   - Grace: How long to wait before alerting (e.g., 5 minutes)
3. Copy the ping URL

## Integrating with Cron Jobs

### Basic Ping
```bash
# At the END of your cron job
0 * * * * /scripts/backup.sh && curl -fsS --retry 3 https://hc-ping.com/your-uuid-here
```

### With Start Signal
```bash
# Signal start AND completion
0 * * * * curl -fsS --retry 3 https://hc-ping.com/your-uuid-here/start && /scripts/backup.sh && curl -fsS --retry 3 https://hc-ping.com/your-uuid-here
```

### With Exit Code
```bash
# Report success/failure
0 * * * * /scripts/backup.sh; curl -fsS --retry 3 https://hc-ping.com/your-uuid-here/$?
```

### With Logs
```bash
# Include output in ping
0 * * * * /scripts/backup.sh 2>&1 | curl -fsS --retry 3 --data-binary @- https://hc-ping.com/your-uuid-here
```

## Script Examples

### Bash Script
```bash
#!/bin/bash
PING_URL="http://localhost:8000/ping/your-uuid-here"

# Signal start
curl -fsS --retry 3 "${PING_URL}/start"

# Do work
if /scripts/backup.sh; then
    # Success
    curl -fsS --retry 3 "${PING_URL}"
else
    # Failure
    curl -fsS --retry 3 "${PING_URL}/fail"
fi
```

### Python Script
```python
import requests
import sys

PING_URL = "http://localhost:8000/ping/your-uuid-here"

# Signal start
requests.get(f"{PING_URL}/start", timeout=10)

try:
    # Do work
    run_backup()
    # Success
    requests.get(PING_URL, timeout=10)
except Exception as e:
    # Failure with message
    requests.post(f"{PING_URL}/fail", data=str(e), timeout=10)
    sys.exit(1)
```

### Docker Container
```bash
# Healthcheck in docker-compose.yml
healthcheck:
  test: ["CMD", "curl", "-fsS", "http://healthchecks:8000/ping/uuid"]
  interval: 5m
```

## Notification Channels

### Email
Configure SMTP in `.env`:
```bash
HEALTHCHECKS_EMAIL_HOST=smtp.gmail.com
HEALTHCHECKS_EMAIL_PORT=587
HEALTHCHECKS_EMAIL_USER=your-email@gmail.com
HEALTHCHECKS_EMAIL_PASSWORD=your-app-password
```

### Ntfy (Self-hosted)
1. Add Integration > Webhook
2. URL: `http://ntfy:80/healthchecks`
3. Method: POST

### Slack
1. Create Slack App
2. Add Integration > Slack
3. Configure OAuth

### Other Integrations
- Discord
- Telegram
- PagerDuty
- Opsgenie
- Custom Webhooks

## Common Checks to Monitor

| Check | Schedule | Grace |
|-------|----------|-------|
| Daily backup | 24h | 1h |
| Hourly sync | 1h | 15m |
| SSL cert renewal | 12h | 2h |
| Log rotation | 24h | 2h |
| Database cleanup | 24h | 1h |
| Health endpoint | 5m | 2m |

## API Usage

### Ping Endpoints
```bash
# Success
curl http://localhost:8000/ping/<uuid>

# Start signal
curl http://localhost:8000/ping/<uuid>/start

# Failure
curl http://localhost:8000/ping/<uuid>/fail

# With exit code (0=success, 1-255=failure)
curl http://localhost:8000/ping/<uuid>/1
```

### Management API
```bash
# List checks
curl -H "X-Api-Key: your-api-key" http://localhost:8000/api/v1/checks/

# Create check
curl -X POST \
  -H "X-Api-Key: your-api-key" \
  -H "Content-Type: application/json" \
  -d '{"name": "Backup", "schedule": "0 2 * * *", "tz": "UTC"}' \
  http://localhost:8000/api/v1/checks/
```

## Best Practices

1. **Use grace period** - Allow time for late starts
2. **Signal start** - Know if job started but didn't finish
3. **Include logs** - Debug failures easily
4. **Group related checks** - Use projects/tags
5. **Set up escalation** - Multiple notification channels

## Configuration

Edit `.env` for custom settings:
```bash
# Custom site name
HEALTHCHECKS_SITE_NAME="MyCompany Cron Monitor"

# Custom ping endpoint display
HEALTHCHECKS_PING_ENDPOINT=https://hc.example.com/ping/
```

## Backup

```bash
# Backup database
docker exec healthchecks-db pg_dump -U healthchecks healthchecks > healthchecks-backup.sql

# Restore
docker exec -i healthchecks-db psql -U healthchecks healthchecks < healthchecks-backup.sql
```

## Healthchecks vs Uptime Kuma

| Feature | Healthchecks | Uptime Kuma |
|---------|--------------|-------------|
| Focus | Cron/scheduled jobs | HTTP endpoints |
| How | Jobs ping Healthchecks | Uptime Kuma pings services |
| Use for | Backups, scripts, batch jobs | Websites, APIs, services |

Use **both** - Uptime Kuma for services, Healthchecks for scheduled jobs.
