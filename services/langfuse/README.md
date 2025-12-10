# LangFuse - LLM Observability Platform

Open-source observability & analytics for LLM applications.

## Features

| Feature | Description |
|---------|-------------|
| **Tracing** | Track LLM calls, chains, and agents |
| **Cost Tracking** | Monitor token usage and API costs |
| **Latency** | Response time analytics |
| **Prompts** | Version control for prompts |
| **Scores** | User feedback and quality metrics |
| **Datasets** | Test datasets for evaluation |
| **Playground** | Test prompts directly in UI |

## Prerequisites

- PostgreSQL (enabled in services.conf)
- Redis (optional but recommended)

## Setup

### 1. Configure

```bash
cp .env.example .env

# Generate secrets
echo "LANGFUSE_NEXTAUTH_SECRET=$(openssl rand -base64 32)" >> .env
echo "LANGFUSE_SALT=$(openssl rand -base64 32)" >> .env
echo "LANGFUSE_DB_PASS=$(openssl rand -base64 24)" >> .env

# Set PostgreSQL admin password (same as your postgres service)
echo "POSTGRES_PASSWORD=your_postgres_admin_password" >> .env
```

### 2. Start

```bash
docker compose up -d

# Check logs
docker logs -f langfuse
```

### 3. Create Account

1. Open http://localhost:3050
2. Click "Sign Up"
3. Create your admin account

### 4. Create API Keys

1. Go to Settings → API Keys
2. Create new API key
3. Save the Public Key and Secret Key

## Integration

### Python (LangChain)

```bash
pip install langfuse
```

```python
from langfuse import Langfuse
from langfuse.callback import CallbackHandler

# Initialize
langfuse = Langfuse(
    host="http://localhost:3050",  # or http://langfuse:3000 from Docker
    public_key="pk-lf-...",
    secret_key="sk-lf-..."
)

# Option 1: LangChain callback
from langchain_openai import ChatOpenAI
from langchain.schema import HumanMessage

handler = CallbackHandler(
    host="http://localhost:3050",
    public_key="pk-lf-...",
    secret_key="sk-lf-..."
)

llm = ChatOpenAI()
response = llm.invoke(
    [HumanMessage(content="Hello!")],
    config={"callbacks": [handler]}
)

# Option 2: Manual tracing
trace = langfuse.trace(name="my-trace")
generation = trace.generation(
    name="chat",
    model="gpt-4",
    input=[{"role": "user", "content": "Hello!"}],
)

# ... call your LLM ...

generation.end(output={"role": "assistant", "content": "Hi there!"})
langfuse.flush()
```

### Python (OpenAI directly)

```python
from langfuse.openai import openai

# Automatically traces all OpenAI calls
client = openai.OpenAI()

response = client.chat.completions.create(
    model="gpt-4",
    messages=[{"role": "user", "content": "Hello!"}],
)
```

### JavaScript/TypeScript

```bash
npm install langfuse
```

```typescript
import { Langfuse } from "langfuse";

const langfuse = new Langfuse({
  baseUrl: "http://localhost:3100",
  publicKey: "pk-lf-...",
  secretKey: "sk-lf-...",
});

// Create a trace
const trace = langfuse.trace({ name: "my-trace" });

// Log a generation
const generation = trace.generation({
  name: "chat",
  model: "gpt-4",
  input: [{ role: "user", content: "Hello!" }],
});

// ... call your LLM ...

generation.end({
  output: { role: "assistant", content: "Hi there!" },
});

await langfuse.flushAsync();
```

### Environment Variables (for your app)

```env
# Add to your backend .env
LANGFUSE_HOST=http://langfuse:3000
LANGFUSE_PUBLIC_KEY=pk-lf-...
LANGFUSE_SECRET_KEY=sk-lf-...
```

## Dashboard

### Traces View
- See all LLM calls with full context
- Filter by user, time, model, cost
- Drill down into individual traces

### Analytics
- Token usage over time
- Cost breakdown by model
- Latency percentiles
- Error rates

### Prompts
- Version control your prompts
- A/B test different versions
- Track which version performs best

## Production Configuration

### Enable HTTPS (Traefik)

```bash
# .env
LANGFUSE_TRAEFIK_ENABLE=true
LANGFUSE_DOMAIN=langfuse.example.com
LANGFUSE_URL=https://langfuse.example.com
```

### Disable Public Signup

```bash
# .env
LANGFUSE_DISABLE_SIGNUP=true
```

### Enable SSO

```bash
# .env - Google OAuth
LANGFUSE_GOOGLE_CLIENT_ID=your-client-id
LANGFUSE_GOOGLE_CLIENT_SECRET=your-client-secret

# .env - GitHub OAuth
LANGFUSE_GITHUB_CLIENT_ID=your-client-id
LANGFUSE_GITHUB_CLIENT_SECRET=your-client-secret
```

### S3 Storage (for large traces)

If you have very large traces, store them in S3 (Garage/MinIO):

```bash
# .env
LANGFUSE_S3_BUCKET=langfuse
LANGFUSE_S3_ENDPOINT=http://garage:3900
LANGFUSE_S3_ACCESS_KEY=your-access-key
LANGFUSE_S3_SECRET_KEY=your-secret-key
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Your LLM Application                                           │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐       │
│  │ Your Code   │ ──→ │ LangChain/  │ ──→ │ OpenAI/     │       │
│  │             │     │ LlamaIndex  │     │ Claude API  │       │
│  └──────┬──────┘     └─────────────┘     └─────────────┘       │
│         │                                                       │
│         │ langfuse.trace()                                      │
│         ▼                                                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  LangFuse (infra network)                               │   │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐           │   │
│  │  │ Web UI    │  │ Worker    │  │ API       │           │   │
│  │  │ :3100     │  │ (bg jobs) │  │ /api/*    │           │   │
│  │  └───────────┘  └───────────┘  └───────────┘           │   │
│  │         │              │              │                 │   │
│  │         └──────────────┴──────────────┘                 │   │
│  │                        │                                │   │
│  │                        ▼                                │   │
│  │              ┌───────────────────┐                      │   │
│  │              │ PostgreSQL        │                      │   │
│  │              │ (shared)          │                      │   │
│  │              └───────────────────┘                      │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Troubleshooting

### Database connection error

```bash
# Check PostgreSQL is running
docker logs postgres

# Verify database was created
docker exec -it postgres psql -U postgres -c "\l" | grep langfuse
```

### Traces not appearing

```python
# Make sure to flush before exit
langfuse.flush()  # sync
await langfuse.flushAsync()  # async
```

### High memory usage

Reduce worker concurrency or increase memory limit:
```bash
# .env
LANGFUSE_MEMORY_LIMIT=4G
```

## Backup

LangFuse data is stored in PostgreSQL. Use the infra backup system:

```bash
# Backup is automatic if backup=true in services.conf
# Manual backup:
cd /opt/infra/services/backup
./scripts/backup.sh
```

## API Reference

| Endpoint | Description |
|----------|-------------|
| `POST /api/public/ingestion` | Ingest traces |
| `GET /api/public/traces` | List traces |
| `GET /api/public/traces/:id` | Get trace |
| `GET /api/public/health` | Health check |
| `GET /api/public/metrics` | Prometheus metrics |

## Resources

- [LangFuse Docs](https://langfuse.com/docs)
- [Python SDK](https://langfuse.com/docs/sdk/python)
- [JS/TS SDK](https://langfuse.com/docs/sdk/typescript)
- [LangChain Integration](https://langfuse.com/docs/integrations/langchain)
- [OpenAI Integration](https://langfuse.com/docs/integrations/openai)
