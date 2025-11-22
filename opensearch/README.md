# OpenSearch Production Setup

A production-ready OpenSearch deployment with Docker Compose, featuring security, monitoring, and backup capabilities.

## 🚀 Quick Start

```bash
# Start OpenSearch cluster
./opensearch-cli.sh start

# Check cluster health
./opensearch-cli.sh health

# Open OpenSearch Dashboards
./opensearch-cli.sh dashboard
```

## 📋 Prerequisites

- **Docker**: 20.10+
- **Docker Compose**: 2.0+
- **Memory**: 4GB+ RAM recommended
- **Storage**: 20GB+ free space
- **OS**: Linux/macOS/Windows with WSL2

### System Configuration

On Linux, you may need to increase `vm.max_map_count`:

```bash
sudo sysctl -w vm.max_map_count=262144
echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf
```

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   OpenSearch Production                     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────┐    ┌─────────────────────────────────┐ │
│  │ OpenSearch Node │    │    OpenSearch Dashboards       │ │
│  │                 │    │                                 │ │
│  │ • Data Storage  │◄──►│ • Web Interface                 │ │
│  │ • Search API    │    │ • Visualizations                │ │
│  │ • Indexing      │    │ • Index Management              │ │
│  └─────────────────┘    └─────────────────────────────────┘ │
│                                                             │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │             Data Persistence                            │ │
│  │                                                         │ │
│  │ • ./data     - Index data                               │ │
│  │ • ./logs     - Application logs                         │ │
│  │ • ./backup   - Snapshot storage                         │ │
│  │ • ./config   - Configuration files                      │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## 🔧 Configuration

### Environment Variables (.env)

| Variable                            | Description             | Default                 |
| ----------------------------------- | ----------------------- | ----------------------- |
| `CLUSTER_NAME`                      | OpenSearch cluster name | `production-opensearch` |
| `OPENSEARCH_INITIAL_ADMIN_PASSWORD` | Admin password          | `Admin123!@#$%`         |
| `OPENSEARCH_PORT`                   | API port                | `9200`                  |
| `OPENSEARCH_DASHBOARDS_PORT`        | Dashboard port          | `5601`                  |
| `OPENSEARCH_JAVA_OPTS`              | JVM options             | `-Xms2g -Xmx2g`         |

### Security Settings

- **Authentication**: Internal user database
- **Authorization**: Role-based access control
- **Audit Logging**: Enabled for compliance
- **SSL/TLS**: Configurable (disabled by default for development)

## 🛠️ Management Commands

### Basic Operations

```bash
# Start cluster
./opensearch-cli.sh start

# Stop cluster
./opensearch-cli.sh stop

# Restart cluster
./opensearch-cli.sh restart

# Show status
./opensearch-cli.sh status
```

### Monitoring & Health

```bash
# Comprehensive health check
./opensearch-cli.sh health

# View logs (all services)
./opensearch-cli.sh logs

# View specific service logs
./opensearch-cli.sh logs opensearch-node1
./opensearch-cli.sh logs opensearch-dashboards
```

### Data Management

```bash
# Create backup
./opensearch-cli.sh backup

# Reset admin password
./opensearch-cli.sh reset-password

# Clean up all data (DESTRUCTIVE!)
./opensearch-cli.sh cleanup
```

### Monitoring Profile

```bash
# Start with performance monitoring
./opensearch-cli.sh monitoring
```

## 🌐 Service Endpoints

| Service                   | URL                   | Description                      |
| ------------------------- | --------------------- | -------------------------------- |
| **OpenSearch API**        | http://localhost:9200 | REST API for search and indexing |
| **OpenSearch Dashboards** | http://localhost:5601 | Web interface and visualizations |

### Default Credentials

- **Username**: `admin`
- **Password**: `Admin123!@#$%` (change this in production!)

## 📊 Index Management

### Creating Index Templates

The setup includes pre-configured templates for common use cases:

```bash
# Application logs
curl -X PUT "localhost:9200/_index_template/application-logs" \
     -H "Content-Type: application/json" \
     -u admin:Admin123!@#$% \
     -d @config/index-templates.json
```

### Index Lifecycle Management

```bash
# Create ILM policy for log rotation
curl -X PUT "localhost:9200/_plugins/_ism/policies/log-rotation" \
     -H "Content-Type: application/json" \
     -u admin:Admin123!@#$% \
     -d '{
       "policy": {
         "description": "Rotate logs monthly",
         "default_state": "hot",
         "states": [
           {
             "name": "hot",
             "actions": [],
             "transitions": [
               {
                 "state_name": "delete",
                 "conditions": {
                   "min_index_age": "30d"
                 }
               }
             ]
           },
           {
             "name": "delete",
             "actions": [
               {
                 "delete": {}
               }
             ]
           }
         ]
       }
     }'
```

## 🔐 Security Configuration

### User Management

```bash
# Create new user
curl -X PUT "localhost:9200/_plugins/_security/api/internalusers/newuser" \
     -H "Content-Type: application/json" \
     -u admin:Admin123!@#$% \
     -d '{
       "password": "newpassword",
       "backend_roles": ["readall"],
       "attributes": {
         "attribute1": "value1"
       }
     }'

# Assign roles
curl -X PUT "localhost:9200/_plugins/_security/api/rolesmapping/readall" \
     -H "Content-Type: application/json" \
     -u admin:Admin123!@#$% \
     -d '{
       "backend_roles": ["readall"],
       "users": ["newuser"]
     }'
```

