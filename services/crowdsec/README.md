# Crowdsec - Modern Security Engine

Collaborative security engine that analyzes logs and shares threat intelligence with the community.

## Features

- **Crowd-sourced threat intelligence** - Community shares attack data
- **Behavior detection** - Not just pattern matching
- **Bouncers** - Block at firewall, Traefik, Nginx level
- **Modern alternative to Fail2ban**

## Quick Start

```bash
./scripts/setup.sh
```

This will:
1. Generate bouncer API key
2. Start Crowdsec
3. Install default collections
4. Register Traefik bouncer

## Integrate with Traefik

Add to your `traefik/docker-compose.yml`:

```yaml
services:
  traefik:
    # ... existing config
    labels:
      # Add bouncer middleware
      - "traefik.http.middlewares.crowdsec.forwardauth.address=http://crowdsec-traefik-bouncer:8080/api/v1/forwardAuth"
      - "traefik.http.middlewares.crowdsec.forwardauth.trustForwardHeader=true"
    networks:
      - crowdsec-net  # Add this network

networks:
  crowdsec-net:
    external: true
```

Then apply middleware to your routes:
```yaml
labels:
  - "traefik.http.routers.myapp.middlewares=crowdsec@docker"
```

## Commands

```bash
# View metrics
docker exec crowdsec cscli metrics

# View decisions (bans)
docker exec crowdsec cscli decisions list

# View alerts
docker exec crowdsec cscli alerts list

# Add manual ban
docker exec crowdsec cscli decisions add --ip 1.2.3.4 --duration 24h --reason "Manual ban"

# Remove ban
docker exec crowdsec cscli decisions delete --ip 1.2.3.4

# List installed collections
docker exec crowdsec cscli collections list

# Update collections
docker exec crowdsec cscli hub update
docker exec crowdsec cscli hub upgrade
```

## Collections

Pre-installed collections:

| Collection | Purpose |
|------------|---------|
| `crowdsecurity/linux` | SSH, syslog attacks |
| `crowdsecurity/traefik` | Traefik log parsing |
| `crowdsecurity/http-cve` | Known CVE exploits |
| `crowdsecurity/whitelist-good-actors` | Whitelist search engines |

Add more:
```bash
docker exec crowdsec cscli collections install crowdsecurity/nginx
docker exec crowdsec cscli collections install crowdsecurity/base-http-scenarios
```

## Crowdsec vs Fail2ban

| Feature | Fail2ban | Crowdsec |
|---------|----------|----------|
| Pattern matching | Regex | Regex + Behavior |
| Threat intel | None | Community-shared |
| Speed | Slower | Faster (Go) |
| Bouncers | iptables | Traefik, Nginx, iptables, etc. |
| Learning curve | Simple | Moderate |

**Recommendation:** Use both initially, then transition to Crowdsec.

## Monitoring

Crowdsec exposes Prometheus metrics:

```bash
# Add to observability
./scripts/manage-targets.sh add app --name crowdsec --host crowdsec --port 6060
```

## Architecture

```
Logs (Traefik, SSH, etc.)
         │
         ▼
    ┌─────────┐
    │Crowdsec │ ──► Community API (share/receive intel)
    │ Engine  │
    └────┬────┘
         │ Decisions
         ▼
    ┌─────────┐
    │Bouncers │ (Traefik, iptables, etc.)
    └────┬────┘
         │
         ▼
    Block bad IPs
```
