# WireGuard VPN

Fast, modern VPN for secure remote access to your infrastructure.

## Quick Start

```bash
# 1. Configure
cp .env.example .env
nano .env  # Set SERVERURL to your server's public IP

# 2. Open firewall
sudo ufw allow 51820/udp

# 3. Start
docker compose up -d

# 4. Get client configs
ls config/peer_*/
```

## Client Setup

### Desktop (macOS/Windows/Linux)

1. Install WireGuard: https://www.wireguard.com/install/
2. Copy config file: `config/peer_1/peer_1.conf`
3. Import into WireGuard app
4. Connect

### Mobile (iOS/Android)

1. Install WireGuard app
2. Scan QR code: `config/peer_1/peer_1.png`
3. Connect

### View QR Code in Terminal

```bash
docker compose exec wireguard /app/show-peer 1
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `SERVERURL` | auto | Server's public IP or domain |
| `SERVERPORT` | 51820 | UDP port |
| `PEERS` | 3 | Number of client configs |
| `ALLOWEDIPS` | 10.13.13.0/24,172.17.0.0/16 | Traffic routing |

## Traffic Routing

### Split Tunnel (Default)

Only infrastructure traffic goes through VPN:

```
ALLOWEDIPS=10.13.13.0/24,172.17.0.0/16
```

Access: PostgreSQL, Redis, Grafana, etc. via VPN
Internet: Goes through your local connection

### Full Tunnel

All traffic goes through VPN:

```
ALLOWEDIPS=0.0.0.0/0
```

## Adding More Clients

```bash
# Edit .env
PEERS=5  # Increase number

# Restart
docker compose up -d

# New configs appear in config/peer_4/ and config/peer_5/
```

## Named Peers

Instead of numbers, use names:

```bash
# In .env
PEERS=alice,bob,charlie
```

Configs will be in `config/peer_alice/`, etc.

## Access Services via VPN

Once connected, access services using VPN IP:

| Service | URL |
|---------|-----|
| Grafana | http://10.13.13.1:3000 |
| Adminer | http://10.13.13.1:8081 |
| PostgreSQL | 10.13.13.1:5432 |

Or use `host.docker.internal` if configured.

## Firewall Rules

```bash
# Allow WireGuard
sudo ufw allow 51820/udp

# If using full tunnel, enable forwarding
sudo sysctl -w net.ipv4.ip_forward=1
```

## Troubleshooting

### Check if running
```bash
docker compose exec wireguard wg show
```

### View logs
```bash
docker compose logs -f wireguard
```

### Regenerate configs
```bash
docker compose down
rm -rf config/*
docker compose up -d
```

## Security Notes

1. **Keep configs secret** - Each peer config is a private key
2. **Use named peers** - Easier to revoke access
3. **Rotate keys periodically** - Delete and regenerate configs
4. **Firewall everything else** - Only expose port 51820/udp
