# Authentik - Identity Provider

Open-source identity provider with SSO, OAuth2, SAML, LDAP, and more.

## Features

- Single Sign-On (SSO) for all your apps
- OAuth2/OpenID Connect provider
- SAML provider
- LDAP provider
- User management & self-service
- Multi-factor authentication (MFA)
- Social login (Google, GitHub, etc.)

## Quick Start

```bash
./setup.sh
```

Access at: http://localhost:9000

**First login:**
- Username: `akadmin`
- Password: (from .env `AUTHENTIK_BOOTSTRAP_PASSWORD`)

## Use Cases

| Scenario | How Authentik Helps |
|----------|---------------------|
| Protect Grafana | SSO login via OAuth2 |
| Protect n8n | Forward auth via Traefik |
| Protect internal tools | Single login for everything |
| User management | Central user directory |

## Integrate with Traefik

### 1. Create Outpost in Authentik

1. Go to Applications > Outposts
2. Create "Embedded Outpost" (or deploy proxy outpost)
3. Note the outpost URL

### 2. Add Forward Auth to Traefik

```yaml
# traefik/config/dynamic/authentik.yml
http:
  middlewares:
    authentik:
      forwardAuth:
        address: http://authentik-server:9000/outpost.goauthentik.io/auth/traefik
        trustForwardHeader: true
        authResponseHeaders:
          - X-authentik-username
          - X-authentik-groups
          - X-authentik-email
```

### 3. Protect Your Apps

```yaml
# In your app's docker-compose.yml
labels:
  - "traefik.http.routers.myapp.middlewares=authentik@file"
```

## Integrate with Grafana

1. In Authentik: Create OAuth2 Provider & Application
2. In Grafana `.env`:

```bash
GF_AUTH_GENERIC_OAUTH_ENABLED=true
GF_AUTH_GENERIC_OAUTH_NAME=Authentik
GF_AUTH_GENERIC_OAUTH_CLIENT_ID=<from authentik>
GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET=<from authentik>
GF_AUTH_GENERIC_OAUTH_SCOPES=openid profile email
GF_AUTH_GENERIC_OAUTH_AUTH_URL=https://auth.example.com/application/o/authorize/
GF_AUTH_GENERIC_OAUTH_TOKEN_URL=https://auth.example.com/application/o/token/
GF_AUTH_GENERIC_OAUTH_API_URL=https://auth.example.com/application/o/userinfo/
```

## Using External Database/Redis

To use your existing PostgreSQL and Redis instead of bundled:

1. Edit `.env`:
```bash
POSTGRES_HOST=host.docker.internal
POSTGRES_PORT=5432
POSTGRES_DB=authentik
POSTGRES_USER=authentik
POSTGRES_PASSWORD=your-password

REDIS_HOST=host.docker.internal
REDIS_PORT=6379
```

2. Remove bundled services from `docker-compose.yml`:
   - Delete the `postgresql` service
   - Delete the `redis` service

3. Create database:
```bash
cd ../../databases/postgres-single
docker exec -it postgres psql -U postgres -c "CREATE DATABASE authentik;"
docker exec -it postgres psql -U postgres -c "CREATE USER authentik WITH PASSWORD 'your-password';"
docker exec -it postgres psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE authentik TO authentik;"
```

## Commands

```bash
# View logs
docker compose logs -f server

# Restart
docker compose restart

# Update
docker compose pull
docker compose up -d
```

## Ports

| Port | Service |
|------|---------|
| 9000 | HTTP |
| 9443 | HTTPS |

## Architecture

```
┌─────────────┐     ┌─────────────┐
│   Traefik   │────▶│  Authentik  │
│  (Reverse   │     │   Server    │
│   Proxy)    │     └──────┬──────┘
└─────────────┘            │
       │              ┌────┴────┐
       │              │ Worker  │
       ▼              └────┬────┘
┌─────────────┐            │
│  Your Apps  │       ┌────┴────┐
│  (Protected │       │ Postgres│
│   by SSO)   │       │  Redis  │
└─────────────┘       └─────────┘
```

## Resources

- [Authentik Docs](https://goauthentik.io/docs/)
- [Integrations](https://goauthentik.io/integrations/)
