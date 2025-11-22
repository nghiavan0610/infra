# NATS Production Setup

A production-ready NATS server setup with inline authentication, monitoring, and management utilities.

## 🚀 Quick Start

```bash
# Start NATS with authentication
./start-nats.sh

# Or use the management CLI
./nats-cli.sh start
```

## 📁 File Structure

```
nats/
├── config/
│   ├── nats.conf             # Main NATS configuration
│   ├── auth.conf.template    # Authentication template
│   └── auth.conf             # Generated auth (auto-created)
├── data/                     # JetStream data (auto-created)
├── logs/                     # NATS logs (auto-created)
├── backups/                  # Data backups (auto-created)
├── .env                      # Environment variables with credentials
├── docker-compose.yml        # Docker Compose configuration
├── start-nats.sh            # Production startup script
├── nats-cli.sh              # Management utility
├── README.md                # This file
└── ADDING_SERVICES.md       # Guide for adding new services
```

## 🔧 Configuration

### Authentication System

This setup uses a **template-based authentication system**:

1. **`.env`** - Contains all service credentials
2. **`auth.conf.template`** - Authentication template with variable placeholders
3. **`auth.conf`** - Generated configuration (auto-created from template)

### Adding New Services

To add a new service account:

1. **Add credentials to `.env`:**

   ```bash
   NEW_SERVICE_USER=new-service-nats
   NEW_SERVICE_PASS=secure_password_here
   ```

2. **Add service template to `auth.conf.template`:**

   ```hocon
   # New Service
   {
       user: "${NEW_SERVICE_USER}"
       password: "${NEW_SERVICE_PASS}"
       permissions = {
           publish = ["new-service.*", "events.new-service.*"]
           subscribe = ["*.query.*", "events.*", "_INBOX.*"]
       }
   },
   ```

3. **Restart NATS:**
   ```bash
   ./start-nats.sh
   ```

📖 **Detailed Guide:** See `ADDING_SERVICES.md` for complete examples and permission templates.## 🛠️ Management Commands

```bash
# Start/Stop
./nats-cli.sh start         # Start NATS with auth
./nats-cli.sh stop          # Stop NATS
./nats-cli.sh restart       # Restart NATS

# Monitoring
./nats-cli.sh status        # Show status
./nats-cli.sh logs          # Follow logs
./nats-cli.sh monitor       # Start with monitoring UI
./nats-cli.sh health        # Comprehensive health check

# Data Management
./nats-cli.sh backup        # Backup JetStream data
./nats-cli.sh clean         # Clean all data (dangerous!)

# Authentication
./nats-cli.sh test-auth     # Test auth configuration
```

## 🔗 Service Endpoints

- **NATS Client**: `nats://localhost:4222`
- **HTTP Monitoring**: `http://localhost:8222`
- **Surveyor UI**: `http://localhost:7777` (when monitoring profile is enabled)

## 🔐 Authentication

### Service Permissions

| Service              | Publish                                                                | Subscribe                                                                              |
| -------------------- | ---------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| teacher-service      | `teacher.*`, `events.teacher.*`, `notifications.*`                     | `user.query.*`, `course.query.*`, `events.user.*`, `events.course.*`, `_INBOX.*`       |
| user-service         | `user.*`, `events.user.*`, `notifications.*`                           | `teacher.query.*`, `course.query.*`, `events.teacher.*`, `events.course.*`, `_INBOX.*` |
| course-service       | `course.*`, `events.course.*`, `notifications.*`                       | `user.query.*`, `teacher.query.*`, `events.user.*`, `events.teacher.*`, `_INBOX.*`     |
| notification-service | `notifications.email.*`, `notifications.sms.*`, `notifications.push.*` | `notifications.*`, `events.*`                                                          |

### Client Connection Example

```javascript
// JavaScript/Node.js
import { connect } from "nats";

const nc = await connect({
  servers: "nats://localhost:4222",
  user: "teacher-service",
  pass: "teacher-secure-2024",
});

// Publish (allowed for teacher-service)
nc.publish("teacher.created", JSON.stringify({ id: 123, name: "John" }));

// Subscribe (allowed for teacher-service)
const sub = nc.subscribe("user.query.get");
for await (const msg of sub) {
  console.log("Received:", msg.string());
}
```

**Note**: Update the credentials in `config/nats.conf` before using in production!

## 🏗️ Production Features

- ✅ **Authentication & Authorization** - Inline account-based security
- ✅ **JetStream** - Message persistence and streaming
- ✅ **Health Checks** - Container and service health monitoring
- ✅ **Resource Limits** - Memory and CPU constraints
- ✅ **Logging** - Structured logging with rotation
- ✅ **Monitoring** - HTTP metrics and optional Surveyor UI
- ✅ **Backup/Restore** - Data management utilities
- ✅ **Simplified Config** - All-in-one configuration file

## 🔍 Troubleshooting

### Check NATS Status

```bash
./nats-cli.sh status
./nats-cli.sh health
```

### View Logs

```bash
./nats-cli.sh logs
```

### Test Authentication

```bash
./nats-cli.sh test-auth
```

### Configuration Issues

```bash
# Check configuration syntax
docker exec nats cat /etc/nats/nats.conf

# Restart with debug logs
docker-compose down && docker-compose up -d
```

## 📊 Monitoring

### Built-in HTTP Monitoring

- URL: `http://localhost:8222`
- Endpoints: `/healthz`, `/connz`, `/subsz`, `/routez`

### Optional Surveyor Dashboard

```bash
./nats-cli.sh monitor
# Then visit: http://localhost:7777
```

## 🔄 Updates

To update NATS version, edit `docker-compose.yml`:

```yaml
image: nats:2.11-alpine # Change version here
```

Then restart:

```bash
./nats-cli.sh restart
```
