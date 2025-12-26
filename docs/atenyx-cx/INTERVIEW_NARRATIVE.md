# CX Genie - Interview Narrative Style

---

## Opening - Tell Me About Your Project

Let me see... so at CX Genie, I was one of the core backend developers building this AI-powered customer support platform. Basically, think of it as a system where businesses can create their own AI chatbots that actually understand their products and services — not just generic responses, but real contextual answers based on their documentation, FAQs, website content, whatever they upload.

The interesting part is that these bots can be deployed across multiple channels — Facebook Messenger, WhatsApp, Viber, Telegram, Instagram DMs, email, and even a web widget they can embed on their website. So a customer asks a question on Facebook, and the same AI that knows everything about that business responds intelligently. And if the AI can't handle it, it seamlessly hands off to a human agent.

We had businesses with thousands of daily conversations happening simultaneously across all these channels, so... yeah, scale was definitely something we had to think about from day one.

---

## System Architecture Overview

Let me draw the high-level architecture first:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              EXTERNAL CHANNELS                               │
│  Facebook │ WhatsApp │ Telegram │ Viber │ Instagram │ Email │ Web Widget   │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼ Webhooks
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AWS ALB (Load Balancer)                         │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
              ┌───────────────────────┼───────────────────────┐
              ▼                       ▼                       ▼
┌──────────────────────┐ ┌──────────────────────┐ ┌──────────────────────┐
│   cxgenie-be (1)     │ │   cxgenie-be (2)     │ │   cxgenie-be (3)     │
│   NestJS + Socket.IO │ │   NestJS + Socket.IO │ │   NestJS + Socket.IO │
└──────────────────────┘ └──────────────────────┘ └──────────────────────┘
              │                       │                       │
              └───────────────────────┼───────────────────────┘
                                      │
        ┌─────────────────────────────┼─────────────────────────────┐
        │                             │                             │
        ▼                             ▼                             ▼
┌───────────────┐           ┌─────────────────┐           ┌─────────────────┐
│  PostgreSQL   │           │     Redis       │           │ cxgenie-core-ai │
│  Master/Slave │           │ Cache + Queues  │           │    FastAPI      │
└───────────────┘           └─────────────────┘           └─────────────────┘
                                                                   │
                                                                   ▼
                                                          ┌─────────────────┐
                                                          │     Zilliz      │
                                                          │  Vector Search  │
                                                          └─────────────────┘
```

So, in terms of architecture, we went with a microservices approach, but not the crazy over-engineered kind with 50 services — we kept it practical. Four main services.

**cxgenie-be** is our main backend written in NestJS with TypeScript. This is basically the brain of the whole operation — it handles all the REST APIs (about 200+ endpoints), WebSocket connections for real-time chat, all the business logic, database operations, everything. When the frontend or mobile app needs anything, they talk to this service. We structured it with NestJS modules — about 50+ modules actually, each handling a specific domain: bots, messages, chat sessions, customers, knowledge bases, subscriptions, and so on. Each module follows the pattern: Controller → Service → Repository → Entity.

**cxgenie-core-ai** is in Python using FastAPI. You know, for AI stuff, Python just makes more sense because of the ecosystem — LangChain, all the embedding libraries, vector database clients. This service handles the actual AI magic: generating embeddings, searching the vector database, calling OpenAI or Gemini or Claude for responses, streaming those responses back. It exposes about 15 REST endpoints that cxgenie-be calls internally. We use async/await throughout with asyncio and uvicorn as ASGI server, which lets us handle multiple AI requests concurrently without blocking.

**cxgenie-email-service** is also NestJS, which handles all email-related stuff — parsing incoming emails using libraries like mailparser, sending responses via SMTP or SendGrid, managing email threads with proper In-Reply-To and References headers. Email is surprisingly complex because you have to deal with threading, attachments, HTML parsing, stripping signatures... it's a whole thing.

**cxgenie-launch-darkly** is our feature flag service. I actually implemented this one myself. It's a wrapper around LaunchDarkly that caches flags in Redis and pushes real-time updates to the dashboard via Socket.IO.

---

## Inter-Service Communication

Now about the communication pattern between services — here's the thing, we don't have an API Gateway. The frontend calls cxgenie-be directly, and then cxgenie-be orchestrates calls to the other services internally via HTTP.

```
Frontend/Mobile App
        │
        ▼ REST API + WebSocket
┌───────────────────────────────────────────────────────────┐
│                       cxgenie-be                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │
│  │ Controllers │──│  Services   │──│ Repositories│       │
│  └─────────────┘  └─────────────┘  └─────────────┘       │
│         │                │                               │
│         │    HTTP Calls (Axios + Circuit Breaker)        │
│         ▼                ▼                ▼              │
│  ┌────────────┐  ┌──────────────┐  ┌────────────────┐   │
│  │ core-ai    │  │ email-service│  │ launch-darkly  │   │
│  └────────────┘  └──────────────┘  └────────────────┘   │
└───────────────────────────────────────────────────────────┘
```

For inter-service calls, we use Axios with several resilience patterns:

**Retry Logic** — If a call to core-ai fails, we retry up to 3 times with exponential backoff (1s, 2s, 4s). We only retry on 5xx errors and network failures, not on 4xx which are client errors.

**Circuit Breaker** — We implemented a simple circuit breaker. If core-ai fails 5 times in a row within 30 seconds, we "open" the circuit and fail fast for the next 60 seconds without even trying. This prevents cascading failures when a downstream service is down.

**Timeout** — Each inter-service call has a timeout. For AI processing, it's 30 seconds (LLM can be slow). For email service, it's 10 seconds. If it takes longer, we timeout and either retry or fail gracefully.

We considered adding Kong or AWS API Gateway, but honestly, for our scale and team size, it would've added complexity without much benefit. The main backend already handles JWT authentication, rate limiting with Redis token bucket, request validation... all that. Maybe if we grew to 10+ services we'd revisit, but you know, YAGNI, right?

---

## Database Design and Data Layer

For the database, we're on PostgreSQL with about 118 models and over 500 migrations. Yeah, it's a lot — we have bots, chat sessions, messages, customers, knowledge bases, documents, social account connections, subscriptions, usage tracking, audit logs... the whole SaaS stack basically.

Here's a simplified ERD of the core entities:

```
┌─────────────┐       ┌─────────────────┐       ┌─────────────────┐
│  Workspace  │──1:N──│      Bot        │──1:N──│   ChatSession   │
│─────────────│       │─────────────────│       │─────────────────│
│ id (UUID)   │       │ id (UUID)       │       │ id (UUID)       │
│ name        │       │ workspace_id    │       │ bot_id          │
│ plan_id     │       │ name            │       │ customer_id     │
│ created_at  │       │ ai_model        │       │ channel         │
└─────────────┘       │ temperature     │       │ status          │
                      │ system_prompt   │       │ created_at      │
                      │ handoff_enabled │       └────────┬────────┘
                      └────────┬────────┘                │
                               │                         │
                      ┌────────┴────────┐       ┌────────┴────────┐
                      │ BotKnowledgeBase│       │     Message     │
                      │─────────────────│       │─────────────────│
                      │ bot_id          │       │ id (UUID)       │
                      │ knowledge_base_id│      │ session_id      │
                      └────────┬────────┘       │ role (user/bot) │
                               │                │ content         │
                      ┌────────┴────────┐       │ created_at      │
                      │  KnowledgeBase  │       └─────────────────┘
                      │─────────────────│
                      │ id (UUID)       │
                      │ name            │
                      │ type            │
                      └────────┬────────┘
                               │
                      ┌────────┴────────┐
                      │    Document     │──1:N──│  DocumentChunk  │
                      │─────────────────│       │─────────────────│
                      │ id (UUID)       │       │ id (UUID)       │
                      │ knowledge_base_id│      │ document_id     │
                      │ filename        │       │ content         │
                      │ status          │       │ embedding_id    │
                      └─────────────────┘       └─────────────────┘
