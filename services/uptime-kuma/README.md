# Uptime Kuma - External Uptime Monitoring

Lightweight, self-hosted monitoring tool for checking service availability from outside.

## Quick Start

```bash
cp .env.example .env
docker compose up -d
```

Access at: http://localhost:3001

## First Setup

1. Open http://localhost:3001
2. Create admin account
3. Add monitors for your services

## Recommended Monitors

| Service | Type | URL/Host |
|---------|------|----------|
| Your App | HTTP(s) | https://yourapp.com |
| API Health | HTTP(s) | https://api.yourapp.com/health |
| Grafana | HTTP(s) | https://grafana.yourapp.com |
| PostgreSQL | TCP | your-server:5432 |
| Redis | TCP | your-server:6379 |

## Notifications

Uptime Kuma supports:
- Slack, Discord, Telegram
- Email (SMTP)
- Webhook
- PagerDuty, Opsgenie
- 90+ notification services

## Why Use This + Observability?

| Tool | Purpose |
|------|---------|
| **Observability (Prometheus)** | Internal metrics, detailed insights |
| **Uptime Kuma** | External checks, "is it actually reachable?" |

Both are needed - Prometheus won't alert if your whole server is down.

## Best Practice

Run Uptime Kuma on a **different server** than your main infrastructure for true external monitoring.
