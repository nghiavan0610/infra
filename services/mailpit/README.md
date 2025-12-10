# Mailpit - Email Testing

Catches all outgoing emails for testing. No emails are actually sent externally.

## Quick Start

```bash
cp .env.example .env
docker compose up -d
```

## Access

| Service | URL/Port | Description |
|---------|----------|-------------|
| Web UI | http://localhost:8025 | View caught emails |
| SMTP | localhost:1025 | Send emails here |

## Configure Your App

Point your application's SMTP settings to Mailpit:

### Node.js (Nodemailer)

```javascript
const transporter = nodemailer.createTransport({
  host: 'localhost',  // or host.docker.internal from Docker
  port: 1025,
  secure: false,
});
```

### Python (Django)

```python
EMAIL_HOST = 'localhost'  # or host.docker.internal
EMAIL_PORT = 1025
EMAIL_USE_TLS = False
```

### Go

```go
smtp.SendMail("localhost:1025", nil, from, to, msg)
```

### Laravel

```env
MAIL_MAILER=smtp
MAIL_HOST=host.docker.internal
MAIL_PORT=1025
MAIL_ENCRYPTION=null
```

## From Docker Containers

If your app runs in Docker, use:

```
SMTP_HOST=host.docker.internal
SMTP_PORT=1025
```

Or connect to the same network:

```yaml
services:
  your-app:
    networks:
      - traefik-public

networks:
  traefik-public:
    external: true
```

Then use `mailpit:1025` as SMTP server.

## Features

- **Catch all emails** - Nothing sent externally
- **Web UI** - Search, view HTML/text, attachments
- **API** - Integrate with tests
- **Persistent storage** - Emails survive restarts

## API Examples

```bash
# List messages
curl http://localhost:8025/api/v1/messages

# Search
curl "http://localhost:8025/api/v1/search?query=subject:test"

# Delete all
curl -X DELETE http://localhost:8025/api/v1/messages
```

## Testing Workflow

1. Configure app to send to `localhost:1025`
2. Trigger email in your app (signup, password reset, etc.)
3. Check http://localhost:8025 to see the email
4. Verify content, links, formatting

## Production Note

**Mailpit is for testing only!**

For production emails, use:
- SendGrid
- AWS SES
- Mailgun
- Postmark
- Self-hosted: Postal, Mailu