```

We use Sequelize as our ORM with sequelize-typescript for decorator-based model definitions. Each module has its own service that injects Sequelize models. We use the repository pattern — services call model methods for queries. For performance-critical queries, we drop down to raw SQL using `sequelize.query()`.

**Connection pooling** is crucial at our scale. We configure Sequelize with a pool of max 25 connections per instance, min 5 idle connections, and connection timeout of 10 seconds. With three backend instances, that's up to 75 connections to the primary database, which is within PostgreSQL's default 100 connection limit with headroom for admin connections.

**For read scaling**, we have master-slave replication. Write operations go to the master, but heavy read operations — like fetching chat history, analytics queries, listing conversations — go to read replicas. We handle this with Sequelize's replication configuration:

```typescript
// Sequelize configuration with replication
{
  dialect: 'postgres',
  replication: {
    read: [
      { host: 'slave1.db.com', username: 'user', password: 'pass' },
      { host: 'slave2.db.com', username: 'user', password: 'pass' },
    ],
    write: { host: 'master.db.com', username: 'user', password: 'pass' },
  },
  pool: {
    max: 25,           // max connections
    min: 5,            // min idle connections
    idle: 30000,
    acquire: 10000,
  },
}
```

**Indexing strategy** — we're careful about indexes because they speed up reads but slow down writes. Every foreign key is indexed, obviously. We have composite indexes on frequently queried combinations:

- `(bot_id, created_at)` for fetching recent conversations per bot
- `(chat_session_id, created_at)` for message ordering
- `(workspace_id, status)` for filtering active conversations
- `(customer_id, channel)` for finding customer across channels

For full-text search on message content, we use PostgreSQL's tsvector with GIN indexes rather than LIKE queries. Much faster for text search.

**Soft deletes** — most entities use soft delete with a `deleted_at` timestamp. This is important for audit trails and data recovery. We have a global scope that excludes soft-deleted records by default, but we can include them when needed for auditing.

**Migration strategy** — we run migrations in CI/CD before deploying new code. For risky migrations (adding NOT NULL columns, dropping tables), we do it in phases: first deploy code that handles both states, then run migration, then deploy code that only handles new state.

---

## Multi-Tenancy Architecture

So we're a SaaS platform, which means multi-tenancy is important. We use the "shared database, shared schema" approach with workspace isolation at the application level.

Every tenant-specific table has a `workspace_id` column. All queries include `WHERE workspace_id = :workspaceId` to ensure data isolation. We enforce this at multiple levels:

**API Level** — The JWT token contains the workspace_id. In a NestJS guard, we extract it and attach it to the request context. Every service method has access to it.

**Repository Level** — We have a base repository class that automatically adds workspace filtering:

```typescript
abstract class WorkspaceScopedRepository<T> {
  async findAll(workspaceId: string): Promise<T[]> {
    return this.repository.find({
      where: { workspaceId, deletedAt: null }
    });
  }

  async findById(workspaceId: string, id: string): Promise<T> {
    return this.repository.findOne({
      where: { id, workspaceId, deletedAt: null }
    });
  }
}
```

**Audit Trail** — Every mutation (create, update, delete) is logged with the user ID, workspace ID, timestamp, and what changed. This is crucial for enterprise customers who need compliance.

---

## The Bot Architecture - This is Important

So one thing I want to clarify because it confused even some of our team at first — when I say "bot," I don't mean like a worker process or a running container. A bot in our system is a database entity. It's basically a configuration bundle stored in the `bots` table.

Let me describe the schema. Each bot record has: `id` (UUID primary key), `name`, `workspace_id` (foreign key to the workspace that owns it), `ai_model` (which could be gpt-4, gpt-3.5-turbo, claude-3, gemini-pro), `temperature` setting (0.0 to 1.0), `system_prompt` (the personality and instructions), `handoff_enabled` (boolean for human takeover), `handoff_threshold` (confidence score below which to hand off), and timestamps.

Then we have a many-to-many relationship with knowledge bases through a `bot_knowledge_bases` junction table. A bot can have multiple knowledge bases attached, and a knowledge base can be shared across bots.

**The channel-to-bot routing** works through the `social_accounts` table. When a business connects their Facebook page or WhatsApp number, we create a record in `social_accounts` with fields like: `id`, `channel` (enum: facebook, whatsapp, telegram, etc.), `channel_account_id` (the page ID or phone number), `bot_id` (foreign key to which bot handles this channel), `credentials` (encrypted OAuth tokens or API keys using AES-256), and `status`.

So when a message comes in — say from Facebook Messenger — the webhook payload contains the page ID. We query: `SELECT * FROM social_accounts WHERE channel = 'facebook' AND channel_account_id = :pageId`. That gives us the `bot_id`, and now we know exactly which bot configuration to use. Then we load that bot's knowledge bases, system prompt, everything, and process the message accordingly.

So it's not like we spin up a container per bot or anything. One backend service handles all bots, all channels. It just queries the right configuration based on the incoming message. This is actually nice for scaling because we can horizontally scale the backend and any instance can handle any bot's messages. It's stateless — all state is in the database and Redis.

---

## Message Flow Architecture

Let me walk you through exactly what happens when a message comes in, because this is really the core of the system.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                            MESSAGE FLOW (Total: ~3-5s)                        │
└──────────────────────────────────────────────────────────────────────────────┘

Facebook Webhook ──▶ Validate Signature ──▶ Parse Payload ──▶ Queue Job ──▶ 200 OK
     (0ms)              (2ms)                  (3ms)           (5ms)        (10ms)
                                                                  │
                                                                  ▼
                                               ┌──────────────────────────────┐
                                               │      Bull Queue (Redis)      │
                                               └──────────────────────────────┘
                                                                  │
                                                                  ▼
                                               ┌──────────────────────────────┐
                                               │ Acquire Distributed Lock     │
                                               │ SETNX lock:session:{id}      │
                                               └──────────────────────────────┘
                                                                  │
                                                                  ▼
                    ┌─────────────────────────────────────────────────────────┐
                    │              PARALLEL CONTEXT LOADING (~50ms)            │
                    │  ┌───────────┐  ┌───────────┐  ┌───────────┐           │
                    │  │ Load Bot  │  │Load/Create│  │  Load     │           │
                    │  │  Config   │  │ Customer  │  │ History   │           │
                    │  └───────────┘  └───────────┘  └───────────┘           │
                    └─────────────────────────────────────────────────────────┘
                                                                  │
                                                                  ▼
                                               ┌──────────────────────────────┐
                                               │   HTTP to cxgenie-core-ai    │
                                               │   RAG + LLM (~2-3s)          │
                                               └──────────────────────────────┘
                                                                  │
                                                                  ▼ Streaming
                    ┌─────────────────────────────────────────────────────────┐
                    │              PARALLEL DELIVERY (per paragraph)           │
                    │  ┌───────────┐  ┌───────────┐  ┌───────────┐           │
                    │  │ Save to   │  │ Emit via  │  │ Send to   │           │
                    │  │ Database  │  │ Socket.IO │  │ Channel   │           │
                    │  └───────────┘  └───────────┘  └───────────┘           │
                    └─────────────────────────────────────────────────────────┘
                                                                  │
                                                                  ▼
                                               ┌──────────────────────────────┐
                                               │  Release Lock + Complete Job │
                                               └──────────────────────────────┘
```

