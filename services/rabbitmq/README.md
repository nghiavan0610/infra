# RabbitMQ

High-performance message broker with management UI, dead-letter handling, and Prometheus metrics.

## Features

- AMQP 0-9-1 message broker
- Management UI with HTTP API
- **Multi-vhost architecture** (tenant isolation)
- Per-user permissions (configure/write/read)
- Easy vhost management via CLI script
- Built-in Prometheus metrics
- Dead-letter exchange support

## Quick Start

```bash
# 1. Setup (from infra root)
cd /opt/infra
./setup.sh  # Generates admin credentials

# 2. Create your first vhost
cd services/rabbitmq
./manage.sh add-vhost myapp

# 3. Use the connection URL provided
# amqp://myapp-admin:xxxxx@localhost:5672/myapp
```

## Endpoints

| Service | Port | URL | Description |
|---------|------|-----|-------------|
| AMQP | 5672 | `amqp://localhost:5672` | Application connections |
| Management | 15672 | `http://localhost:15672` | Web UI & HTTP API |
| Metrics | 15692 | `http://localhost:15692/metrics` | Prometheus metrics |

---

## Vhost Management

Use `manage.sh` to manage vhosts and users. All credentials are auto-generated and stored securely.

### Create a Vhost

```bash
./manage.sh add-vhost myapp
```

Output:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Connection Details
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Vhost:    myapp
  User:     myapp-admin
  Password: xK9mN2pQ7rT4wY6z...
  URL:      amqp://myapp-admin:****@localhost:5672/myapp

  Default exchanges created:
    - events  (topic)   - for event publishing
    - commands (direct) - for RPC/commands
    - dlx (direct)      - dead letter exchange

  Credentials saved to: .credentials/myapp.env
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Add User with Permissions

```bash
# Add a worker with limited permissions
./manage.sh add-user myapp worker \
  --configure "^worker\." \
  --write "^jobs\." \
  --read "^results\."

# Add a monitoring user (read-only)
./manage.sh add-user myapp monitor -c "" -w "" -r ".*" -t "monitoring"
```

### List All Vhosts and Users

```bash
./manage.sh list
```

Output:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  RabbitMQ Vhosts and Users
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  myapp
    ├─ myapp-admin (full access)
    ├─ worker (c:^worker\. w:^jobs\. r:^results\.)
    ├─ monitor (c: w: r:.*)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Show Connection Details

```bash
# Show vhost admin credentials
./manage.sh show myapp

# Show specific user credentials
./manage.sh show myapp worker
```

### Remove User or Vhost

```bash
# Remove a user
./manage.sh remove-user myapp worker

# Remove entire vhost (and all queues/exchanges)
./manage.sh remove-vhost myapp
```

### All Commands

| Command | Description |
|---------|-------------|
| `add-vhost <name>` | Create vhost with admin user and default exchanges |
| `add-user <vhost> <user> [options]` | Add user with permissions |
| `list` | List all vhosts and users |
| `show <vhost> [user]` | Show connection details |
| `remove-user <vhost> <user>` | Remove user |
| `remove-vhost <vhost>` | Remove vhost and all data |
| `test <vhost> [user]` | Test connection |

---

## Understanding Vhosts, Users, and Permissions

### Vhosts (Virtual Hosts)

Vhosts provide **complete isolation** - separate queues, exchanges, bindings, and permissions.

```
┌─────────────────────────────────────────────────────────┐
│                     RabbitMQ Server                      │
│  ┌───────────────────┐    ┌───────────────────┐        │
│  │  Vhost: /myapp    │    │  Vhost: /shop     │        │
│  │  - orders queue   │    │  - cart queue     │        │
│  │  - events exch    │    │  - events exch    │        │
│  └───────────────────┘    └───────────────────┘        │
│          ↑                         ↑                    │
│          └─── Completely isolated ────┘                 │
└─────────────────────────────────────────────────────────┘
```

### Users and Permissions

Users have three permission types (regex patterns):

| Permission | Controls |
|------------|----------|
| **Configure** | Create/delete queues, exchanges, bindings |
| **Write** | Publish to exchanges, bind queues |
| **Read** | Consume from queues, get bindings |

```bash
# Full access (default for admin)
--configure ".*" --write ".*" --read ".*"

# Worker: can only write to jobs.*, read from results.*
--configure "" --write "^jobs\." --read "^results\."

# Read-only monitoring
--configure "" --write "" --read ".*"
```

### Permission Patterns (Regex)

| Pattern | Matches |
|---------|---------|
| `.*` | Everything |
| `""` (empty) | Nothing |
| `^orders$` | Exact "orders" |
| `^jobs\.` | Starts with "jobs." |
| `^(q1\|q2)$` | Either "q1" or "q2" |

---

## Connecting from Applications

### Node.js (amqplib)

```javascript
const amqp = require('amqplib');

const connection = await amqp.connect(process.env.RABBITMQ_URL);
// amqp://worker:xxxxx@localhost:5672/myapp

const channel = await connection.createChannel();

// Publish to topic exchange
channel.publish('events', 'order.created', Buffer.from(JSON.stringify({
  orderId: '123',
  total: 99.99
})));

// Consume from queue
channel.consume('orders', (msg) => {
  console.log('Order:', msg.content.toString());
  channel.ack(msg);
});
```

### Python (pika)

```python
import pika
import os

url = os.environ['RABBITMQ_URL']
params = pika.URLParameters(url)
connection = pika.BlockingConnection(params)
channel = connection.channel()

# Publish
channel.basic_publish(
    exchange='events',
    routing_key='order.created',
    body='{"orderId": "123"}'
)

# Consume
def callback(ch, method, properties, body):
    print(f"Order: {body}")
    ch.basic_ack(delivery_tag=method.delivery_tag)

channel.basic_consume(queue='orders', on_message_callback=callback)
channel.start_consuming()
```

