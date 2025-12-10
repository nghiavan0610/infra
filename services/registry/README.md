# Docker Registry - Private Container Images

Self-hosted Docker registry for storing your container images privately.

## Quick Start

```bash
./setup.sh
```

## Usage

### Login

```bash
docker login localhost:5000
# Username: admin
# Password: (from .env)
```

### Push Image

```bash
# Tag your image
docker tag myapp:latest localhost:5000/myapp:v1

# Push to registry
docker push localhost:5000/myapp:v1
```

### Pull Image

```bash
docker pull localhost:5000/myapp:v1
```

### List Images

```bash
# List repositories
curl -u admin:password http://localhost:5000/v2/_catalog

# List tags
curl -u admin:password http://localhost:5000/v2/myapp/tags/list
```

## Web UI

```bash
docker compose --profile ui up -d
```

Access at: http://localhost:5001

## Storage Backends

### Local Filesystem (Default)

Images stored in `./data/`

### Garage S3 Storage

Edit `.env`:
```bash
REGISTRY_STORAGE=s3
REGISTRY_S3_BUCKET=docker-registry
REGISTRY_S3_REGION=garage
REGISTRY_S3_ENDPOINT=http://garage:3900
REGISTRY_S3_ACCESS_KEY=your-key
REGISTRY_S3_SECRET_KEY=your-secret
```

Update `config.yml`:
```yaml
storage:
  s3:
    bucket: docker-registry
    region: garage
    regionendpoint: http://garage:3900
    accesskey: your-key
    secretkey: your-secret
```

## Traefik Integration

Add to Traefik for HTTPS access:

```yaml
# traefik/config/dynamic/registry.yml
http:
  routers:
    registry:
      rule: "Host(`registry.example.com`)"
      service: registry
      tls:
        certResolver: letsencrypt
  services:
    registry:
      loadBalancer:
        servers:
          - url: "http://registry:5000"
```

## Garbage Collection

Clean up deleted images:

```bash
# Dry run
docker exec registry bin/registry garbage-collect /etc/docker/registry/config.yml --dry-run

# Actually delete
docker exec registry bin/registry garbage-collect /etc/docker/registry/config.yml
```

## CI/CD Integration

### GitHub Actions

```yaml
- name: Login to Private Registry
  uses: docker/login-action@v3
  with:
    registry: registry.example.com
    username: ${{ secrets.REGISTRY_USER }}
    password: ${{ secrets.REGISTRY_PASSWORD }}

- name: Build and Push
  uses: docker/build-push-action@v5
  with:
    push: true
    tags: registry.example.com/myapp:${{ github.sha }}
```

## Ports

| Port | Service |
|------|---------|
| 5000 | Registry API |
| 5001 | Web UI (optional) |

## Security

- Always use HTTPS in production (via Traefik)
- Use strong passwords
- Consider IP whitelisting for push access
- Regularly run garbage collection