**Step 1: Webhook Reception (5-10ms)** — A message arrives at our webhook endpoint, let's say `/webhooks/facebook`. The controller validates the Facebook signature using HMAC-SHA256 (they send X-Hub-Signature header), parses the payload, extracts the message content and sender ID.

**Step 2: Fast Acknowledgment (10ms total)** — Here's the key insight: we don't process the message in the request handler. Facebook expects a 200 response within 20 seconds or they'll retry (and they get aggressive with retries). AI processing can take 3-5 seconds. So we immediately push a job to Bull queue and return 200. The webhook handler does: validate → parse → `queue.add('process-message', payload)` → return 200.

**Step 3: Queue Processing** — Bull picks up the job from Redis. The processor first checks if this conversation is already being processed. If not, it acquires a distributed lock with `SETNX lock:conversation:{sessionId} {instanceId} EX 30`.

**Step 4: Context Loading (~50ms)** — We load the bot configuration, the customer record (create if new), the chat session (create if new conversation), and the last 10 messages for context. This involves multiple database queries, so we use Promise.all where possible to run them in parallel.

**Step 5: AI Processing (~2-3s)** — We call cxgenie-core-ai with the message, context, bot configuration. This service does the RAG pipeline — retrieve relevant knowledge, generate response with LLM, stream it back.

**Step 6: Response Delivery** — As we receive streamed paragraphs, we do three things in parallel per paragraph: save to database as a message record, emit via Socket.IO for web widget users, and send back to the original channel (Facebook API, WhatsApp API, etc.).

**Step 7: Cleanup** — Release the distributed lock with `DEL lock:conversation:{sessionId}`, mark the Bull job as complete, trigger any post-processing (analytics events, webhook notifications to the business).

---

## RAG Pipeline - The AI Part

Okay, so the RAG pipeline — Retrieval Augmented Generation — this is really the core of what makes our chatbots smart instead of just... generic ChatGPT wrappers.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        RAG PIPELINE (Total: ~2-3s)                            │
└──────────────────────────────────────────────────────────────────────────────┘

User Question: "What's your return policy for electronics?"
        │
        ▼
┌───────────────────────────────────────┐
│ Step 1: Search Term Extraction (~200ms)│
│ Model: gpt-3.5-turbo (cheaper)        │
│ Output: ["return policy", "electronics"]│
└───────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────┐
│ Step 2: Embedding Generation (~150ms)  │
│ Model: text-embedding-3-large         │
│ Output: [0.123, -0.456, ...] (3072-dim)│
└───────────────────────────────────────┘
        │
        ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                    Step 3: Parallel Vector Search (~100ms)                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │  Documents  │  │  Websites   │  │    FAQs     │  │  Snippets   │         │
│  │  (top 5)    │  │  (top 5)    │  │  (top 5)    │  │  (top 5)    │         │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘         │
│                    Using asyncio.gather() for parallelism                    │
└──────────────────────────────────────────────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────┐
│ Step 4: Merge & Rank (~10ms)          │
│ - Combine 20 candidates               │
│ - FAQ boost: 1.2x                     │
│ - Recency boost: 1.1x                 │
│ - Take top 5-8 chunks                 │
└───────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────┐
│ Step 5: Prompt Assembly (~5ms)        │
│ - System prompt (bot personality)     │
│ - Retrieved context (XML wrapped)     │
│ - Chat history (last 10 messages)     │
│ - Current question                    │
│ Total: ~3000-4000 tokens             │
└───────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────┐
│ Step 6: LLM Streaming (~2s)           │
│ Model: gpt-4 / claude-3 / gemini-pro  │
│ Stream tokens → Buffer → Paragraphs   │
└───────────────────────────────────────┘
        │
        ▼
   Streamed Response to User
```

When a customer asks a question, here's what actually happens in cxgenie-core-ai:

**Step 1: Search Term Extraction (~200ms)** — We take their question and send it to an LLM with a specific prompt to extract search terms. Like if someone asks "What's your return policy for electronics purchased online?", we extract terms like "return policy," "electronics," "online purchase." We use gpt-3.5-turbo for this — it's cheaper and just as good for extraction. This is better than just using the raw question because customers often phrase things weirdly or include irrelevant words like "hey", "um", "I was wondering".

**Step 2: Embedding Generation (~150ms)** — Then we generate an embedding for the query — a 3072-dimension vector using OpenAI's text-embedding-3-large model. We migrated to this from ada-002 because the larger dimensions give better semantic matching, about 15% improvement in our benchmarks on domain-specific retrieval tasks.

**Step 3: Parallel Vector Search (~100ms)** — Here's where it gets interesting. We do four parallel searches in our vector database, which is Zilliz, the managed version of Milvus. We search across:

- Document chunks from uploaded PDFs and docs (partition: `documents`)
- Website content we've crawled (partition: `websites`)
- FAQ entries (partition: `faqs`)
- Custom knowledge snippets (partition: `snippets`)

We use `asyncio.gather()` to run all four searches in parallel. Each search uses cosine similarity with a limit of 5 results, so we get up to 20 candidates. Parallel execution means this takes 100ms total instead of 400ms sequentially.

**Step 4: Merge and Rank (~10ms)** — We merge all those results using a combination of vector similarity scores and some heuristics. FAQ matches get a 1.2x boost because they're usually more authoritative — someone explicitly wrote that answer. Recent documents get a slight boost over old ones. We normalize scores and take the top 5-8 chunks that fit within our context window.

**Step 5: Prompt Assembly (~5ms)** — We build the final prompt with:

```
<system>
{bot.system_prompt}
</system>

<context>
{retrieved_chunks_in_xml_format}
</context>

<history>
{last_10_messages}
</history>