### Go (amqp091-go)

```go
import amqp "github.com/rabbitmq/amqp091-go"

conn, _ := amqp.Dial(os.Getenv("RABBITMQ_URL"))
ch, _ := conn.Channel()

// Publish
ch.Publish("events", "order.created", false, false, amqp.Publishing{
    Body: []byte(`{"orderId": "123"}`),
})

// Consume
msgs, _ := ch.Consume("orders", "", false, false, false, false, nil)
for msg := range msgs {
    fmt.Println("Order:", string(msg.Body))
    msg.Ack(false)
}
```

### Environment Variables

Load credentials from generated `.credentials/` files:

```bash
source /opt/infra/services/rabbitmq/.credentials/myapp_worker.env
echo $RABBITMQ_URL  # amqp://worker:xxxxx@localhost:5672/myapp
```

---

## Default Exchanges

Each vhost is created with these exchanges:

| Exchange | Type | Purpose |
|----------|------|---------|
| `events` | topic | Event broadcasting (`order.created`, `user.*`) |
| `commands` | direct | RPC/command routing |
| `dlx` | direct | Dead-letter exchange |

### Exchange Types

```
Topic Exchange (events):
  routing_key: "order.created" → matches "order.*", "#"
  routing_key: "user.signup"   → matches "user.*", "*.signup"

Direct Exchange (commands):
  routing_key: "process-order" → exact match only
```

---

## Dead Letter Handling

Failed messages are automatically routed to the DLX:

```
┌──────────────┐    reject/expire    ┌─────────────────┐
│  jobs.queue  │ ─────────────────→  │  dlx.queue      │
│              │                     │  (inspect later)│
└──────────────┘                     └─────────────────┘
```

Configure a queue with DLX:

```javascript
channel.assertQueue('jobs', {
  deadLetterExchange: 'dlx',
  deadLetterRoutingKey: 'dlx',
  messageTtl: 86400000  // 24h
});
```

---

## Monitoring

### Health Check

```bash
curl -u admin:password http://localhost:15672/api/health/checks/alarms
```

### Queue Status

```bash
curl -u admin:password http://localhost:15672/api/queues/myapp
```

### Prometheus Metrics

Built-in metrics at `http://localhost:15692/metrics`:

```
# Key metrics
rabbitmq_queue_messages          # Messages in queue
rabbitmq_queue_consumers         # Consumer count
rabbitmq_connections_opened_total # Connection count
rabbitmq_channel_messages_published_total
```

### Grafana Dashboard

Import dashboard ID: **10991** (RabbitMQ Overview)

---

## File Structure

```
rabbitmq/
├── manage.sh               # Vhost management CLI
├── config/
│   ├── rabbitmq.conf       # Server configuration
│   ├── definitions.json    # Base definitions
│   └── enabled_plugins     # Enabled plugins
├── .credentials/           # Generated credentials (gitignored)
├── docker-compose.yml
├── .env.example
└── README.md
```

---

## Troubleshooting

### RabbitMQ won't start

```bash
# Check logs
docker logs rabbitmq --tail 50

# Check if port is in use
netstat -tlnp | grep 5672
```

### Authentication failed

```bash
# Verify credentials
./manage.sh test myapp

# Check user exists
curl -u admin:password http://localhost:15672/api/users
```

### Queue not receiving messages

```bash
# Check queue bindings
curl -u admin:password http://localhost:15672/api/queues/myapp/orders/bindings

# Check exchange exists
curl -u admin:password http://localhost:15672/api/exchanges/myapp
```

### Memory alarm

```bash
# Check memory
docker exec rabbitmq rabbitmqctl status | grep memory

# See what's using memory
curl -u admin:password http://localhost:15672/api/queues | jq '.[].memory'
```

### Purge stuck queue

```bash
# DESTRUCTIVE - removes all messages
docker exec rabbitmq rabbitmqctl purge_queue orders -p myapp
```

---

## Security Best Practices

1. **Use unique credentials** - Each vhost/user gets auto-generated passwords
2. **Minimal permissions** - Only grant configure/write/read that's needed
3. **Localhost binding** - Ports are bound to localhost by default
4. **TLS in production** - Uncomment TLS config in `rabbitmq.conf`
5. **Backup credentials** - The `.credentials/` directory contains all passwords

---

## Configuration Reference

### Environment Variables (.env)

| Variable | Default | Description |
|----------|---------|-------------|
| `RABBITMQ_ADMIN_USER` | `admin` | Admin username |
| `RABBITMQ_ADMIN_PASS` | (generated) | Admin password |
| `RABBITMQ_ERLANG_COOKIE` | (generated) | Cluster cookie |
| `RABBITMQ_PORT` | `5672` | AMQP port |
| `RABBITMQ_MANAGEMENT_PORT` | `15672` | Management UI port |
| `RABBITMQ_CPU_LIMIT` | `2` | CPU cores limit |
| `RABBITMQ_MEMORY_LIMIT` | `1G` | Container memory limit |

### Server Settings (rabbitmq.conf)

| Setting | Value | Description |
|---------|-------|-------------|
| `vm_memory_high_watermark` | 0.7 | Memory threshold (70% of RAM) |
| `disk_free_limit` | 2GB | Minimum free disk space |
| `channel_max` | 128 | Max channels per connection |
| `heartbeat` | 60 | Heartbeat interval (seconds) |
| `default_queue_type` | quorum | Default queue type (replicated) |
