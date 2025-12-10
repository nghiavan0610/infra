# Plausible Analytics

Privacy-friendly, lightweight web analytics - Google Analytics alternative.

## Quick Start

```bash
# Generate secret keys
echo "PLAUSIBLE_SECRET_KEY=$(openssl rand -base64 48)" >> .env
echo "PLAUSIBLE_TOTP_KEY=$(openssl rand -base64 32)" >> .env
echo "PLAUSIBLE_DB_PASSWORD=$(openssl rand -hex 16)" >> .env

# Start Plausible
docker compose up -d

# Wait for initialization (first start takes ~60 seconds)
docker compose logs -f plausible
```

## First Setup

1. Open http://localhost:8000
2. Create admin account
3. Add your first website

## Add Tracking Script

Add to your website's `<head>`:

```html
<script defer data-domain="yourdomain.com" src="http://localhost:8000/js/script.js"></script>
```

For production with custom domain:
```html
<script defer data-domain="yourdomain.com" src="https://analytics.yourdomain.com/js/script.js"></script>
```

## Features

- **Privacy-Friendly** - No cookies, GDPR compliant by default
- **Lightweight** - < 1KB tracking script
- **Simple Dashboard** - One-page overview
- **Real-time** - Live visitor count
- **Goals** - Track conversions and events
- **Funnels** - Conversion path analysis
- **Custom Properties** - Segment by custom data

## Tracking Options

### Standard Script
```html
<script defer data-domain="example.com" src="/js/script.js"></script>
```

### With Extensions
```html
<!-- Track outbound links -->
<script defer data-domain="example.com" src="/js/script.outbound-links.js"></script>

<!-- Track file downloads -->
<script defer data-domain="example.com" src="/js/script.file-downloads.js"></script>

<!-- Track 404 pages -->
<script defer data-domain="example.com" src="/js/script.404.js"></script>

<!-- All extensions -->
<script defer data-domain="example.com" src="/js/script.outbound-links.file-downloads.js"></script>
```

### Custom Events
```javascript
// Track custom event
plausible('Signup', {props: {plan: 'Premium'}});

// Track purchase
plausible('Purchase', {props: {product: 'T-Shirt'}, revenue: {currency: 'USD', amount: 29.99}});
```

## Configuration

Edit `.env`:
- `PLAUSIBLE_BASE_URL` - Public URL for Plausible (required)
- `PLAUSIBLE_SECRET_KEY` - Encryption key (generate with openssl)
- `PLAUSIBLE_DISABLE_REGISTRATION` - Disable signup after setup

## Goals

Track specific actions:

1. Go to Site Settings > Goals
2. Add goal (pageview or custom event)
3. View conversions in dashboard

### Pageview Goals
Track visits to specific pages like `/signup` or `/thank-you`.

### Custom Event Goals
Track button clicks, form submissions, etc.

```javascript
// Button click
document.getElementById('signup-btn').addEventListener('click', function() {
    plausible('Signup Click');
});
```

## API Access

Generate API token in Settings > API Keys.

```bash
# Get stats
curl "http://localhost:8000/api/v1/stats/aggregate" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -d "site_id=example.com" \
  -d "period=30d" \
  -d "metrics=visitors,pageviews"
```

## Import from Google Analytics

1. Go to Site Settings > Import Data
2. Follow Google Analytics import wizard
3. Historical data will be imported

## Multi-Site

Add multiple websites:
1. Click "Add Site" in dashboard
2. Add tracking script to each site
3. Switch between sites in dropdown

## Security

After setup:
1. Disable registration:
   ```bash
   PLAUSIBLE_DISABLE_REGISTRATION=true
   ```
2. Restart: `docker compose up -d`

## Exposing via Traefik

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.plausible.rule=Host(`analytics.example.com`)"
  - "traefik.http.routers.plausible.entrypoints=websecure"
  - "traefik.http.routers.plausible.tls.certresolver=letsencrypt"
```

Update `.env`:
```bash
PLAUSIBLE_BASE_URL=https://analytics.example.com
```

## Backup

```bash
# Backup PostgreSQL
docker exec plausible-db pg_dump -U plausible plausible > plausible-postgres.sql

# Backup ClickHouse (events data)
docker exec plausible-events-db clickhouse-client \
    --query "SELECT * FROM plausible_events.events FORMAT Native" > events.native
```

## Plausible vs Google Analytics

| Feature | Plausible | Google Analytics |
|---------|-----------|------------------|
| Privacy | No cookies, GDPR compliant | Requires cookie consent |
| Script size | < 1KB | ~45KB |
| Data ownership | Self-hosted | Google's servers |
| Learning curve | Simple | Complex |
| Cost | Self-hosted (free) | Free tier available |
| Features | Essential metrics | Comprehensive |

Plausible is ideal when you need simple, privacy-friendly analytics without the complexity of Google Analytics.