<question>
{current_question}
</question>
```

We're careful about token counting here — we use tiktoken to count and truncate if needed. Max context is about 4000 tokens for the prompt to leave room for the response.

**Step 6: LLM Streaming (~2s)** — Finally, we call the LLM (OpenAI, Anthropic, or Google depending on bot config) with streaming enabled. We use async generators to yield tokens as they arrive, buffer into paragraphs, and emit.

The whole thing takes maybe 2-3 seconds for a good response, but we stream it so users see text appearing immediately.

---

## AI Handoff Detection - When to Escalate to Humans

So one of the trickier AI UX problems is knowing when the bot should admit it can't help and escalate to a human agent. If the bot guesses wrong, customers get frustrated. If it escalates everything, what's the point of having a bot?

**LLM Self-Evaluation**

We built this into the prompt itself. When the LLM generates a response, we don't just ask it to answer — we ask it to evaluate its own confidence. The response includes a field called `have_enough_information_for_reply` with a value of either `"YES"` or `"NO"`.

In our prompt template (`prompt_const.py`), we explicitly tell the LLM: set this to `"NO"` if:
- Your reply doesn't directly answer the question
- You'd need to ask for more information to properly answer
- You're apologizing for not being able to help
- The question is outside the knowledge base scope

So the AI is doing metacognition — evaluating its own answer quality.

**Configurable Fallback Behavior**

When we get `"NO"` from the AI, what happens next is configurable per bot through the `type_reply_unknown` setting in the bot configuration. There are three options:

```typescript
export enum TypeReplyUnknown {
  INPUT_ANSWER = 'INPUT_ANSWER',   // Use pre-configured fallback message
  AI_GENERATE = 'AI_GENERATE',      // Let AI respond anyway
  NO_REPLY = 'NO_REPLY',            // Don't reply, trigger handoff
}
```

- `INPUT_ANSWER` — Fall back to a pre-configured message like "I'm sorry, I don't have that information. Would you like to speak with a human agent?" Professional and predictable.

- `AI_GENERATE` — Let the AI respond anyway even if uncertain. Some businesses prefer a partial answer over no answer.

- `NO_REPLY` — Stay silent and immediately trigger the handoff flow.

**Human Agent Notification**

When `NO_REPLY` is configured, we emit a `BOT_NOT_ENOUGH_DATA` event through our notification system:

```typescript
export enum NotificationEventForBot {
  BOT_NOT_ENOUGH_DATA = 'BOT_NOT_ENOUGH_DATA',  // Alert human agents
}
```

This event lights up the agent dashboard with the conversation context — the question that stumped the bot, what the AI was about to say, customer info. So when a human picks it up, they have full context.

**Why This Design?**

The key insight is that confidence detection shouldn't be a separate classifier — the model generating the answer is the best judge of its quality. And making it configurable per bot means businesses can tune behavior based on their customer service philosophy. Some want aggressive AI coverage; others want conservative handoff. We support both.

---

## Streaming - How We Handle It

So about streaming — you know how ChatGPT shows text appearing word by word? We do something similar but with a twist. Token-by-token streaming creates a lot of Socket.IO events. When you have thousands of concurrent chats, that's a lot of overhead — network packets, event parsing, state updates on the client.

What we do instead is **paragraph-based buffering**. Here's the implementation:
Buffer tokens until paragraph complete, then emit

```python
async def stream_with_buffering(response_stream):
    """Buffer tokens and yield complete paragraphs."""
    buffer = ""
    async for token in response_stream:
        buffer += token
        if "\n\n" in buffer:
            paragraphs = buffer.split("\n\n")
            # Yield all complete paragraphs
            for p in paragraphs[:-1]:
                yield p + "\n\n"
            # Keep incomplete paragraph in buffer
            buffer = paragraphs[-1]
    # Yield remaining content
    if buffer:
        yield buffer
```

The NestJS backend receives these paragraph chunks via HTTP streaming (we use axios with `responseType: 'stream'`), and for each chunk, we do three things in parallel:

```typescript
async function handleStreamChunk(chunk: string, session: ChatSession) {
  await Promise.all([
    // 1. Save to database
    this.messageRepository.save({
      sessionId: session.id,
      role: 'assistant',
      content: chunk,
      isPartial: true,
    }),

    // 2. Emit via Socket.IO
    this.socketGateway.emitToRoom(
      `session:${session.id}`,
      'message:chunk',
      { content: chunk }
    ),

    // 3. Send to channel (Facebook, WhatsApp, etc.)
    this.channelService.sendMessage(session.channel, session.channelId, chunk),
  ]);
}
```

This reduces our socket events by like 90% compared to token-by-token. The UX is slightly different — users see paragraphs appear at once instead of character by character — but honestly, most users don't notice, and the performance improvement is significant. We measured: average response has maybe 4-5 paragraphs, so 5 socket events instead of 500+ tokens.

---

## Handling Concurrency - No Traditional Workers

So this is a question I've gotten before: how do we handle high concurrency without traditional worker processes like Celery or Sidekiq?

The answer is... Node.js event loop plus Bull queues plus horizontal scaling. Let me break it down technically.

**Node.js Event Loop** — Node.js is single-threaded but non-blocking. When we make a database query or HTTP call, Node doesn't wait. It registers a callback and moves on. When the I/O completes, the callback fires. This means a single Node process can handle thousands of concurrent connections because it's never blocking on I/O. For our use case — lots of I/O (database, Redis, HTTP to AI service) and not much CPU — this is perfect.

**Bull Queue Architecture** — Bull is our job queue, backed by Redis. We have about 26 different queues:

- `ai-processing` — incoming messages to process (concurrency: 10)
- `message-delivery` — sending responses to channels (concurrency: 20)
- `email-send` — sending email responses (concurrency: 5)
- `webhook-delivery` — notifying businesses of events (concurrency: 10)
- `knowledge-extraction` — processing uploaded documents (concurrency: 3)
- `website-crawl` — crawling and indexing websites (concurrency: 2)
- And about 20 more for various async tasks

Each queue has its own concurrency setting. For `ai-processing`, we set concurrency to 10 per instance — meaning each instance processes up to 10 AI messages in parallel. We tune these based on the nature of the work and downstream service limits.

**Message Ordering Problem** — Here's a tricky part. For a single conversation, messages need to be processed in order — you can't have response 2 come before response 1. But across different conversations, we want maximum parallelism.

So we implement **per-conversation serial processing with global parallelism**. When a message job starts, we check Redis:

```typescript
async function acquireLock(sessionId: string): Promise<boolean> {
  const lockKey = `lock:conversation:${sessionId}`;
  // SETNX returns 1 if key was set, 0 if it already existed
  const acquired = await redis.set(lockKey, instanceId, 'EX', 30, 'NX');
  return acquired === 'OK';
}

// In the queue processor
async process(job: Job) {
  const { sessionId } = job.data;

  if (!await acquireLock(sessionId)) {
    // Another instance is processing this conversation
    // Throw to retry later
    throw new Error('Conversation locked, will retry');
  }

  try {
    await processMessage(job.data);
  } finally {
    await redis.del(`lock:conversation:${sessionId}`);
  }
}
```

This ensures only one message per conversation is processing at a time, but different conversations process in parallel across all instances.

**Horizontal Scaling** — We run multiple instances of cxgenie-be behind an AWS ALB. Bull with Redis handles the coordination — Redis is the single source of truth, and only one instance picks up each job. If an instance crashes mid-job, Bull's built-in retry mechanism picks it up on another instance after the lock expires (30 seconds).

In production, we run three instances with 2 vCPUs each and handle thousands of concurrent conversations. If we needed more, we'd just add instances — the architecture is designed for horizontal scaling.

---

## Two Queue Systems

Actually, let me clarify — we have two different queue systems for different purposes.

**Bull/Redis Queues** — For durable, distributed job processing. These are the 26 queues I mentioned. Jobs are persisted in Redis, survive restarts, can be retried (up to 3 times with exponential backoff), have visibility (Bull Board dashboard), and work across multiple instances. We use these for anything that needs reliability: message processing, email sending, webhook delivery.

```typescript
// Bull queue configuration
const aiQueue = new Bull('ai-processing', {
  redis: REDIS_URL,
  defaultJobOptions: {
    attempts: 3,
    backoff: {
      type: 'exponential',
      delay: 1000, // 1s, 2s, 4s
    },
    removeOnComplete: 100, // Keep last 100 completed jobs
    removeOnFail: 500,     // Keep last 500 failed jobs for debugging
  },
});
```

**In-Memory Queue Service** — For high-throughput, ephemeral tasks within a single instance. We have a `BotQueueManagerService` that manages per-bot queues in memory. This is used specifically for knowledge extraction — when someone uploads a 500-page PDF, we don't want to create 500 Bull jobs (Redis overhead). Instead, we chunk the document and queue chunks in memory, processing them sequentially per bot.

The tradeoff is clear: in-memory is faster but not durable. If the instance crashes during knowledge extraction, that job is lost and needs to be restarted. For knowledge extraction, that's acceptable — the document is still there, we just re-process. For message processing, durability is critical, so we use Bull.

---

## WebSocket Architecture

For real-time features, we use Socket.IO, not raw WebSockets. Socket.IO gives us automatic reconnection, fallback to long-polling, room management, and namespaces.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         SOCKET.IO ARCHITECTURE                                │
└──────────────────────────────────────────────────────────────────────────────┘

  Browser/Widget                          Dashboard
       │                                      │
       │ WebSocket (or long-polling)          │
       ▼                                      ▼
┌─────────────────┐                 ┌─────────────────┐
│ Join room:      │                 │ Join room:      │
│ session:{id}    │                 │ workspace:{id}  │
└────────┬────────┘                 └────────┬────────┘
         │                                   │
         └───────────────┬───────────────────┘
                         ▼
              ┌─────────────────────┐
              │   cxgenie-be (1)    │
              │   Socket.IO Server  │
              └──────────┬──────────┘
                         │ Redis Pub/Sub
              ┌──────────┴──────────┐
              ▼                     ▼
    ┌─────────────────┐   ┌─────────────────┐
    │  cxgenie-be (2) │   │  cxgenie-be (3) │
    └─────────────────┘   └─────────────────┘
```

