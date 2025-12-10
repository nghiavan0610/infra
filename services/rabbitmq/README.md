# RabbitMQ - Production Setup

High-performance message broker with management UI, dead-letter handling, and Prometheus metrics.

## Quick Start

```bash
# 1. Create environment file
cp .env.example .env

# 2. Generate secure credentials
# Admin password
openssl rand -base64 24

# Erlang cookie (for clustering)
openssl rand -hex 32

# 3. Edit .env with your values
nano .env

# 4. Start RabbitMQ
docker compose up -d

# 5. Access Management UI
# http://localhost:15672
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                       RabbitMQ                              │
├─────────────────────────────────────────────────────────────┤
│  Port 5672   │  AMQP - Application connections              │
│  Port 15672  │  Management UI & HTTP API                    │
│  Port 9419   │  Prometheus metrics (exporter)               │
└─────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
rabbitmq/
├── docker-compose.yml    # Main compose file
├── .env.example          # Environment template
├── .env                  # Your configuration (gitignored)
├── .gitignore
├── README.md
└── config/
    ├── rabbitmq.conf     # Server configuration
    ├── definitions.json  # Users, vhosts, policies, exchanges
    └── enabled_plugins   # Enabled plugins list
```

## Default Configuration

### Virtual Hosts
| VHost | Purpose |
|-------|---------|
| `/` | Default (admin only) |
| `production` | Application workloads |

### Users
| User | Role | Access |
|------|------|--------|
| `admin` | Administrator | Full access to all vhosts |
| `app` | Application | Read/write to `production` vhost |
| `monitoring` | Monitoring | Read-only for metrics |

### Policies
| Policy | Pattern | Settings |
|--------|---------|----------|
| `default-ttl` | All queues | 24h TTL, 1M max messages, DLX |
| `dlx-policy` | `dlx.*` | 7 days TTL, 100K max |
| `ha-policy` | `ha.*` | Mirrored across all nodes |

### Exchanges
| Exchange | Type | Purpose |
|----------|------|---------|
| `app.events` | topic | Event broadcasting |
| `app.commands` | direct | Command routing |
| `dlx.exchange` | direct | Dead-letter handling |

## Usage Examples

### Connect from Application

```python
# Python (pika)
import pika

credentials = pika.PlainCredentials('app', 'your_password')
connection = pika.BlockingConnection(
    pika.ConnectionParameters(
        host='localhost',
        port=5672,
        virtual_host='production',
        credentials=credentials
    )
)
channel = connection.channel()

# Publish
channel.basic_publish(
    exchange='app.events',
    routing_key='order.created',
    body='{"order_id": "123"}'
)
```

```javascript
// Node.js (amqplib)
const amqp = require('amqplib');

const connection = await amqp.connect(
  'amqp://app:your_password@localhost:5672/production'
);
const channel = await connection.createChannel();

// Publish
channel.publish('app.events', 'order.created', Buffer.from('{"order_id": "123"}'));
```

### Management CLI

```bash
# Enter RabbitMQ container
docker exec -it rabbitmq bash

# List queues
rabbitmqctl list_queues -p production

# List connections
rabbitmqctl list_connections

# Check cluster status
rabbitmqctl cluster_status

# Add new user
rabbitmqctl add_user newuser password
rabbitmqctl set_permissions -p production newuser ".*" ".*" ".*"
```

## Monitoring

### Enable Prometheus Exporter

```bash
docker compose --profile monitoring up -d
```

### Prometheus Configuration

Add to your Prometheus `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'rabbitmq'
    static_configs:
      - targets: ['rabbitmq-exporter:9419']
```

### Key Metrics
- `rabbitmq_queue_messages` - Messages in queue
- `rabbitmq_queue_consumers` - Consumer count
- `rabbitmq_connections` - Active connections
- `rabbitmq_channels` - Open channels

### Grafana Dashboard
Import dashboard ID: **10991** (RabbitMQ Overview)

## Production Checklist

- [ ] Change all default passwords in `.env`
- [ ] Generate unique Erlang cookie
- [ ] Configure TLS for AMQP connections
- [ ] Set up monitoring with Prometheus
- [ ] Configure alerting for queue depth
- [ ] Set appropriate memory limits
- [ ] Enable Traefik for Management UI (optional)
- [ ] Set up backup for definitions

## Resource Recommendations

| Environment | CPU | Memory | Disk |
|-------------|-----|--------|------|
| Development | 0.5 | 512MB | 1GB |
| Staging | 1 | 1GB | 10GB |
| Production | 2+ | 2GB+ | 50GB+ |

## Backup & Restore

### Export Definitions

```bash
# Export current definitions
curl -u admin:password http://localhost:15672/api/definitions > backup-definitions.json
```

### Import Definitions

```bash
# Import definitions
curl -u admin:password -X POST -H "Content-Type: application/json" \
  -d @backup-definitions.json http://localhost:15672/api/definitions
```

## TLS Configuration

1. Place certificates in `config/certs/`:
   - `server.crt` - Server certificate
   - `server.key` - Private key
   - `ca.crt` - CA certificate

2. Uncomment TLS section in `rabbitmq.conf`

3. Update docker-compose.yml to mount certs:
   ```yaml
   volumes:
     - ./config/certs:/etc/rabbitmq/certs:ro
   ```

4. Update application connection strings to use `amqps://`

## Clustering (HA)

For high availability, deploy multiple RabbitMQ nodes:

1. Set same `RABBITMQ_ERLANG_COOKIE` on all nodes
2. Configure `cluster_formation` in rabbitmq.conf
3. Use quorum queues (default) for replicated queues

## Troubleshooting

### Check Logs

```bash
docker compose logs -f rabbitmq
```

### Memory Issues

```bash
# Check memory usage
docker exec rabbitmq rabbitmqctl status | grep memory

# Force garbage collection
docker exec rabbitmq rabbitmqctl eval 'garbage_collect().'
```

### Connection Issues

```bash
# List connections
docker exec rabbitmq rabbitmqctl list_connections

# Check listeners
docker exec rabbitmq rabbitmqctl listeners
```

### Queue Stuck

```bash
# Purge queue (DESTRUCTIVE)
docker exec rabbitmq rabbitmqctl purge_queue queue_name -p production

# Delete queue
docker exec rabbitmq rabbitmqctl delete_queue queue_name -p production
```
