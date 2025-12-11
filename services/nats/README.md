# NATS Server

High-performance messaging server with JetStream persistence for microservices communication.

## Features

- High-performance pub/sub messaging
- JetStream for persistent streams and queues
- **Multi-tenant architecture** with isolated accounts
- Per-user permissions (publish/subscribe restrictions)
- Easy tenant management via CLI script
- Prometheus metrics via Surveyor

## Quick Start

```bash
# 1. Setup (from infra root)
cd /opt/infra
./setup.sh  # Generates NATS_SYS_PASSWORD

# 2. Create your first tenant
cd services/nats
./manage.sh add-tenant myapp

# 3. Use the connection URL provided
# nats://myapp:xxxxx@localhost:4222
```

## Endpoints

| Service | Port | URL | Description |
|---------|------|-----|-------------|
| Client | 4222 | `nats://localhost:4222` | NATS client connections |
| Monitoring | 8222 | `http://localhost:8222` | HTTP monitoring API |
| Surveyor | 7777 | `http://localhost:7777` | Prometheus metrics (optional) |

---

## Tenant Management

Use `manage.sh` to manage tenants and users. All credentials are auto-generated and stored securely.

### Create a Tenant

```bash
./manage.sh add-tenant myapp
```

Output:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Connection Details
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  User:     myapp
  Password: xK9mN2pQ7rT4wY6z...
  URL:      nats://myapp:xK9mN2pQ7rT4wY6z...@localhost:4222

  Credentials saved to: .credentials/myapp.env
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Add User with Permissions

```bash
# Add a service user with restricted publish/subscribe permissions
./manage.sh add-user myapp order-service \
  --publish "orders.*,events.order.*" \
  --subscribe "payments.*,inventory.*"
```

### List All Tenants and Users

```bash
./manage.sh list
```

Output:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  NATS Tenants and Users
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  MYAPP
    ├─ myapp (full access)
    ├─ order-service (publish: orders.*, subscribe: payments.*)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Show Connection Details

```bash
# Show tenant admin credentials
./manage.sh show myapp

# Show specific user credentials
./manage.sh show myapp order-service
```

### Remove User or Tenant

```bash
# Remove a user
./manage.sh remove-user myapp order-service

# Remove entire tenant (and all users)
./manage.sh remove-tenant myapp
```

### All Commands

| Command | Description |
|---------|-------------|
| `add-tenant <name> [memory] [storage]` | Create new tenant (default: 64MB, 5GB) |
| `add-user <tenant> <user> [-p subjects] [-s subjects]` | Add user with permissions |
| `list` | List all tenants and users |
| `show <tenant> [user]` | Show connection details |
| `remove-user <tenant> <user>` | Remove user from tenant |
| `remove-tenant <tenant>` | Remove tenant and all users |
| `test <tenant> [user]` | Test connection |
| `reload` | Rebuild config and restart NATS |

---

## Understanding Tenants, Users, and Permissions

### Tenants (Accounts)

Tenants are **isolated namespaces**. Messages in one tenant cannot be seen by another.

```
┌─────────────────────────────────────────────────────────┐
│                      NATS Server                        │
│  ┌───────────────────┐    ┌───────────────────┐        │
│  │  Tenant: SHOP     │    │  Tenant: BLOG     │        │
│  │  - orders.*       │    │  - posts.*        │        │
│  │  - payments.*     │    │  - comments.*     │        │
│  └───────────────────┘    └───────────────────┘        │
│          ↑                         ↑                    │
│          └─── Cannot see each other's messages ───┘    │
└─────────────────────────────────────────────────────────┘
```

### Users

Users belong to a tenant and have credentials to connect:
- **Admin user** (same name as tenant): Full access within tenant
- **Service users**: Can have restricted permissions

### Permissions

Control what subjects a user can publish to or subscribe from:

```bash
# order-service can:
#   - PUBLISH to: orders.*, events.order.*
#   - SUBSCRIBE to: payments.*, inventory.*

./manage.sh add-user myapp order-service \
  -p "orders.*,events.order.*" \
  -s "payments.*,inventory.*"
```

### Subject Patterns

| Pattern | Matches | Example |
|---------|---------|---------|
| `orders.created` | Exact match | `orders.created` |
| `orders.*` | Single token wildcard | `orders.created`, `orders.shipped` |
| `orders.>` | Multi-token wildcard | `orders.created`, `orders.item.added` |

---

## Connecting from Applications

### Node.js

```javascript
import { connect } from 'nats';

const nc = await connect({
  servers: 'nats://localhost:4222',
  user: 'order-service',
  pass: process.env.NATS_PASSWORD
});

// Publish
nc.publish('orders.created', JSON.stringify({ id: 1, total: 99.99 }));

// Subscribe
const sub = nc.subscribe('payments.*');
for await (const msg of sub) {
  console.log('Payment received:', msg.string());
}

// Request/Reply
const response = await nc.request('inventory.check', JSON.stringify({ sku: 'ABC123' }));
console.log('Stock:', response.string());
```