**Room Structure** — Each chat session has a room: `session:{sessionId}`. When a user opens the chat widget, they join that room. When a new message comes in or AI responds, we emit to that room: `io.to('session:' + sessionId).emit('message', data)`. This means we only send to clients who care.

For the dashboard, agents join rooms for their workspace: `workspace:{workspaceId}`. When any conversation in that workspace updates, they see it in real-time.

**Redis Adapter** — With multiple backend instances, we need to share socket state. Socket.IO's Redis adapter uses Redis pub/sub. When instance A emits to a room, it publishes to Redis. Instance B is subscribed and receives it. If any client in that room is connected to B, B emits to them.

```typescript
import { createAdapter } from '@socket.io/redis-adapter';
import { createClient } from 'redis';

const pubClient = createClient({ url: process.env.REDIS_URL });
const subClient = pubClient.duplicate();

await Promise.all([pubClient.connect(), subClient.connect()]);

io.adapter(createAdapter(pubClient, subClient));
```

**Authentication** — On socket connection, the client sends a JWT in the handshake query or auth header. We validate it in the connection middleware:

```typescript
io.use(async (socket, next) => {
  const token = socket.handshake.auth.token;
  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    socket.data.user = decoded;
    next();
  } catch (err) {
    next(new Error('Unauthorized'));
  }
});
```

**Heartbeat and Reconnection** — Socket.IO has built-in ping/pong heartbeat (default 25s interval, 20s timeout). If a client disconnects (network issue), Socket.IO client automatically tries to reconnect with exponential backoff. On reconnection, they rejoin their rooms automatically because we handle it in the connection handler.

---

## Caching Strategy

We use Redis heavily for caching, with different patterns for different data.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           REDIS CACHE STRUCTURE                               │
└──────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ session:{userId}         │ User session data      │ TTL: 24h, refresh     │
├─────────────────────────────────────────────────────────────────────────────┤
│ bot:{botId}              │ Bot configuration      │ TTL: 5min             │
├─────────────────────────────────────────────────────────────────────────────┤
│ ratelimit:{userId}       │ Token bucket counter   │ TTL: 1min             │
├─────────────────────────────────────────────────────────────────────────────┤
│ ld:flag:{flagKey}        │ Feature flag value     │ TTL: 5min + event     │
├─────────────────────────────────────────────────────────────────────────────┤
│ lock:conversation:{id}   │ Distributed lock       │ TTL: 30s              │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Session Cache** — User sessions are cached with prefix `session:`. TTL of 24 hours, refreshed on access. This reduces database lookups on every authenticated request.

**Bot Configuration Cache** — Bot configs don't change often, so we cache them: `bot:{botId}`. TTL of 5 minutes. When someone updates a bot in the dashboard, we invalidate: `redis.del('bot:' + botId)`. Cache-aside pattern — check cache, miss goes to DB and populates cache.

**Rate Limiting** — Redis token bucket for API rate limiting. Each user has a bucket: `ratelimit:{userId}`. We use Lua scripts for atomic check-and-decrement to avoid race conditions:

```lua
-- rate_limit.lua
local key = KEYS[1]
local limit = tonumber(ARGV[1])
local window = tonumber(ARGV[2])

local current = tonumber(redis.call('GET', key) or 0)
if current >= limit then
  return 0  -- Rate limited
end

redis.call('INCR', key)
redis.call('EXPIRE', key, window)
return 1  -- Allowed
```

Limit is 100 requests per minute for free tier, 1000 for paid.

**Distributed Locks** — For the message ordering problem, we use Redis SETNX: `lock:conversation:{sessionId}`. TTL of 30 seconds (max processing time) to prevent deadlocks if an instance crashes.

---

## API Design

Let me talk about our REST API design because it's pretty standard but there are some interesting patterns.

**RESTful Conventions** — We follow REST conventions: `GET /bots` for list, `GET /bots/:id` for single, `POST /bots` for create, `PATCH /bots/:id` for update, `DELETE /bots/:id` for delete. We use PATCH instead of PUT because we usually do partial updates.

**Pagination** — For list endpoints, we use cursor-based pagination for chat sessions (because new ones are created constantly) and offset-based for static resources like bots:

```typescript
// Cursor-based for time-series data
GET /chat-sessions?cursor=2024-01-15T10:30:00Z&limit=20

// Offset-based for static data
GET /bots?page=1&limit=20&sort=createdAt:desc
```

**Response Format** — All responses follow a consistent format:

```json
{
  "success": true,
  "data": { ... },
  "meta": {
    "page": 1,
    "limit": 20,
    "total": 150
  }
}
```

For errors:

```json
{
  "success": false,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Bot name is required",
    "details": [
      { "field": "name", "message": "is required" }
    ]
  }
}
```

**Validation** — We use class-validator with DTOs for request validation. NestJS pipes automatically validate and transform incoming data:

```typescript
class CreateBotDto {
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  name: string;

  @IsEnum(AIModel)
  aiModel: AIModel;

  @IsNumber()
  @Min(0)
  @Max(1)
  temperature: number;
}
```

**Versioning** — We use URL versioning: `/api/v1/bots`. We haven't needed v2 yet, but the structure is there.

---

## Security Considerations

Security is critical for a SaaS platform handling customer data. Here's what we do:

**Authentication** — JWT-based authentication. Access tokens expire in 1 hour, refresh tokens in 7 days. We store a hash of the refresh token in the database so we can revoke it if needed.

**Authorization** — Role-based access control (RBAC). Each workspace has roles: owner, admin, agent. Different permissions for each. We check permissions in NestJS guards:

```typescript
@UseGuards(AuthGuard, RolesGuard)
@Roles('admin', 'owner')
@Delete(':id')
async deleteBot(@Param('id') id: string) { ... }
```

**Data Encryption** — Sensitive data like OAuth tokens and API keys are encrypted at rest using AES-256-GCM. We use a key management service for the encryption keys.

**Input Validation** — All inputs are validated using class-validator. We sanitize HTML content to prevent XSS. SQL injection is prevented by using parameterized queries (Sequelize handles this automatically with model methods and prepared statements).

**Rate Limiting** — As mentioned, Redis token bucket. Also request size limits (10MB max) and webhook signature validation for incoming data.

