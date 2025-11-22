# 📊 Production Observability Stack

Complete observability solution with metrics, logs, and traces for microservices.

## 🏗️ Architecture

```
Your Application
       ↓
OpenTelemetry Collector (OTLP)
       ↓
   ┌────┴────┬────────┬────────┐
   ↓         ↓        ↓        ↓
Prometheus  Loki   Tempo    Jaeger
   ↓         ↓        ↓        ↓
       Grafana (Visualization)
```

## 🚀 Quick Start

### 1. Configure Environment

```bash
# Copy and edit .env file
cp .env.example .env
nano .env

# Change at minimum:
# - GRAFANA_ADMIN_PASSWORD
```

### 2. Start the Stack

```bash
chmod +x observability-cli.sh
./observability-cli.sh start
```

### 3. Access Dashboards

- **Grafana**: http://localhost:3000 (admin/your-password)
- **Prometheus**: http://localhost:9090
- **Jaeger**: http://localhost:16686

## 📦 Components

### **OpenTelemetry Collector**

- Receives telemetry data from your applications
- Ports: 4317 (gRPC), 4318 (HTTP)

### **Prometheus**

- Metrics storage and querying
- Port: 9090
- Retention: 15 days (configurable)

### **Loki**

- Log aggregation
- Port: 3100
- Retention: 7 days (configurable)

### **Tempo**

- Distributed tracing storage
- Port: 3200

### **Jaeger**

- Distributed tracing UI
- Port: 16686

### **Grafana**

- Unified visualization
- Port: 3000

## 🔧 Management

```bash
# Start all services
./observability-cli.sh start

# Check health
./observability-cli.sh health

# View logs
./observability-cli.sh logs-grafana

# Backup data
./observability-cli.sh backup

# Show all URLs
./observability-cli.sh urls
```

## 📊 Instrumenting Your Application

### Node.js Example

```javascript
const { NodeSDK } = require("@opentelemetry/sdk-node");
const {
  getNodeAutoInstrumentations,
} = require("@opentelemetry/auto-instrumentations-node");
const {
  OTLPTraceExporter,
} = require("@opentelemetry/exporter-trace-otlp-grpc");
const {
  OTLPMetricExporter,
} = require("@opentelemetry/exporter-metrics-otlp-grpc");

const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter({
    url: "http://localhost:4317",
  }),
  metricReader: new PeriodicExportingMetricReader({
    exporter: new OTLPMetricExporter({
      url: "http://localhost:4317",
    }),
  }),
  instrumentations: [getNodeAutoInstrumentations()],
});

sdk.start();
```

### Python Example

```python
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

trace.set_tracer_provider(TracerProvider())
tracer = trace.get_tracer(__name__)

otlp_exporter = OTLPSpanExporter(endpoint="localhost:4317", insecure=True)
span_processor = BatchSpanProcessor(otlp_exporter)
trace.get_tracer_provider().add_span_processor(span_processor)
```

## 🔐 Security

### Production Checklist

- [ ] Change `GRAFANA_ADMIN_PASSWORD` in `.env`
- [ ] Enable authentication on Prometheus
- [ ] Use TLS for OTLP endpoints
- [ ] Restrict network access
- [ ] Enable Grafana HTTPS
- [ ] Set up Grafana users/roles

## 📈 Performance Tuning

### Memory Limits (in `.env`)

```bash
# Adjust based on your workload
PROMETHEUS_MEMORY_LIMIT=2g
LOKI_MEMORY_LIMIT=1g
TEMPO_MEMORY_LIMIT=1g
GRAFANA_MEMORY_LIMIT=512m
```

### Data Retention

```bash
# Prometheus
PROMETHEUS_RETENTION_TIME=15d

# Loki
LOKI_RETENTION_PERIOD=168h  # 7 days
```

## 🛠️ Troubleshooting

### Services not starting

```bash
# Check logs
./observability-cli.sh logs

# Check health
./observability-cli.sh health

# Check Docker resources
docker stats
```

### Out of memory

```bash
# Adjust memory limits in .env
PROMETHEUS_MEMORY_LIMIT=4g  # Increase if needed

# Restart services
./observability-cli.sh restart
```

### Data not appearing in Grafana

1. Check data source configuration in Grafana
2. Verify your app is sending data to OTLP endpoint
3. Check OTEL Collector logs: `./observability-cli.sh logs-otel`

## 📚 Grafana Dashboards

### Import Recommended Dashboards

1. Go to Grafana → Dashboards → Import
2. Use these IDs:
   - **Node Exporter Full**: 1860
   - **Loki Logs**: 13639
   - **Jaeger Traces**: 10001
   - **OTEL Collector**: 15983

## 🔄 Backup & Restore

### Backup

```bash
./observability-cli.sh backup
# Backups saved to ./backups/
```

### Restore

```bash
# Stop services
docker-compose down

# Restore volumes (example for Prometheus)
docker run --rm -v observability_prometheus-data:/data \
  -v "$(pwd)/backups/backup_TIMESTAMP":/backup \
  alpine sh -c "cd /data && tar xzf /backup/prometheus-data.tar.gz"

# Restart
./observability-cli.sh start
```

## 📊 Monitoring This Stack

The stack monitors itself! Check:

- OTEL Collector metrics: http://localhost:8888/metrics
- Prometheus self-metrics: http://localhost:9090/metrics

## 🎯 Best Practices

1. **Metrics**: Use Prometheus for time-series metrics
2. **Logs**: Send structured JSON logs to Loki via Promtail
3. **Traces**: Use OpenTelemetry SDK in your app
4. **Dashboards**: Create custom Grafana dashboards for your KPIs
5. **Alerts**: Set up Prometheus alerting rules
6. **Retention**: Adjust based on compliance/storage needs

## Summay

- Start: `./observability-cli.sh start`
- Stop all services: `./observability-cli.sh stop`
- Restart all services: `./observability-cli.sh restart`
- Remove all: `./observability-cli.sh down`
- Clean all: `./observability-cli.sh clean`
- Check logs: `./observability-cli.sh logs`
- Health check: `./observability-cli.sh health`

- View lowg from specific services
  ./observability-cli.sh logs-grafana
  ./observability-cli.sh logs-prometheus
  ./observability-cli.sh logs-loki
  ./observability-cli.sh logs-tempo
  ./observability-cli.sh logs-jaeger
  ./observability-cli.sh logs-otel