### Go

```go
import "github.com/nats-io/nats.go"

nc, _ := nats.Connect("nats://localhost:4222",
    nats.UserInfo("order-service", os.Getenv("NATS_PASSWORD")))

// Publish
nc.Publish("orders.created", []byte(`{"id": 1}`))

// Subscribe
nc.Subscribe("payments.*", func(m *nats.Msg) {
    fmt.Printf("Payment: %s\n", string(m.Data))
})
```

### Python

```python
import nats
import os

nc = await nats.connect(
    servers=["nats://localhost:4222"],
    user="order-service",
    password=os.environ["NATS_PASSWORD"]
)

# Publish
await nc.publish("orders.created", b'{"id": 1}')

# Subscribe
async def handler(msg):
    print(f"Payment: {msg.data.decode()}")

await nc.subscribe("payments.*", cb=handler)
```

### Environment Variables

Load credentials from the generated `.credentials/` files:

```bash
# Source credentials
source /opt/infra/services/nats/.credentials/myapp_order-service.env

# Use in your app
echo $NATS_URL  # nats://order-service:xxxxx@localhost:4222
```

---

## JetStream (Persistent Messaging)

JetStream adds persistence, exactly-once delivery, and replay capabilities.

### Configuration

Default limits in `nats.conf`:
```
jetstream {
    max_memory_store: 256MB   # In-memory streams
    max_file_store: 10GB      # File-based streams
}
```

Per-tenant limits (set when creating tenant):
```bash
./manage.sh add-tenant myapp 128MB 10GB
#                            ↑      ↑
#                         memory  storage
```

### Creating Streams

```bash
# Start nats-box for CLI access
docker compose --profile tools up -d
docker exec -it nats-box sh

# Create a stream
nats stream add ORDERS \
  --subjects "orders.*" \
  --storage file \
  --retention limits \
  --max-msgs 100000 \
  --max-age 7d
```

---

## Monitoring

### Health Check

```bash
curl http://localhost:8222/healthz
```

### Server Info

```bash
# General info
curl http://localhost:8222/varz

# Connections
curl http://localhost:8222/connz

# JetStream status
curl http://localhost:8222/jsz
```

### Prometheus Metrics

```bash
# Start with Surveyor
docker compose --profile monitoring up -d

# Metrics available at
curl http://localhost:7777/metrics
```

### Grafana Dashboard

Import dashboard ID: **2279** (NATS Server)

---

## File Structure

```
nats/
├── manage.sh               # Tenant management CLI
├── config/
│   ├── nats.conf           # Server configuration
│   ├── auth.conf           # Auto-generated auth config
│   └── tenants/            # Tenant config files
│       └── .gitkeep
├── .credentials/           # Generated credentials (gitignored)
├── docker-compose.yml
├── .env.example
└── README.md
```

---

## Troubleshooting

### NATS won't start

```bash
# Check logs
docker logs nats --tail 50

# Validate config
docker run --rm -v $(pwd)/config:/etc/nats nats:2.10-alpine \
  nats-server --config /etc/nats/nats.conf -t
```

### Authentication failing

```bash
# Check current auth config
cat config/auth.conf

# Rebuild and reload
./manage.sh reload

# Test connection
./manage.sh test myapp
```

### JetStream memory error

```
Error: insufficient memory resources available
```

Solution: Reduce per-tenant memory limits or increase global limit in `nats.conf`:
```bash
# Check current tenant limits
./manage.sh list

# Create tenant with smaller limits
./manage.sh add-tenant smallapp 32MB 1GB
```

### Connection refused

```bash
# Check if NATS is running
docker ps | grep nats

# Check port binding
netstat -tlnp | grep 4222

# Restart
docker compose restart nats
```

---

## Security Best Practices

1. **Use unique passwords** - Each tenant/user gets auto-generated credentials
2. **Restrict permissions** - Only grant publish/subscribe access that's needed
3. **Localhost binding** - Ports are bound to 127.0.0.1 by default
4. **TLS in production** - Uncomment TLS config in `nats.conf` for encrypted connections
5. **Backup credentials** - The `.credentials/` directory contains all passwords

---

## Configuration Reference

### Environment Variables (.env)

| Variable | Default | Description |
|----------|---------|-------------|
| `NATS_SERVER_NAME` | `nats-1` | Server identifier |
| `NATS_PORT` | `4222` | Client port |
| `NATS_HTTP_PORT` | `8222` | Monitoring port |
| `NATS_SYS_PASSWORD` | (generated) | System account password |
| `NATS_CPU_LIMIT` | `2` | CPU cores limit |
| `NATS_MEMORY_LIMIT` | `512M` | Container memory limit |

### Server Settings (nats.conf)

| Setting | Value | Description |
|---------|-------|-------------|
| `max_connections` | 10000 | Max concurrent clients |
| `max_payload` | 1MB | Max message size |
| `max_memory_store` | 256MB | JetStream memory limit |
| `max_file_store` | 10GB | JetStream disk limit |