**Audit Logging** — All sensitive operations (create, update, delete) are logged with user ID, timestamp, and what changed. Stored in a separate audit table.

---

## ClickHouse for Analytics

So for analytics-heavy workloads, PostgreSQL wasn't cutting it. When you have millions of chat messages and you want to generate real-time dashboards for agent performance, CSAT scores, response times... that's a lot of aggregations. PostgreSQL can do it, but it gets slow.

We introduced ClickHouse as our analytics database. It's a columnar database optimized for OLAP workloads — exactly what we needed.

**What we store in ClickHouse:**

```sql
-- Member availability logs (agent online/idle time)
CREATE TABLE member_availability_logs (
    user_id UUID,
    team_ids Array(UUID),
    workspace_id UUID,
    session_id UUID,
    type String,           -- 'online', 'idle', 'offline'
    duration Float64,
    timestamp DateTime
) ENGINE = MergeTree()
ORDER BY (workspace_id, user_id, timestamp);

-- Daily summaries for dashboards
CREATE TABLE member_availability_daily_summaries (
    user_id UUID,
    team_ids Array(UUID),
    workspace_id UUID,
    first_online Nullable(DateTime),
    last_online Nullable(DateTime),
    total_active_duration Float64,
    total_idle_duration Float64,
    avg_first_response_time Float64,
    total_chat UInt32,
    timezone Int32,
    created_at DateTime,
    day Date
) ENGINE = MergeTree()
ORDER BY (workspace_id, user_id, created_at);
```

**The ETL Pattern:**
- PostgreSQL is the source of truth for transactional data
- Cronjobs periodically aggregate data and push to ClickHouse
- ClickHouse handles the heavy analytical queries
- Dashboard reads from ClickHouse for fast response times

**Why ClickHouse over alternatives:**
- Crazy fast for aggregations (100x faster than PostgreSQL for our queries)
- MergeTree engine optimized for time-series data
- Supports SQL so no learning curve for the team
- Column-oriented storage means efficient compression

The tradeoff is eventual consistency — there's a 1-2 minute delay before data appears in dashboards. But for analytics, that's acceptable. Users don't need real-time agent performance metrics.

---

## Microservices Architecture - Full Picture

Let me give you the complete picture of all our services. It's not just 4 services — we have more for enterprise deployments:

```
┌────────────────────────────────────────────────────────────────────────────────┐
│                           FULL MICROSERVICES ARCHITECTURE                       │
└────────────────────────────────────────────────────────────────────────────────┘

                              ┌─────────────────────┐
                              │   NGINX Ingress     │
                              │   (per-tenant)      │
                              └──────────┬──────────┘
                                         │
         ┌───────────────────────────────┼───────────────────────────────┐
         │                               │                               │
         ▼                               ▼                               ▼
┌─────────────────┐            ┌─────────────────┐            ┌─────────────────┐
│   dashboard     │            │   chat-widget   │            │   chat-web      │
│   (Frontend)    │            │   (Embeddable)  │            │   (Web Chat)    │
└────────┬────────┘            └────────┬────────┘            └────────┬────────┘
         │                               │                               │
         └───────────────────────────────┼───────────────────────────────┘
                                         │
                                         ▼
                              ┌─────────────────────┐
                              │    gateway-api      │
                              │  (API Gateway/BE)   │
                              │     NestJS          │
                              └──────────┬──────────┘
                                         │
         ┌───────────────────────────────┼───────────────────────────────┐
         │                               │                               │
         ▼                               ▼                               ▼
┌─────────────────┐            ┌─────────────────┐            ┌─────────────────┐
│    core-ai      │            │ integration-svc │            │  loader-service │
│    FastAPI      │            │    NestJS       │            │    Python       │
│ (RAG + LLM)     │            │ (Slack/Discord/ │            │ (Doc Processing)│
│                 │            │  Telegram)      │            │                 │
└────────┬────────┘            └─────────────────┘            └─────────────────┘
         │
         ▼
┌─────────────────┐
│     Zilliz      │
│  Vector Search  │
└─────────────────┘

         ┌───────────────────────────────────────────────────────────────┐
         │                        SHARED INFRASTRUCTURE                   │
         ├─────────────────┬─────────────────┬─────────────────┬─────────┤
         │   PostgreSQL    │      Redis      │   ClickHouse    │   S3    │
         │   (per-tenant)  │  (Cache/Queue)  │  (Analytics)    │ (Files) │
         └─────────────────┴─────────────────┴─────────────────┴─────────┘
```

**Service Details:**

**gateway-api (cxgenie-be)** — The main backend. All REST APIs, WebSocket, business logic. This is what I mainly worked on.

**core-ai** — Python FastAPI service for RAG pipeline, embedding generation, LLM calls.

**integration-service** — Handles platform integrations like Slack, Discord, Telegram. When a business wants to connect their Slack workspace or Telegram bot, this service handles the OAuth flow, webhook registration, and message routing. Port 3005.

**loader-service** — Document processing service. When users upload PDFs, DOCs, or provide URLs to crawl, this service handles:
- Document parsing and text extraction
- Chunking into 512-token segments
- Embedding generation
- Storing in vector database
It runs on port 8000 with Prometheus metrics endpoint for monitoring processing throughput.

**ticket** — Ticketing system for human agent handoff.

**All services integrate with gateway-api (cxgenie-be)** — The main backend orchestrates calls to other services. For example:
- User uploads a document → BE calls loader-service
- Message comes in → BE calls core-ai for response
- Slack integration request → BE calls integration-service

---

## Infrastructure & DevOps

Now let me talk about the infrastructure side because I also handled DevOps for this project.

**AWS Services We Use:**

```
┌────────────────────────────────────────────────────────────────────────────────┐
│                              AWS INFRASTRUCTURE                                 │
└────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                                    VPC                                          │
│  Region: ap-southeast-1 (Singapore)                                            │
│  AZs: ap-southeast-1a, ap-southeast-1b                                         │
│                                                                                 │
│  ┌─────────────────────────────┐    ┌─────────────────────────────┐           │
│  │      Public Subnets         │    │      Private Subnets        │           │
│  │  ┌─────────────────────┐   │    │  ┌─────────────────────┐    │           │
│  │  │   NAT Gateway       │   │    │  │   EKS Node Groups   │    │           │
│  │  │   EC2 Bastion       │   │    │  │   RDS Instances     │    │           │
│  │  │   ALB               │   │    │  │                     │    │           │
│  │  └─────────────────────┘   │    │  └─────────────────────┘    │           │
│  └─────────────────────────────┘    └─────────────────────────────┘           │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                               AWS EKS Cluster                                   │
│                                                                                 │
│  Managed Node Groups (per enterprise client):                                  │
│  ┌───────────────┐ ┌───────────────┐ ┌───────────────┐ ┌───────────────┐       │
│  │ baji-prod     │ │ mcw-prod      │ │ crickex-prod  │ │ bigwin29-prod │       │
│  │ 3-5 nodes     │ │ 2-5 nodes     │ │ 2-5 nodes     │ │ 2-5 nodes     │       │
│  │ t3a.large     │ │ t3a.large     │ │ t3a.large     │ │ t3a.large     │       │
│  └───────────────┘ └───────────────┘ └───────────────┘ └───────────────┘       │
│  ┌───────────────┐ ┌───────────────┐ ┌───────────────┐                         │
│  │ pb88-prod     │ │ wolfherd-prod │ │ ep-monitor    │                         │
│  │ 2-5 nodes     │ │ 2-5 nodes     │ │ 1-2 nodes     │                         │
│  └───────────────┘ └───────────────┘ └───────────────┘                         │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                               AWS RDS (PostgreSQL 16)                           │
│                                                                                 │
│  Separate database per enterprise client:                                      │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐               │
│  │ cxg_baji    │ │ cxg_mcw     │ │ cxg_crickex │ │ cxg_bigwin29│               │
│  │ db.t4g.med  │ │ db.t4g.med  │ │ db.t4g.med  │ │ db.t4g.med  │               │
│  │ 200GB       │ │ 200GB       │ │ 200GB       │ │ 200GB       │               │
│  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘               │
│  ┌─────────────┐ ┌─────────────┐                                               │
│  │ cxg_pb88    │ │cxg_wolfherd │                                               │
│  └─────────────┘ └─────────────┘                                               │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                              Other AWS Services                                 │
│                                                                                 │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐               │
│  │ S3          │ │ EC2 Bastion │ │ VPC Endpoint│ │ IAM         │               │
│  │ Backups     │ │ SSH Tunnel  │ │ for S3      │ │ Policies    │               │
│  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘               │
└─────────────────────────────────────────────────────────────────────────────────┘
```

