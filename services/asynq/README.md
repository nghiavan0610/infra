# Asynqmon - Task Queue Dashboard

Web UI for monitoring [Asynq](https://github.com/hibiken/asynq) distributed task queues.

## What is Asynq?

Asynq is a **Go library** for distributed task processing. It uses Redis as a backend. This setup only provides the **monitoring dashboard** - your application code handles task processing.

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Your App       │     │  redis-queue    │     │   asynqmon      │
│  (Go/Node)      │────▶│  (port 6380)    │◀────│  Dashboard      │
│  Enqueue tasks  │     │  Stores tasks   │     │  port 8080      │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │
        ▼
┌─────────────────┐
│  Worker         │
│  Process tasks  │
└─────────────────┘
```

## Quick Start

```bash
# Configure
cp .env.example .env
nano .env  # Set REDIS_PASSWORD

# Start dashboard
docker compose up -d

# Open dashboard
open http://localhost:8080
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `ASYNQMON_PORT` | 8080 | Dashboard port |
| `REDIS_ADDR` | host.docker.internal:6380 | Redis address |
| `REDIS_DB` | 0 | Redis database number |
| `REDIS_PASSWORD` | - | Redis password |

## Prometheus Metrics Integration

Asynqmon is for viewing tasks. For metrics/alerting, expose metrics from your app.

### Go (Asynq) - Expose Metrics

```go
package main

import (
    "net/http"

    "github.com/hibiken/asynq"
    "github.com/hibiken/asynq/x/metrics"
    "github.com/prometheus/client_golang/prometheus"
    "github.com/prometheus/client_golang/prometheus/promhttp"
)

func main() {
    // Redis connection
    redisOpt := asynq.RedisClientOpt{
        Addr:     "localhost:6380",
        Password: "your_password",
    }

    // Create inspector for metrics
    inspector := asynq.NewInspector(redisOpt)

    // Register Asynq metrics collector
    prometheus.MustRegister(
        metrics.NewQueueMetricsCollector(inspector),
    )

    // Expose /metrics endpoint
    http.Handle("/metrics", promhttp.Handler())
    go http.ListenAndServe(":9090", nil)

    // Start worker
    srv := asynq.NewServer(redisOpt, asynq.Config{
        Concurrency: 10,
        Queues: map[string]int{
            "critical": 6,
            "default":  3,
            "low":      1,
        },
    })

    mux := asynq.NewServeMux()
    mux.HandleFunc("email:send", handleEmailTask)
    srv.Run(mux)
}
```

### Node.js (BullMQ) - Expose Metrics

```typescript
import { Queue, Worker, QueueEvents } from 'bullmq';
import { Registry, Gauge, Counter } from 'prom-client';
import express from 'express';

const register = new Registry();
const connection = { host: 'localhost', port: 6380 };

// Create metrics
const queueSize = new Gauge({
  name: 'bull_queue_waiting',
  help: 'Number of waiting jobs',
  labelNames: ['queue'],
  registers: [register],
});

const failedJobs = new Gauge({
  name: 'bull_queue_failed',
  help: 'Number of failed jobs',
  labelNames: ['queue'],
  registers: [register],
});

const processedTotal = new Counter({
  name: 'bull_jobs_processed_total',
  help: 'Total processed jobs',
  labelNames: ['queue'],
  registers: [register],
});

// Create queue
const queue = new Queue('emails', { connection });

// Update metrics periodically
setInterval(async () => {
  const waiting = await queue.getWaitingCount();
  const failed = await queue.getFailedCount();
  queueSize.set({ queue: 'emails' }, waiting);
  failedJobs.set({ queue: 'emails' }, failed);
}, 5000);

// Track processed jobs
const queueEvents = new QueueEvents('emails', { connection });
queueEvents.on('completed', () => {
  processedTotal.inc({ queue: 'emails' });
});

// Expose metrics endpoint
const app = express();
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});
app.listen(9090);
```

### Register with Prometheus

Add your app to observability targets:

```bash
cd ../../tools/observability
./scripts/manage-targets.sh add application \
  --name my-worker \
  --host host.docker.internal \
  --port 9090
```

Or edit `observability/targets/applications.json`:

```json
[
  {
    "targets": ["host.docker.internal:9090"],
    "labels": {
      "service": "my-worker",
      "environment": "production"
    }
  }
]
```

### Pre-configured Alerts

Alerting rules are already configured in observability stack:

| Alert | Condition | Severity |
|-------|-----------|----------|
| TaskQueueBacklog | Queue > 1000 tasks | Warning |
| TaskQueueBacklogCritical | Queue > 5000 tasks | Critical |
| TaskFailureRateHigh | Failure rate > 10% | Warning |
| TasksInDeadQueue | Dead tasks > 0 | Warning |
| TaskWorkersIdle | No processing + tasks pending | Critical |

## Usage in Your Application

### Go Example

```go
// Client (enqueue tasks)
client := asynq.NewClient(asynq.RedisClientOpt{
    Addr:     "localhost:6380",
    Password: "your_password",
})
defer client.Close()

// Enqueue with options
task := asynq.NewTask("email:send", []byte(`{"to":"user@example.com"}`))
client.Enqueue(task,
    asynq.MaxRetry(5),
    asynq.Timeout(10*time.Minute),
    asynq.Queue("critical"),
    asynq.Unique(time.Hour),
)

// Worker
srv := asynq.NewServer(redisOpt, asynq.Config{
    Concurrency: 10,
    Queues: map[string]int{"critical": 6, "default": 3, "low": 1},
})

mux := asynq.NewServeMux()
mux.HandleFunc("email:send", handleEmailTask)
srv.Run(mux)
```

### Node.js Example (BullMQ)

```typescript
import { Queue, Worker } from 'bullmq';

const connection = { host: 'localhost', port: 6380, password: 'your_password' };

// Producer
const queue = new Queue('emails', { connection });
await queue.add('send', { to: 'user@example.com' }, {
    attempts: 5,
    backoff: { type: 'exponential', delay: 1000 },
    removeOnComplete: 1000,
    removeOnFail: 5000,
});

// Worker
const worker = new Worker('emails', async job => {
    console.log('Sending email to:', job.data.to);
}, {
    connection,
    concurrency: 10,
});
```

## Comparison: Asynqmon vs Observability

| Feature | Asynqmon | Observability |
|---------|----------|---------------|
| View individual tasks | ✅ | ❌ |
| Retry failed tasks | ✅ | ❌ |
| See task payloads | ✅ | ❌ |
| Historical metrics | ❌ | ✅ |
| Alerting | ❌ | ✅ |
| Dashboards | ❌ | ✅ |

**Use both:**
- Asynqmon for debugging/operations
- Observability for monitoring/alerting

## File Structure

```
asynq/
├── docker-compose.yml
├── .env.example
├── .env              # (gitignored)
└── README.md
```
