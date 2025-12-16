# Traefik Reverse Proxy - Production Setup

Production-ready Traefik reverse proxy with automatic SSL, security headers, and rate limiting.

## Features

- Automatic Let's Encrypt SSL certificates
- Docker service auto-discovery via labels
- Security headers (HSTS, XSS, etc.)
- Rate limiting (standard, strict, relaxed)
- Secure dashboard with authentication
- Access logging with filtering
- Prometheus metrics integration
- TLS 1.2+ with modern cipher suites

## Quick Start

### 1. Create the network

```bash
docker network create infra
```

### 2. Configure environment

```bash
cp .env.example .env
```

Edit `.env` and set:
- `ACME_EMAIL` - Your email for Let's Encrypt
- `TRAEFIK_DASHBOARD_HOST` - Dashboard domain (e.g., `traefik.example.com`)
- `TRAEFIK_DASHBOARD_AUTH` - Dashboard password hash

### 3. Generate dashboard password

```bash
# Install htpasswd if not available
# Ubuntu/Debian: apt install apache2-utils
# CentOS/RHEL: yum install httpd-tools
# macOS: brew install httpd

# Generate password hash (replace 'your-password')
htpasswd -nB admin
# Output: admin:$2y$05$...

# Copy the output to .env (escape $ with $$)
# admin:$2y$05$abc → admin:$$2y$$05$$abc
```

### 4. Create certificate storage

```bash
touch certs/acme.json
chmod 600 certs/acme.json
```

### 5. Start Traefik

```bash
docker compose up -d
```

### 6. Verify

```bash
# Check logs
docker compose logs -f

# Check dashboard (after DNS is configured)
curl -I https://traefik.example.com
```

## Adding Services

To expose a service through Traefik, add labels to your `docker-compose.yml`:

### Basic Example

```yaml
services:
  myapp:
    image: myapp:latest
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`app.example.com`)"
      - "traefik.http.routers.myapp.entrypoints=websecure"
      - "traefik.http.routers.myapp.tls.certresolver=letsencrypt"
    networks:
      - infra

networks:
  infra:
    external: true
```

### With Middlewares

```yaml
services:
  myapp:
    image: myapp:latest
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`app.example.com`)"
      - "traefik.http.routers.myapp.entrypoints=websecure"
      - "traefik.http.routers.myapp.tls.certresolver=letsencrypt"
      # Apply middleware chain
      - "traefik.http.routers.myapp.middlewares=chain-web@file"
    networks:
      - infra

networks:
  infra:
    external: true
```

### With Custom Port

```yaml
services:
  myapp:
    image: myapp:latest
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`app.example.com`)"
      - "traefik.http.routers.myapp.entrypoints=websecure"
      - "traefik.http.routers.myapp.tls.certresolver=letsencrypt"
      # Specify which port the container uses
      - "traefik.http.services.myapp.loadbalancer.server.port=8080"
    networks:
      - infra

networks:
  infra:
    external: true
```

### Path-Based Routing

```yaml
services:
  api:
    image: api:latest
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.api.rule=Host(`example.com`) && PathPrefix(`/api`)"
      - "traefik.http.routers.api.entrypoints=websecure"
      - "traefik.http.routers.api.tls.certresolver=letsencrypt"
      - "traefik.http.routers.api.middlewares=chain-api@file"
    networks:
      - infra

networks:
  infra:
    external: true
```

### Wildcard Certificate (DNS Challenge)

```yaml
services:
  myapp:
    image: myapp:latest
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`app.example.com`)"
      - "traefik.http.routers.myapp.entrypoints=websecure"
      # Use DNS challenge for wildcard
      - "traefik.http.routers.myapp.tls.certresolver=letsencrypt-dns"
      - "traefik.http.routers.myapp.tls.domains[0].main=example.com"
      - "traefik.http.routers.myapp.tls.domains[0].sans=*.example.com"
    networks:
      - infra

networks:
  infra:
    external: true
```

## Available Middlewares

| Middleware | Description | Usage |
|------------|-------------|-------|
| `security-headers@file` | Full security headers (HSTS, XSS, etc.) | Web apps |
| `security-headers-api@file` | Relaxed headers for APIs | API services |
| `rate-limit@file` | 100 req/s rate limit | Standard |
| `rate-limit-strict@file` | 10 req/s rate limit | Login pages |
| `rate-limit-relaxed@file` | 500 req/s rate limit | Static assets |
| `ip-whitelist-internal@file` | Private IP only | Internal services |
| `compress@file` | Gzip compression | All services |
| `chain-web@file` | Security + rate limit + compress | Web apps |
| `chain-api@file` | API headers + rate limit + compress | APIs |
| `chain-internal@file` | IP whitelist + security | Internal |

## Connecting Your Infrastructure

### Expose Grafana

```yaml
# In observability/docker-compose.yml, add to grafana service:
services:
  grafana:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.grafana.rule=Host(`grafana.example.com`)"
      - "traefik.http.routers.grafana.entrypoints=websecure"
      - "traefik.http.routers.grafana.tls.certresolver=letsencrypt"
      - "traefik.http.routers.grafana.middlewares=chain-web@file"
      - "traefik.http.services.grafana.loadbalancer.server.port=3000"
    networks:
      - infra
      - observability

networks:
  infra:
    external: true
  observability:
    # keep existing network
```

### Expose n8n

```yaml
# In n8n/docker-compose.yml:
services:
  n8n:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.n8n.rule=Host(`n8n.example.com`)"
      - "traefik.http.routers.n8n.entrypoints=websecure"
      - "traefik.http.routers.n8n.tls.certresolver=letsencrypt"
      - "traefik.http.routers.n8n.middlewares=chain-web@file"
      - "traefik.http.services.n8n.loadbalancer.server.port=5678"
    networks:
      - infra

networks:
  infra:
    external: true
```

## Prometheus Integration

Add to `observability/config/prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'traefik'
    static_configs:
      - targets: ['traefik:8080']
        labels:
          service: 'traefik'
```

## Troubleshooting

### Check Traefik logs

```bash
docker compose logs -f traefik
```

### Verify certificate

```bash
echo | openssl s_client -servername app.example.com -connect app.example.com:443 2>/dev/null | openssl x509 -noout -dates
```

### Test rate limiting

```bash
# Should get rate limited after many requests
for i in {1..200}; do curl -s -o /dev/null -w "%{http_code}\n" https://app.example.com; done
```

### Debug mode

Temporarily set log level in `config/traefik.yml`:
```yaml
log:
  level: DEBUG
```

Then restart: `docker compose restart`

## File Structure

```
traefik/
├── docker-compose.yml      # Main compose file
├── .env.example            # Environment template
├── .env                    # Your configuration (git-ignored)
├── config/
│   ├── traefik.yml         # Static configuration
│   └── dynamic/
│       ├── middlewares.yml # Reusable middlewares
│       └── tls.yml         # TLS settings
├── certs/
│   └── acme.json           # Let's Encrypt certificates (auto-generated)
└── README.md
```
