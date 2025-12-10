# Portainer

Docker management UI for managing containers, images, volumes, and networks.

## Quick Start

```bash
# Start Portainer
docker compose up -d

# Access UI
open https://localhost:9443
# or
open http://localhost:9000
```

## First Login

1. Open https://localhost:9443
2. Create admin user and password
3. Select "Local" environment to manage this Docker instance

## Features

- **Container Management** - Start, stop, restart, remove containers
- **Image Management** - Pull, build, remove images
- **Volume Management** - Create, inspect, remove volumes
- **Network Management** - Create and manage Docker networks
- **Stack Deployment** - Deploy docker-compose stacks from UI
- **Logs & Console** - View logs and exec into containers
- **Resource Monitoring** - CPU, memory, network stats

## Configuration

Edit `.env`:
- `PORTAINER_PORT` - HTTPS port (default: 9443)
- `PORTAINER_HTTP_PORT` - HTTP port (default: 9000)
- `PORTAINER_ADMIN_PASSWORD` - Pre-set admin password (optional)

## Security Notes

1. **Docker Socket Access**: Portainer has full Docker access via socket mount. This is powerful but also a security consideration.

2. **Network Access**: By default only accessible from localhost. Use Traefik for secure remote access.

3. **HTTPS**: Use port 9443 (HTTPS) rather than 9000 (HTTP) for better security.

## Exposing via Traefik

To access Portainer remotely with SSL:

1. Edit docker-compose.yml and uncomment Traefik labels
2. Set `PORTAINER_DOMAIN` in `.env`
3. Restart: `docker compose up -d`

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.portainer.rule=Host(`portainer.example.com`)"
  - "traefik.http.routers.portainer.entrypoints=websecure"
  - "traefik.http.routers.portainer.tls.certresolver=letsencrypt"
  - "traefik.http.services.portainer.loadbalancer.server.port=9000"
```

## Managing Multiple Hosts

Portainer can manage multiple Docker hosts:

1. Go to **Environments** > **Add environment**
2. Choose connection type:
   - **Agent** - Install Portainer Agent on remote host
   - **Docker API** - Connect via TCP (requires TLS)
   - **Edge Agent** - For firewalled environments

## Stacks

Deploy docker-compose applications:

1. Go to **Stacks** > **Add stack**
2. Paste docker-compose.yml content or upload file
3. Configure environment variables
4. Deploy

## User Management

For team access:

1. Go to **Users** > **Add user**
2. Create teams for different access levels
3. Assign environments and permissions per team

## Backup

Portainer data is stored in the `portainer_data` volume.

```bash
# Backup
docker run --rm -v portainer_data:/data -v $(pwd):/backup alpine \
    tar czf /backup/portainer-backup.tar.gz /data

# Restore
docker run --rm -v portainer_data:/data -v $(pwd):/backup alpine \
    tar xzf /backup/portainer-backup.tar.gz -C /
```
