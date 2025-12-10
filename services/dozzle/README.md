# Dozzle

Real-time Docker log viewer in your browser.

## Quick Start

```bash
# Start Dozzle
docker compose up -d

# Access UI
open http://localhost:9999
```

## Features

- **Real-time logs** - Stream logs as they happen
- **All containers** - View any container's logs
- **Search & filter** - Find specific log entries
- **Multi-container** - View multiple containers side by side
- **Download logs** - Export logs to file
- **Dark/Light mode** - UI theme options
- **No database** - Lightweight, stateless

## Configuration

Edit `.env`:

```bash
# Enable authentication
DOZZLE_USERNAME=admin
DOZZLE_PASSWORD=secretpassword

# Load more initial log lines
DOZZLE_TAILSIZE=1000
```

## Using Dozzle

### View Container Logs

1. Open http://localhost:9999
2. Click on any container in the sidebar
3. Logs stream in real-time

### Search Logs

- Use the search box to filter log entries
- Supports regex patterns

### Multi-Container View

1. Click the split icon
2. Select multiple containers
3. View logs side by side

### Download Logs

1. Click the download icon
2. Choose time range
3. Download as text file

## Security

### Enable Authentication

```bash
DOZZLE_USERNAME=admin
DOZZLE_PASSWORD=your-secure-password
```

### Expose via Traefik with SSL

Edit docker-compose.yml labels:
```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.dozzle.rule=Host(`logs.example.com`)"
  - "traefik.http.routers.dozzle.entrypoints=websecure"
  - "traefik.http.routers.dozzle.tls.certresolver=letsencrypt"
```

### Use with Authentik

For SSO authentication, configure Traefik to use Authentik middleware.

## Integration with Observability Stack

Dozzle complements Loki/Grafana:

| Tool | Use Case |
|------|----------|
| **Dozzle** | Quick debugging, real-time viewing |
| **Loki/Grafana** | Long-term storage, queries, alerts |

Use Dozzle for quick checks, Loki for historical analysis.

## Tips

### Keyboard Shortcuts

- `Ctrl/Cmd + K` - Quick search
- `Ctrl/Cmd + F` - Filter logs
- `Esc` - Close panels

### Container Labels

Hide containers from Dozzle:
```yaml
services:
  internal-service:
    labels:
      - "dev.dozzle.hide=true"
```

### Log Retention

Dozzle doesn't store logs - it reads from Docker's log driver.
Configure Docker's log rotation:

```json
// /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

## Troubleshooting

### Can't see container logs

- Check Docker socket is mounted
- Verify container is using json-file log driver

### Performance with many containers

- Dozzle handles 100+ containers well
- Avoid streaming all containers simultaneously
