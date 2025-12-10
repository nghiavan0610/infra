# NATS Server

High-performance messaging server with JetStream persistence for microservices communication.

## Features

- High-performance pub/sub messaging
- JetStream for persistent streams and queues
- Multi-account authentication with per-service permissions
- Request/Reply pattern support
- Prometheus metrics via Surveyor
- Production-optimized configuration

## Quick Start

```bash
# Configure
cp .env.example .env
nano .env  # Update credentials

# Start NATS
docker compose up -d

# Or use the CLI
./scripts/nats-cli.sh start

# Check status
./scripts/nats-cli.sh status
```

## Endpoints

| Service | Port | URL | Description |
|---------|------|-----|-------------|
| Client | 4222 | `nats://localhost:4222` | NATS client connections |
| Monitoring | 8222 | `http://localhost:8222` | HTTP monitoring API |
| Surveyor | 7777 | `http://localhost:7777` | Prometheus metrics |

## CLI Commands

```bash
# Start/Stop
./scripts/nats-cli.sh start      # Start NATS
./scripts/nats-cli.sh stop       # Stop NATS
./scripts/nats-cli.sh restart    # Restart NATS

# Monitoring
./scripts/nats-cli.sh status     # Show status
./scripts/nats-cli.sh health     # Health check
./scripts/nats-cli.sh logs       # Follow logs
./scripts/nats-cli.sh logs-tail  # Last 50 lines
./scripts/nats-cli.sh monitor    # Start with Surveyor

# Maintenance
./scripts/nats-cli.sh backup     # Backup JetStream data
./scripts/nats-cli.sh test-auth  # Test authentication
./scripts/nats-cli.sh reset-auth # Regenerate auth config
./scripts/nats-cli.sh clean      # Remove all data
```

## Authentication

NATS uses multi-account authentication with per-service credentials.

### Configuration Files

```
config/
├── nats.conf           # Main NATS configuration
├── auth.conf           # Generated authentication (from template)
└── auth.conf.template  # Authentication template with env vars
```

### Adding a New Service

1. Add credentials to `.env`:
```bash
MY_SERVICE_USER=my-service
MY_SERVICE_PASS=$(openssl rand -base64 24)
```

2. Add to `config/auth.conf.template`:
```conf
{
    user: "${MY_SERVICE_USER}"
    password: "${MY_SERVICE_PASS}"
    permissions = {
        publish = ["my-service.*", "events.my-service.*"]
        subscribe = ["other-service.*", "_INBOX.*"]
    }
}
```

3. Regenerate auth and restart:
```bash
./scripts/nats-cli.sh reset-auth
```

### Service Permissions Example

| Service | Publish | Subscribe |
|---------|---------|-----------|
| teacher-service | `teacher.*`, `events.teacher.*` | `user.query.*`, `events.user.*`, `_INBOX.*` |
| user-service | `user.*`, `events.user.*` | `teacher.query.*`, `events.teacher.*`, `_INBOX.*` |
| notification-service | `notifications.*` | `notifications.*`, `events.*` |

### Connecting from Applications

**Node.js:**
```javascript
import { connect } from 'nats';

const nc = await connect({
  servers: 'nats://localhost:4222',
  user: 'my-service',
  pass: 'my-password'
});

// Publish
nc.publish('events.user.created', JSON.stringify({ id: 1 }));

// Subscribe
const sub = nc.subscribe('events.*');
for await (const msg of sub) {
  console.log(msg.string());
}
```

**Python:**
```python
import nats

nc = await nats.connect(
    servers=["nats://localhost:4222"],
    user="my-service",
    password="my-password"
)

# Publish
await nc.publish("events.user.created", b'{"id": 1}')

# Subscribe
async def handler(msg):
    print(msg.data.decode())

await nc.subscribe("events.*", cb=handler)
```

## JetStream

JetStream provides persistent messaging with streams and consumers.

### Configuration

In `nats.conf`:
```conf
jetstream {
    store_dir: "/data/jetstream"
    max_memory_store: 1GB
    max_file_store: 50GB
    sync_interval: "1s"
}
```

### Creating Streams

```bash
# Using nats-box
docker compose --profile tools up -d
docker exec -it nats-box sh

# Create a stream
nats stream add EVENTS \
  --subjects "events.*" \
  --storage file \
  --replicas 1 \
  --retention limits \
  --max-msgs 1000000
```

## Monitoring

### Built-in Endpoints

| Endpoint | Description |
|----------|-------------|
| `/healthz` | Health check |
| `/varz` | Server variables |
| `/connz` | Connection info |
| `/subsz` | Subscriptions |
| `/jsz` | JetStream info |

```bash
# Health check
curl http://localhost:8222/healthz

# Server info
curl http://localhost:8222/varz

# Connections
curl http://localhost:8222/connz

# JetStream status
curl http://localhost:8222/jsz
```

### Prometheus Metrics

Start with Surveyor:
```bash
./scripts/nats-cli.sh monitor
# Metrics at http://localhost:7777/metrics
```

### Grafana Dashboard

Import dashboard ID: **2279** (NATS Server)

## Configuration

### Key Settings (nats.conf)

| Setting | Value | Description |
|---------|-------|-------------|
| `max_connections` | 10000 | Max client connections |
| `max_payload` | 1MB | Max message size |
| `ping_interval` | 20s | Client ping interval |
| `sync_interval` | 1s | JetStream disk sync |

### Resource Limits (.env)

```bash
NATS_CPU_LIMIT=2
NATS_MEMORY_LIMIT=2G
NATS_JS_MAX_MEMORY=1GB
NATS_JS_MAX_FILE=50GB
```

## Security

### Port Bindings

All ports bound to localhost only:
- `127.0.0.1:4222` - Client connections
- `127.0.0.1:8222` - HTTP monitoring
- `127.0.0.1:7777` - Surveyor metrics

### TLS (Optional)

Uncomment in `nats.conf`:
```conf
tls {
    cert_file: "/etc/nats/certs/server.crt"
    key_file: "/etc/nats/certs/server.key"
    verify: true
    min_version: "1.2"
}
```

## Troubleshooting

### NATS won't start

```bash
# Check logs
./scripts/nats-cli.sh logs

# Validate config
docker run --rm -v $(pwd)/config:/etc/nats nats:2.10-alpine \
  nats-server --config /etc/nats/nats.conf --dry-run
```

### Authentication failing

```bash
# Test auth setup
./scripts/nats-cli.sh test-auth

# Check auth.conf
docker exec nats cat /etc/nats/auth.conf
```

### JetStream issues

```bash
# Check status
curl http://localhost:8222/jsz

# Check disk space
df -h
```

## File Structure

```
nats/
├── config/
│   ├── nats.conf           # Main configuration
│   ├── auth.conf           # Generated auth (gitignored)
│   └── auth.conf.template  # Auth template
├── scripts/
│   ├── nats-cli.sh         # Management CLI
│   └── start-nats.sh       # Initial setup script
├── docker-compose.yml
├── .env.example
├── .env                    # Credentials (gitignored)
└── README.md
```
