# Garage - S3-Compatible Object Storage

Lightweight, self-hosted S3-compatible storage using [Garage](https://garagehq.deuxfleurs.fr/).

## Features

- S3-compatible API
- Lightweight (~50MB RAM)
- Built-in data deduplication
- Distributed by design (can scale to multiple nodes)
- Web hosting for static sites
- MIT license (no AGPL concerns like MinIO)

## Quick Start

```bash
# One-click setup (recommended)
./setup.sh

# Create your first bucket
./scripts/manage.sh quick-setup myapp
```

That's it! The setup script automatically:
- Generates secure secrets
- Creates configuration files
- Starts Garage
- Configures cluster layout

## Installation

### Option 1: Automated Setup (Recommended)

```bash
./setup.sh
```

This handles everything automatically. Skip to [Create Buckets](#create-buckets) after running.

### Option 2: Manual Setup

If you need more control over the setup process:

#### Step 1: Configure Environment

```bash
cp .env.example .env
nano .env  # Optional: customize settings
```

Key settings:
| Variable | Default | Description |
|----------|---------|-------------|
| `GARAGE_CAPACITY` | `100G` | Storage capacity (e.g., `100G`, `1T`) |
| `GARAGE_REPLICATION_FACTOR` | `1` | 1 for single node, 3 for cluster |
| `GARAGE_COMPRESSION_LEVEL` | `1` | 0=none, 1=fast, 2=default, 3=best |

Secrets are auto-generated if not set.

#### Step 2: Initialize and Start

```bash
./scripts/init.sh       # Generate config
docker compose up -d    # Start Garage
./scripts/setup-layout.sh  # Configure layout
```

#### Step 3: Start with Web UI (Optional)

```bash
docker compose --profile webui up -d
```

### Create Buckets

```bash
# Quick setup: creates bucket + key in one command
./scripts/manage.sh quick-setup myapp

# Or manually:
./scripts/manage.sh bucket create myapp
./scripts/manage.sh key create myapp-key
./scripts/manage.sh allow myapp myapp-key
```

## Usage

### Management Commands

```bash
# Status
./scripts/manage.sh status

# Buckets
./scripts/manage.sh bucket list
./scripts/manage.sh bucket create <name>
./scripts/manage.sh bucket delete <name>
./scripts/manage.sh bucket info <name>
./scripts/manage.sh bucket website <name>    # Enable static hosting

# Access Keys
./scripts/manage.sh key list
./scripts/manage.sh key create <name>
./scripts/manage.sh key delete <id>
./scripts/manage.sh key info <id>

# Permissions
./scripts/manage.sh allow <bucket> <key>     # Grant access
./scripts/manage.sh deny <bucket> <key>      # Revoke access

# Quick setup (bucket + key)
./scripts/manage.sh quick-setup <name>
```

### Using with AWS CLI

```bash
# Configure AWS CLI
aws configure --profile garage
# Access Key ID: <from key create output>
# Secret Access Key: <from key create output>
# Region: garage
# Output format: json

# Set endpoint
export AWS_ENDPOINT_URL=http://localhost:3900

# List buckets
aws --profile garage --endpoint-url http://localhost:3900 s3 ls

# Upload file
aws --profile garage --endpoint-url http://localhost:3900 s3 cp file.txt s3://myapp/

# Download file
aws --profile garage --endpoint-url http://localhost:3900 s3 cp s3://myapp/file.txt ./
```

### Using with Restic (Backups)

```bash
# In backup/.env
RESTIC_REPOSITORY=s3:http://localhost:3900/backups
AWS_ACCESS_KEY_ID=<your-key-id>
AWS_SECRET_ACCESS_KEY=<your-secret-key>
```

### Static Website Hosting

```bash
# Enable website hosting
./scripts/manage.sh bucket website my-site

# Upload files
aws --profile garage --endpoint-url http://localhost:3900 s3 sync ./public/ s3://my-site/

# Access at: http://my-site.web.garage.localhost:3902
# Or configure reverse proxy for custom domain
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `GARAGE_S3_API_PORT` | `3900` | S3 API port |
| `GARAGE_RPC_PORT` | `3901` | Inter-node RPC port |
| `GARAGE_S3_WEB_PORT` | `3902` | Static website hosting port |
| `GARAGE_ADMIN_PORT` | `3903` | Admin API + Metrics port |
| `GARAGE_CAPACITY` | `100G` | Storage capacity |
| `GARAGE_REPLICATION_FACTOR` | `1` | Replication (1=single node, 3=cluster) |
| `GARAGE_COMPRESSION_LEVEL` | `1` | 0=none, 1=fast, 2=default, 3=best |
| `GARAGE_MEMORY_LIMIT` | `1g` | Container memory limit |

### Performance Tuning

For high-throughput workloads:

```bash
# .env
GARAGE_BLOCK_SIZE=10485760          # 10MB blocks (better for large files)
GARAGE_COMPRESSION_LEVEL=0          # Disable compression (faster)
GARAGE_SLED_CACHE_CAPACITY=268435456  # 256MB metadata cache
GARAGE_MEMORY_LIMIT=2g              # More memory
```

For storage efficiency:

```bash
# .env
GARAGE_BLOCK_SIZE=1048576           # 1MB blocks
GARAGE_COMPRESSION_LEVEL=2          # Better compression
```

## Monitoring

### Prometheus Metrics

Metrics are available at `http://localhost:3903/metrics`

Add to Prometheus:

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'garage'
    static_configs:
      - targets: ['garage:3903']
    bearer_token: '<GARAGE_METRICS_TOKEN>'
```

### Health Check

```bash
# Check status
docker exec garage /garage status

# Detailed info
docker exec garage /garage stats
```

## Ports

| Port | Service | Description |
|------|---------|-------------|
| 3900 | S3 API | Main S3-compatible endpoint |
| 3901 | RPC | Inter-node communication |
| 3902 | Web | Static website hosting |
| 3903 | Admin | Admin API + Metrics |
| 3909 | WebUI | Optional web interface |

## Directory Structure

```
garage/
├── setup.sh                # One-click automated setup
├── docker-compose.yml      # Docker services
├── .env.example            # Environment template
├── .env                    # Your configuration (gitignored)
├── config/
│   ├── garage.toml.template  # Config template
│   └── garage.toml           # Generated config (gitignored)
├── scripts/
│   ├── init.sh             # Initialize configuration
│   ├── setup-layout.sh     # Setup cluster layout
│   └── manage.sh           # Bucket/key management
├── data/                   # Object data (gitignored)
└── meta/                   # Metadata (gitignored)
```

## Multi-Node Cluster

For production with redundancy:

1. Set `GARAGE_REPLICATION_FACTOR=3` in `.env`
2. Deploy on 3+ servers
3. Connect nodes via `rpc_public_addr`
4. Assign capacity on each node

See [Garage documentation](https://garagehq.deuxfleurs.fr/documentation/cookbook/real-world/) for detailed cluster setup.

## Troubleshooting

### Garage won't start

```bash
# Check logs
docker compose logs garage

# Verify config
cat config/garage.toml
```

### Layout not applied

```bash
# Check status
docker exec garage /garage status

# Manually assign
docker exec garage /garage layout assign --zone dc1 --capacity 100G <node-id>
docker exec garage /garage layout apply --version 1
```

### Permission denied

```bash
# Check key permissions
./scripts/manage.sh key info <key-id>

# Grant access
./scripts/manage.sh allow <bucket> <key>
```

## Resources

- [Garage Documentation](https://garagehq.deuxfleurs.fr/documentation/)
- [S3 Compatibility](https://garagehq.deuxfleurs.fr/documentation/reference-manual/s3-compatibility/)
- [Configuration Reference](https://garagehq.deuxfleurs.fr/documentation/reference-manual/configuration/)