**Infrastructure as Code with Terraform:**

We use Terraform for all infrastructure provisioning:

```hcl
# EKS Cluster with managed node groups
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.VPC_NAME
  cluster_version = var.K8S_VERSION

  eks_managed_node_groups = {
    baji-general-prod = {
      instance_types = ["t3a.large"]
      min_size       = 3
      max_size       = 5
      desired_size   = 5
      capacity_type  = "ON_DEMAND"

      labels = {
        enterprise  = "baji"
        environment = "production"
      }
    }
    # ... more node groups per client
  }
}

# RDS per client for data isolation
module "rds-baji" {
  source         = "./modules/rds"
  RDS_NAME       = "baji"
  PSQL_VERSION   = 16
  INSTANCE_CLASS = "db.t4g.medium"
  DISK_SIZE      = "200"
  DB_NAME        = "cxg_baji"
}
```

**GitOps with ArgoCD:**

Every deployment goes through ArgoCD with automated sync:

```yaml
# ArgoCD Application manifest
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cxg-be-baji-production
  namespace: argocd
spec:
  destination:
    namespace: baji-production
    server: 'https://kubernetes.default.svc'
  source:
    path: config/baji/cxgenie/be/production
    repoURL: 'https://github.com/Eastplayers/cxgenie-etp-infra'
    helm:
      valueFiles:
        - values.yaml
  syncPolicy:
    automated:
      prune: true      # Remove resources not in git
      selfHeal: true   # Auto-fix drift
```

**Helm Charts for Kubernetes:**

