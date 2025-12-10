# Kafka - Self-Hosted Production Setup

High-performance event streaming with KRaft mode (no Zookeeper).

## Quick Start

```bash
# 1. Setup environment
cp .env.example .env
nano .env  # Set KAFKA_ADVERTISED_HOST to your server IP

# 2. Start Kafka
docker compose up -d

# 3. Start with UI
docker compose --profile ui up -d

# 4. Start with monitoring
docker compose --profile all up -d
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Kafka (KRaft Mode)                       │
├─────────────────────────────────────────────────────────────┤
│  Port 9092  │  External clients (your apps)                 │
│  Port 9094  │  Internal Docker network                      │
│  Port 8080  │  Kafka UI (optional)                          │
│  Port 9308  │  Prometheus metrics (optional)                │
└─────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
kafka/
├── docker-compose.yml         # Self-hosted Kafka (production)
├── docker-compose.managed.yml # Kafka UI for managed Kafka (DO, AWS)
├── .env.example               # Configuration template
├── .env                       # Your config (gitignored)
├── .gitignore
└── README.md
```

## Profiles

| Command | What Starts |
|---------|-------------|
| `docker compose up -d` | Kafka only |
| `docker compose --profile ui up -d` | Kafka + UI |
| `docker compose --profile monitoring up -d` | Kafka + Exporter |
| `docker compose --profile all up -d` | Everything |

## Configuration

### Single Node (Default)

Current setup runs single Kafka node. Good for:
- Small to medium workloads
- Development/staging
- < 50k messages/sec

### Production Checklist

- [ ] Set `KAFKA_ADVERTISED_HOST` to server IP/domain
- [ ] Set `KAFKA_AUTO_CREATE_TOPICS=false`
- [ ] Enable SASL authentication
- [ ] Configure firewall (only allow trusted IPs on 9092)
- [ ] Set up monitoring with Prometheus
- [ ] Configure log retention based on disk space

## Connect from Application

```typescript
// Node.js (kafkajs)
import { Kafka } from 'kafkajs';

const kafka = new Kafka({
  clientId: 'my-app',
  brokers: ['YOUR_SERVER_IP:9092'],
  // With SASL auth:
  // sasl: {
  //   mechanism: 'plain',
  //   username: 'app',
  //   password: 'your_password'
  // }
});

// Producer
const producer = kafka.producer();
await producer.connect();
await producer.send({
  topic: 'events',
  messages: [{ value: JSON.stringify({ event: 'order.created' }) }]
});

// Consumer
const consumer = kafka.consumer({ groupId: 'my-group' });
await consumer.connect();
await consumer.subscribe({ topic: 'events' });
await consumer.run({
  eachMessage: async ({ message }) => {
    console.log(JSON.parse(message.value.toString()));
  }
});
```

```python
# Python (kafka-python)
from kafka import KafkaProducer, KafkaConsumer
import json

# Producer
producer = KafkaProducer(
    bootstrap_servers=['YOUR_SERVER_IP:9092'],
    value_serializer=lambda v: json.dumps(v).encode()
)
producer.send('events', {'event': 'order.created'})

# Consumer
consumer = KafkaConsumer(
    'events',
    bootstrap_servers=['YOUR_SERVER_IP:9092'],
    group_id='my-group',
    value_deserializer=lambda m: json.loads(m.decode())
)
for message in consumer:
    print(message.value)
```

## Topic Management

```bash
# Enter Kafka container
docker exec -it kafka bash

# List topics
kafka-topics.sh --bootstrap-server localhost:29092 --list

# Create topic
kafka-topics.sh --bootstrap-server localhost:29092 \
  --create --topic my-topic \
  --partitions 3 \
  --replication-factor 1

# Describe topic
kafka-topics.sh --bootstrap-server localhost:29092 \
  --describe --topic my-topic

# Delete topic
kafka-topics.sh --bootstrap-server localhost:29092 \
  --delete --topic my-topic

# Console producer (testing)
kafka-console-producer.sh --bootstrap-server localhost:29092 --topic my-topic

# Console consumer (testing)
kafka-console-consumer.sh --bootstrap-server localhost:29092 --topic my-topic --from-beginning
```

## Monitoring

### Prometheus Configuration

Add to your `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'kafka'
    static_configs:
      - targets: ['kafka-exporter:9308']
```

### Key Metrics

| Metric | Description |
|--------|-------------|
| `kafka_topic_partitions` | Partitions per topic |
| `kafka_consumergroup_lag` | Consumer lag (important!) |
| `kafka_brokers` | Number of brokers |
| `kafka_topic_partition_current_offset` | Current offset |

### Grafana Dashboard

Import dashboard ID: **7589** (Kafka Exporter Overview)

## Resource Recommendations

| Environment | CPU | Memory | Disk |
|-------------|-----|--------|------|
| Development | 1 | 2GB | 10GB |
| Staging | 2 | 4GB | 50GB |
| Production | 4+ | 8GB+ | 100GB+ SSD |

## Scaling to Multi-Node Cluster

For high availability, expand to 3+ nodes:

### Node 1 (kafka-1)
```env
KAFKA_NODE_ID=1
KAFKA_CFG_CONTROLLER_QUORUM_VOTERS=1@kafka-1:9093,2@kafka-2:9093,3@kafka-3:9093
KAFKA_DEFAULT_REPLICATION=3
KAFKA_MIN_ISR=2
```

### Node 2 (kafka-2)
```env
KAFKA_NODE_ID=2
KAFKA_CFG_CONTROLLER_QUORUM_VOTERS=1@kafka-1:9093,2@kafka-2:9093,3@kafka-3:9093
```

### Node 3 (kafka-3)
```env
KAFKA_NODE_ID=3
KAFKA_CFG_CONTROLLER_QUORUM_VOTERS=1@kafka-1:9093,2@kafka-2:9093,3@kafka-3:9093
```

## Backup & Recovery

### Export Topic Data

```bash
# Export messages from topic
kafka-console-consumer.sh --bootstrap-server localhost:29092 \
  --topic my-topic --from-beginning > backup.json
```

### Backup Volume

```bash
# Stop Kafka first
docker compose stop kafka

# Backup data
tar -czvf kafka-backup-$(date +%Y%m%d).tar.gz \
  /var/lib/docker/volumes/kafka_data

# Restart
docker compose start kafka
```

## Troubleshooting

### Check Logs

```bash
docker compose logs -f kafka
```

### Broker Not Starting

```bash
# Check if port is in use
lsof -i :9092

# Check disk space
df -h
```

### Consumer Lag

```bash
# Check consumer group lag
kafka-consumer-groups.sh --bootstrap-server localhost:29092 \
  --group my-group --describe
```

### High Memory Usage

Reduce heap size in `.env`:
```env
KAFKA_HEAP_OPTS=-Xmx1G -Xms1G
```

## Security Hardening

1. **Enable SASL** - Uncomment auth section in docker-compose.yml
2. **Firewall** - Only allow 9092 from trusted IPs
3. **TLS** - Enable for production (especially if traffic crosses networks)
4. **Network** - Keep Kafka in private network, expose only via VPN

## Managed Kafka (Alternative)

If self-hosting is too complex, use `docker-compose.managed.yml` to connect Kafka UI to managed services:

```bash
docker compose -f docker-compose.managed.yml up -d
```

Supports: DigitalOcean, AWS MSK, Confluent Cloud, Aiven
