# Adminer - Database Management UI

Lightweight, single-file database management tool supporting multiple database types.

## Quick Start

```bash
cp .env.example .env
docker compose up -d
```

Access: http://localhost:8081

## Connecting to Databases

### PostgreSQL

| Field | Value |
|-------|-------|
| System | PostgreSQL |
| Server | host.docker.internal |
| Username | postgres |
| Password | (from .secrets) |
| Database | (your database) |

### MongoDB

| Field | Value |
|-------|-------|
| System | MongoDB |
| Server | host.docker.internal:27017 |
| Username | admin |
| Password | (from .secrets) |
| Database | admin |

### Redis

Adminer doesn't support Redis directly. Use Redis Commander or RedisInsight instead.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `ADMINER_PORT` | 8081 | Web UI port |
| `DEFAULT_DB_HOST` | host.docker.internal | Pre-filled server |
| `ADMINER_DESIGN` | pepa-linha-dark | Theme |

## Security Warning

**Never expose Adminer directly to the internet!**

Options for secure access:
1. Keep on localhost only (default)
2. Use VPN (Wireguard)
3. Add basic auth via Traefik
4. Use SSH tunnel

### SSH Tunnel Access

```bash
# From your local machine
ssh -L 8081:localhost:8081 user@your-server

# Then open http://localhost:8081
```

## Available Themes

- `pepa-linha-dark` (default, dark mode)
- `nette`
- `hydra`
- `rmsoft`

Change in `.env`:
```
ADMINER_DESIGN=nette
```