Each service has a Helm chart with:
- Deployment with resource limits
- HPA (Horizontal Pod Autoscaler)
- Ingress with TLS (cert-manager + Let's Encrypt)
- ConfigMaps and Secrets
- Health checks (liveness + readiness probes)

```yaml
# Example: loader-service values.yaml
replicaCount: 2
resources:
  limits:
    cpu: 500m
    memory: 1Gi
  requests:
    cpu: 100m
    memory: 1Gi

# Prometheus metrics
podAnnotations:
  prometheus.io/scrape: "true"
  prometheus.io/path: "/metrics"
  prometheus.io/port: "8000"

# Node affinity for tenant isolation
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
          - key: enterprise
            operator: In
            values:
              - baji
```

**Multi-Tenancy at Infrastructure Level:**

This is important — we have enterprise clients who require data isolation. We achieve this at multiple levels:

1. **Separate RDS per client** — Each enterprise client has their own PostgreSQL database
2. **Separate K8s namespace per client** — baji-production, mcw-production, etc.
3. **Node affinity** — Pods only run on nodes labeled for that client
4. **Separate ingress controllers** — nginx-baji, nginx-mcw, etc.

**EC2 Bastion for Secure Access:**

SSH tunnel through bastion for database access:
```bash
ssh -i key.pem -L 5432:rds-endpoint:5432 ec2-user@bastion-ip
```

**Why This Architecture:**
- Full tenant isolation (compliance requirement for enterprise)
- Independent scaling per client
- No noisy neighbor issues
- Easy to onboard new enterprise clients (just add Terraform module + Helm values)

---

## Feature Flags - LaunchDarkly Integration

Let me tell you about the feature flag system because this was my implementation and I'm actually pretty proud of it.

So LaunchDarkly is great for feature flags, but there are two problems at scale: API rate limits, and you want real-time updates without polling.

**The Architecture** — I built a dedicated service (cxgenie-launch-darkly) that acts as a caching proxy:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      LAUNCHDARKLY INTEGRATION                                │
└─────────────────────────────────────────────────────────────────────────────┘

                      ┌─────────────────────────┐
                      │  LaunchDarkly Cloud     │
                      │  (Flag Configuration)   │
                      └───────────┬─────────────┘
                                  │ SSE Stream
                                  ▼
                      ┌─────────────────────────┐
                      │ cxgenie-launch-darkly   │
                      │ (LD SDK + Redis Cache)  │
                      └───────────┬─────────────┘
                           │      │
           ┌───────────────┘      └───────────────┐
           ▼                                      ▼
     ┌──────────────┐                      ┌──────────────┐
     │    Redis     │                      │  cxgenie-be  │◄──── HTTP
     │ ld:flag:*    │                      │  (Webhook)   │
     └──────────────┘                      └──────┬───────┘
                                                  │ Socket.IO
                                                  ▼
                                           ┌──────────────┐
                                           │  Dashboard   │
                                           └──────────────┘
```

**Flag Fetching Flow**:

1. Dashboard needs flags → calls cxgenie-be API
2. cxgenie-be calls cxgenie-launch-darkly service
3. LD service checks Redis cache first
4. Cache hit → return immediately (1-2ms)
5. Cache miss → evaluate flag using LD SDK, cache result, return
6. Cache TTL is 5 minutes as a fallback

**Real-time Update Flow**:

1. Admin changes flag in LaunchDarkly dashboard
2. LD SDK in our service receives SSE event
3. We update Redis cache immediately: `redis.set('ld:flag:' + key, value)`
4. We call cxgenie-be webhook: POST `/internal/flags/updated`
5. cxgenie-be emits Socket.IO event to all connected dashboards
6. Dashboard updates UI without refresh

So flag changes propagate in near-real-time — usually under 1 second. An admin toggles a feature, and within a second, every user's dashboard reflects it.

This reduced our LaunchDarkly API calls by about 95%. Most requests hit Redis cache. We're only calling LD for cache misses and initial SDK initialization. This matters when you're paying by usage.

---

## Monitoring & Observability

We have several layers of observability:

**Application Metrics** — We use Prometheus-style metrics exposed on `/metrics` endpoint. Key metrics:

- `http_request_duration_seconds` — API latency histogram
- `bull_queue_jobs_total` — Queue job counts by status
- `ai_processing_duration_seconds` — RAG pipeline latency
- `active_websocket_connections` — Current WebSocket count
- `database_pool_active` — Active database connections

**Logging** — Structured JSON logging with correlation IDs. Every request gets a unique `requestId` that's passed through to all services. Makes debugging distributed issues much easier:

```json
{
  "level": "info",
  "requestId": "req_abc123",
  "message": "Processing message",
  "sessionId": "sess_xyz",
  "botId": "bot_456",
  "duration": 2345
}
```

**Alerting** — We alert on:

- Error rate > 1% over 5 minutes
- P95 latency > 5s
- Queue backlog > 1000 jobs
- Database connection pool > 80%
- Memory usage > 85%

**Distributed Tracing** — For debugging cross-service issues, we propagate trace IDs through HTTP headers. Not full APM, but enough to trace a request across services.

---

## Production Challenges

So let me think about production issues we've dealt with...

**Database Connection Exhaustion** — This was a fun one. We're using Sequelize with a connection pool, max 25 connections per instance. But with our async queue processors and multiple parallel operations, we were sometimes exhausting the pool during traffic spikes. You'd see errors like "ConnectionAcquireTimeoutError: Operation timeout."

The solution was a combination of things. First, connection pool monitoring — we added metrics to track pool usage and alert when it hits 80%. Second, query optimization to reduce connection hold time — a connection is held for the duration of a query, so faster queries mean more throughput. We found some N+1 queries and fixed them with proper `include` options for eager loading. Third, read replicas for heavy read operations — analytics dashboards were doing heavy aggregations, we moved those to read replicas using `useMaster: false` option.

**Message Ordering Race Condition** — Like I mentioned, messages in a conversation need to stay in order. Early on, we had a race condition. Two messages arrive 50ms apart. Message 1 starts processing, checks the lock, none exists, proceeds. Message 2 starts, checks the lock, message 1 hasn't set it yet (race window), proceeds. Both process simultaneously, responses come back out of order.

The fix was atomic distributed locking using Redis SETNX. Instead of check-then-set (two operations), SETNX is atomic — set-if-not-exists. If it returns OK, you got the lock. If null, someone else has it, retry later. We also added a TTL of 30 seconds to prevent deadlocks.

**Memory Leaks in AI Service** — Python's not known for memory issues, but when you're loading large embedding models and processing thousands of documents for knowledge extraction, you can accumulate memory if you're not careful. We'd see the container memory creep up over days until it OOM'd.

The diagnosis: large numpy arrays from embeddings weren't being garbage collected promptly because of reference cycles. The fix: explicit `gc.collect()` calls after large operations, using `del` to clear large variables, and switching to generators instead of loading entire documents into memory. We also added memory monitoring to catch issues early.

**WebSocket Scaling Issues** — When we added a second backend instance, suddenly users were getting disconnected randomly. What happened: user connects to instance A, instance A restarts for deploy, connection drops, client reconnects... but maybe to instance B. Instance B doesn't know about their session state (rooms they were in).

The fix was two parts. First, Redis adapter for Socket.IO so socket events work across instances. Second, on reconnection, the client sends their session info (which rooms they should be in), and we rejoin them to appropriate rooms server-side. Now deploys are seamless — we do rolling restarts, and users barely notice.

**Cold Start Latency** — The AI service had cold start issues. First request after a while was slow — loading models, warming up connections. Solution: we added a `/health` endpoint that the load balancer hits, which also pre-warms the model. And we configured min-replicas to 1 so there's always a warm instance.

---

## Tech Choices and Tradeoffs

For tech choices, let me think...

**NestJS** was picked for the main backend because we wanted TypeScript's type safety and NestJS's structure with decorators, dependency injection, modules — it's very organized for a large codebase. The tradeoff is it's more verbose than Express, and there's definitely a learning curve with the DI system. New developers need time to understand how providers, modules, and injection scopes work. But for a team project with 118 models and 50+ modules, the structure pays off.

**Sequelize over TypeORM** — We chose Sequelize with sequelize-typescript for the ORM. Sequelize is more mature, has better documentation, and the migration system with sequelize-cli is straightforward. TypeORM has some nice features like QueryBuilder, but at the time we started, Sequelize was more battle-tested with NestJS. The tradeoff is that Sequelize's typing can be a bit awkward compared to TypeORM's decorators, but sequelize-typescript helps with that by providing decorator-based model definitions.

**FastAPI** for the AI service because Python's AI ecosystem is just unmatched. LangChain, LlamaIndex, all the embedding libraries, vector database clients — everything's in Python first. FastAPI gives us nice typing with Pydantic, async support with ASGI (uvicorn), and automatic OpenAPI docs. Could we have done it in Node? Technically yes, but we'd be using Python bindings anyway (ONNX runtime, etc.) or fighting against the ecosystem.

**PostgreSQL over MongoDB** — we have complex relational data. Bots have knowledge bases, knowledge bases have documents, documents have chunks, chunks have embeddings... it's all relational. Plus we needed ACID transactions for things like subscription billing — you can't have a race condition that charges someone twice. MongoDB would've been awkward for joins and transactions. PostgreSQL also has great performance with proper indexing and supports JSON columns for flexible data when we need it.

**Zilliz over self-hosted Milvus** — we tried self-hosting Milvus first. The operational overhead was brutal — tuning etcd, managing index builds, handling failovers. When a node went down at 3 AM, we were paged. Zilliz is managed, handles scaling automatically, handles backups, has better support. Costs more but we're not in the business of managing vector databases. Focus on product, not infrastructure.

**Bull over RabbitMQ** — Bull is simpler. It's just Redis, which we already use for caching and sessions. One less piece of infrastructure to manage. RabbitMQ has more features — sophisticated routing, message acknowledgment patterns, dead letter exchanges — but we didn't need them. Bull has good monitoring with Bull Board, straightforward API, and battle-tested at scale. For our needs, simpler is better.

**Socket.IO over raw WebSocket** — Socket.IO handles the edge cases. Automatic reconnection with exponential backoff, fallback to long-polling if WebSocket is blocked (corporate firewalls), room abstraction, namespace support, and the Redis adapter for horizontal scaling. With raw WebSocket, we'd have to implement all of that ourselves.

---

## Summary

So yeah, that's CX Genie in a nutshell. An AI customer support platform with full microservices architecture:

**Services:** gateway-api (NestJS), core-ai (FastAPI), integration-service (NestJS), loader-service (Python), ticket, plus frontend services (dashboard, chat-widget, chat-web).

**Databases:** PostgreSQL (per-tenant, 118 models), Redis (cache + queues), ClickHouse (analytics), Zilliz (vector search).

**Infrastructure:** AWS EKS with Terraform, ArgoCD for GitOps, Helm charts, multi-tenant isolation with separate RDS + namespaces per enterprise client.

The interesting technical problems are:

- **RAG pipeline** for intelligent responses with parallel vector search
- **Multi-channel message routing** through database configuration, not code
- **Event-driven architecture** with Bull queues for scalability
- **WebSocket with Redis adapter** for real-time across multiple instances
- **Paragraph-based streaming** for efficient delivery (90% fewer events)
- **Distributed locking** with Redis SETNX for message ordering
- **Feature flag service** with caching and real-time updates (95% fewer API calls)
- **ClickHouse analytics** for CSAT dashboards and agent performance metrics
- **Multi-tenant infrastructure** with full data isolation per enterprise client
- **GitOps deployment** with ArgoCD automated sync + self-heal

I worked on pretty much all parts of the backend and DevOps — the core message processing flow, the RAG pipeline integration, the feature flag system, WebSocket handling, database design, and the entire Kubernetes/Terraform infrastructure. The thing I'm most proud of is probably combining the backend complexity with proper infrastructure — making async event-driven architecture work correctly with message ordering, distributed locking, horizontal scaling, AND having it all deployed via GitOps with proper tenant isolation.

Any questions about specific parts? I can go deeper on database design, the AI pipeline, the queue architecture, infrastructure, Kubernetes, or anything else.
