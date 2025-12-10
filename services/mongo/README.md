# MongoDB Replica Set

Production-ready MongoDB 8.0 replica set with TLS, authentication, and monitoring.

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  mongo-primary  │────▶│ mongo-secondary │     │  mongo-arbiter  │
│   (priority 2)  │◀────│   (priority 1)  │     │  (votes only)   │
│     :27017      │     │     :27018      │     │     :27019      │
└─────────────────┘     └─────────────────┘     └─────────────────┘
         │
         ▼
┌─────────────────┐
│ mongodb-exporter│ ──▶ Prometheus
│     :9216       │
└─────────────────┘
```

## Quick Start

```bash
# 1. Generate TLS certificates (first time only)
./scripts/generate-certs.sh

# 2. Configure environment
cp .env.example .env
# Edit .env with your passwords

# 3. Start replica set
docker compose up -d

# 4. Initialize replica set and create users
./scripts/init-replica.sh

# 5. (Optional) Enable monitoring
docker compose --profile monitoring up -d
```

## Scripts

| Script | Description |
|--------|-------------|
| `scripts/generate-certs.sh` | Generate TLS certificates and keyfile |
| `scripts/init-replica.sh` | Initialize replica set and create users |
| `scripts/create-user.sh` | Create database users |

## Connection Strings

### Internal (Docker network)

```
mongodb://app:password@mongo-primary:27017,mongo-secondary:27017/mydb?replicaSet=rs0&tls=true&tlsCAFile=/path/to/ca.pem
```

### External (from host)

```
mongodb://app:password@localhost:27017,localhost:27018/mydb?replicaSet=rs0&tls=true&tlsCAFile=/path/to/ca.pem
```

### Application Example (Node.js)

```javascript
const { MongoClient } = require('mongodb');

const uri = 'mongodb://app:password@mongo-primary:27017/mydb?replicaSet=rs0';
const client = new MongoClient(uri, {
  tls: true,
  tlsCAFile: '/path/to/ca.pem',
  // For self-signed certs in development:
  // tlsAllowInvalidCertificates: true,
});
```

## User Management

```bash
# Create a new user
./scripts/create-user.sh myuser mypassword mydb readWrite

# Roles: read, readWrite, dbAdmin, dbOwner
```

## Backup & Restore

See the centralized backup system at `../backup/` for MongoDB backups.

```bash
cd ../../tools/backup
./scripts/backup-mongodb.sh
```

## Monitoring

Enable the mongodb-exporter for Prometheus monitoring:

```bash
docker compose --profile monitoring up -d
```

Then register with observability stack:

```bash
cd ../../tools/observability
./scripts/manage-targets.sh add mongodb --name mongo-rs --host host.docker.internal --port 9216
```

### Available Metrics

- Connection pool stats
- Replication lag
- Operations per second
- Memory usage
- Lock statistics
- Collection sizes

## TLS Certificates

### Generate New Certificates

```bash
# Default domain (mongodb.local)
./scripts/generate-certs.sh

# Custom domain
./scripts/generate-certs.sh mongo.example.com
```

### Certificate Files

| File | Purpose |
|------|---------|
| `ca.pem` | CA certificate (share with clients) |
| `ca.key` | CA private key (keep secret) |
| `mongodb.pem` | Server cert + key (for mongod) |
| `keyfile` | Internal replica set auth |

### For Production with Valid Certificates

1. Obtain certificates from a CA (Let's Encrypt, etc.)
2. Replace `mongodb.pem` with your valid certificate
3. Update `ca.pem` with the CA chain
4. Set in `.env`:
   ```
   MONGO_TLS_ALLOW_INVALID_HOSTNAMES=false
   MONGO_TLS_ALLOW_INVALID_CERTIFICATES=false
   ```

## Resource Sizing

### Small VPS (4GB RAM)

```env
MONGO_PRIMARY_MEMORY_LIMIT=1G
MONGO_PRIMARY_CACHE_SIZE_GB=0.25
```

Consider running single-node instead of replica set.

### Medium VPS (8-16GB RAM) - Default

```env
MONGO_PRIMARY_MEMORY_LIMIT=2G
MONGO_PRIMARY_CACHE_SIZE_GB=0.5
```

### Large VPS (32GB+ RAM)

```env
MONGO_PRIMARY_MEMORY_LIMIT=8G
MONGO_PRIMARY_CACHE_SIZE_GB=4
```

## Replica Set Commands

```bash
# Connect to mongo shell
docker exec -it mongo-primary mongosh -u admin -p <password> --authenticationDatabase admin

# Check replica set status
rs.status()

# Check who is primary
rs.isMaster()

# Step down primary (for maintenance)
rs.stepDown()

# Add a member
rs.add("hostname:port")

# Remove a member
rs.remove("hostname:port")
```

## Troubleshooting

### Replica Set Not Initializing

```bash
# Check container logs
docker logs mongo-primary

# Manually check status
docker exec mongo-primary mongosh --eval "rs.status()"
```

### Authentication Errors

```bash
# Verify keyfile permissions
ls -la certs/keyfile
# Should be 600

# Check if keyfile is readable
docker exec mongo-primary cat /etc/mongo/certs/keyfile | head -c 20
```

### TLS Issues

```bash
# Test TLS connection
openssl s_client -connect localhost:27017 -CAfile certs/ca.pem

# Check certificate
openssl x509 -in certs/mongodb.crt -text -noout
```

### Connection Refused

```bash
# Check if containers are running
docker compose ps

# Check container health
docker inspect mongo-primary --format='{{.State.Health.Status}}'

# Check listening ports
docker exec mongo-primary ss -tlnp
```

## Directory Structure

```
mongo/
├── docker-compose.yml      # Main compose file
├── .env.example            # Environment template
├── .env                    # Your configuration (git-ignored)
├── README.md               # This file
├── certs/                  # TLS certificates
│   ├── ca.pem
│   ├── ca.key
│   ├── mongodb.pem
│   └── keyfile
└── scripts/                # Management scripts
    ├── generate-certs.sh
    ├── init-replica.sh
    └── create-user.sh
```

## Security Checklist

- [ ] Changed default passwords in `.env`
- [ ] Generated new TLS certificates
- [ ] Keyfile has 600 permissions
- [ ] `.env` is git-ignored
- [ ] Backups are encrypted/secured
- [ ] Ports not exposed to internet (use firewall)
- [ ] Monitoring enabled
- [ ] Regular backup schedule configured
