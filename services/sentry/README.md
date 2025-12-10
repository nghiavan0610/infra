# Sentry - Error Tracking

Self-hosted error tracking and performance monitoring for your applications.

## Prerequisites

- PostgreSQL running (shared database)
- Redis running (shared cache)

## Quick Start

```bash
# 1. Configure
cp .env.example .env
nano .env  # Set SENTRY_SECRET_KEY and database passwords

# 2. Create Sentry database in PostgreSQL
docker exec -it postgres psql -U postgres -c "CREATE DATABASE sentry;"

# 3. Start services
docker compose up -d

# 4. Initialize database (first time only)
docker compose exec sentry sentry upgrade

# 5. Create admin user
docker compose exec sentry sentry createuser
```

## Access

- URL: http://localhost:9000
- Create account on first visit

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `SENTRY_SECRET_KEY` | - | Secret key (required) |
| `SENTRY_PORT` | 9000 | Web UI port |
| `POSTGRES_PASSWORD` | - | PostgreSQL password |
| `REDIS_PASSWORD` | - | Redis password |
| `SENTRY_DOMAIN` | - | Domain for Traefik |

## Integrating with Your App

### JavaScript/Node.js

```javascript
import * as Sentry from "@sentry/node";

Sentry.init({
  dsn: "http://your-key@localhost:9000/1",
  environment: process.env.NODE_ENV,
  tracesSampleRate: 1.0,
});
```

### Python

```python
import sentry_sdk

sentry_sdk.init(
    dsn="http://your-key@localhost:9000/1",
    environment="production",
    traces_sample_rate=1.0,
)
```

### Go

```go
import "github.com/getsentry/sentry-go"

sentry.Init(sentry.ClientOptions{
    Dsn: "http://your-key@localhost:9000/1",
    Environment: "production",
})
```

## Architecture

```
┌─────────────────┐     ┌─────────────────┐
│   Your Apps     │────▶│     Sentry      │
│  (send errors)  │     │   (port 9000)   │
└─────────────────┘     └────────┬────────┘
                                 │
                    ┌────────────┼────────────┐
                    ▼            ▼            ▼
              ┌──────────┐ ┌──────────┐ ┌──────────┐
              │ PostgreSQL│ │  Redis   │ │  Worker  │
              │ (storage) │ │ (cache)  │ │ (process)│
              └──────────┘ └──────────┘ └──────────┘
```

## Production Notes

1. **Use external PostgreSQL** - Don't run separate DB for Sentry
2. **Configure email** - For alert notifications
3. **Set up cleanup** - Sentry can use a lot of storage
4. **Rate limiting** - Configure in Sentry admin

## Cleanup Old Data

```bash
# Clean events older than 30 days
docker compose exec sentry sentry cleanup --days 30
```