### SSL/TLS Setup (Production)

1. Generate certificates:

```bash
# Create certificates directory
mkdir -p ./config/certificates

# Generate CA and node certificates
openssl genrsa -out ./config/certificates/root-ca-key.pem 2048
openssl req -new -x509 -sha256 -key ./config/certificates/root-ca-key.pem -out ./config/certificates/root-ca.pem -days 730
```

2. Update `.env` file:

```bash
OPENSEARCH_TLS_ENABLED=true
OPENSEARCH_TLS_CERT_PATH=/usr/share/opensearch/config/certificates
```

## 💾 Backup & Recovery

### Snapshot Repository Setup

```bash
# Register snapshot repository
curl -X PUT "localhost:9200/_snapshot/backup_repo" \
     -H "Content-Type: application/json" \
     -u admin:Admin123!@#$% \
     -d '{
       "type": "fs",
       "settings": {
         "location": "/usr/share/opensearch/backup"
       }
     }'
```

### Create Snapshot

```bash
# Manual snapshot
curl -X PUT "localhost:9200/_snapshot/backup_repo/snapshot_$(date +%Y%m%d)" \
     -H "Content-Type: application/json" \
     -u admin:Admin123!@#$% \
     -d '{"include_global_state": true}'

# Or use the CLI
./opensearch-cli.sh backup
```

### Restore from Snapshot

```bash
# List snapshots
curl -X GET "localhost:9200/_snapshot/backup_repo/_all" \
     -u admin:Admin123!@#$%

# Restore snapshot
curl -X POST "localhost:9200/_snapshot/backup_repo/snapshot_name/_restore" \
     -H "Content-Type: application/json" \
     -u admin:Admin123!@#$% \
     -d '{
       "indices": "*",
       "ignore_unavailable": true,
       "include_global_state": true
     }'
```

## 📈 Performance Tuning

### JVM Configuration

Edit `config/jvm.options`:

```bash
# Heap size (50% of available RAM, max 32GB)
-Xms4g
-Xmx4g

# Use G1GC for better performance
-XX:+UseG1GC
-XX:MaxGCPauseMillis=200
```

### Index Settings

```bash
# Optimize for write performance
curl -X PUT "localhost:9200/my-index/_settings" \
     -H "Content-Type: application/json" \
     -u admin:Admin123!@#$% \
     -d '{
       "index": {
         "refresh_interval": "30s",
         "number_of_replicas": 0,
         "translog.flush_threshold_size": "1gb"
       }
     }'
```

## 🚨 Troubleshooting

### Common Issues

1. **Out of Memory Errors**

   ```bash
   # Check JVM settings
   ./opensearch-cli.sh logs opensearch-node1 | grep -i "out of memory"

   # Adjust heap size in .env
   OPENSEARCH_JAVA_OPTS=-Xms4g -Xmx4g
   ```

2. **Disk Space Issues**

   ```bash
   # Check disk usage
   du -sh ./data ./logs ./backup

   # Clean old logs
   find ./logs -name "*.log" -mtime +7 -delete
   ```

3. **Authentication Problems**

   ```bash
   # Reset admin password
   ./opensearch-cli.sh reset-password

   # Check security configuration
   curl -X GET "localhost:9200/_plugins/_security/whoami" -u admin:newpassword
   ```

### Health Check Commands

```bash
# Cluster health
curl -X GET "localhost:9200/_cluster/health?pretty" -u admin:Admin123!@#$%

# Node stats
curl -X GET "localhost:9200/_nodes/stats?pretty" -u admin:Admin123!@#$%

# Index health
curl -X GET "localhost:9200/_cat/indices?v" -u admin:Admin123!@#$%
```

## 🔄 Updates & Maintenance

### Updating OpenSearch

1. Stop the cluster:

   ```bash
   ./opensearch-cli.sh stop
   ```

2. Update version in `docker-compose.yml`:

   ```yaml
   image: opensearchproject/opensearch:2.16.0 # Update version
   ```

3. Start with new version:
   ```bash
   ./opensearch-cli.sh start
   ```

### Regular Maintenance

- **Weekly**: Check cluster health and disk usage
- **Monthly**: Create snapshots and test restore procedures
- **Quarterly**: Update OpenSearch version and review security settings

## 📚 Additional Resources

- [OpenSearch Documentation](https://opensearch.org/docs/)
- [Security Plugin Guide](https://opensearch.org/docs/latest/security-plugin/)
- [Performance Tuning](https://opensearch.org/docs/latest/opensearch/performance/)
- [Monitoring](https://opensearch.org/docs/latest/monitoring-plugins/index/)

## 🆘 Support

For issues and questions:

1. Check the troubleshooting section above
2. Review OpenSearch logs: `./opensearch-cli.sh logs`
3. Check cluster health: `./opensearch-cli.sh health`
4. Consult [OpenSearch Community Forums](https://forum.opensearch.org/)

---

**⚠️ Security Notice**: Always change default passwords and enable SSL/TLS in production environments!
