# Interview Speaking Guide: Flowmingo Project
## 30-Minute General Interview | SA + Founder

---

# Interview Flow (30 minutes)

```
0-3 min   → Opening / Your Background
3-8 min   → Project Overview & Your Role
8-25 min  → Deep Dive: Challenges, Diagnosis, Solutions
25-28 min → Questions About Passion & Mindset
28-30 min → Your Questions / Closing
```

---

# Part 1: Opening (0-3 min)

## "Tell me about yourself"

> "I'm a backend developer with a focus on Node.js and system architecture. Most recently, I worked as a technical consultant where I was brought in to audit and fix a production system that was struggling - an AI-powered interview platform processing thousands of candidates daily.
>
> What I enjoy most is diagnosing complex production issues and building systems that actually work at scale. I've seen what happens when teams skip engineering fundamentals, and I'm passionate about doing things right - even in a fast-moving environment."

---

# Part 2: Project Overview (3-8 min)

## "Tell me about your recent project"

> "At Atenyx, I worked on AI-powered products. One of my lastest projects was being outsourced as a technical consultant to Flowmingo - an AI interview platform.The system handles video interviews with real-time audio streaming - candidates speak, we stream audio to AI, process with Gemini, and stream back responses. Processing thousands of candidates daily.
>
> The situation was pretty bad when I joined. Daily crashes, candidates stuck in interviews for hours, duplicate processing wasting API credits. Customer complaints coming in constantly. The team basically discovered outages when customers complained - there was no monitoring, no alerting, nothing.
>
> The root cause? The team had been 'vibe coding' - shipping features fast without any engineering fundamentals. No code review, no testing, no CI/CD, no staging environment. When something broke, they would SSH into the server, grep logs, and basically guess what went wrong.
>
> My role was to conduct a comprehensive technical audit, prioritize issues by business impact, and implement proper solutions. I treated it like a consulting engagement - diagnose, prioritize, fix, and document everything so the team could maintain it going forward."

## "What was your specific contribution?"

> "I owned the entire technical transformation. I started by auditing the codebase and categorizing issues - P0 for things causing immediate customer pain like crashes and duplicates, P1 for operational issues like no observability, P2 for code quality stuff.
>
> Then I fixed the critical issues - restructured the queue architecture to eliminate duplicates, fixed memory leaks in video processing, resolved race conditions, set up the CI/CD pipeline, implemented proper database migrations. I also set up the full observability stack - OpenTelemetry, Prometheus, Grafana, the works.
>
> But honestly, I wasn't just fixing bugs. I was changing how the team builds software. Introducing code review, proper deployment processes, documentation. Shifting from 'vibe coding' to actual engineering practices."

---

# Part 3: Technical Deep Dives (8-25 min)

*Pick 3-4 based on their interest.*

---

## Topic 1: PM2 & WebSocket Architecture
*Best for showing: Infrastructure diagnosis*

**"What was the first critical issue you found?"**

> "So the platform uses WebSocket for real-time audio streaming during interviews. Candidates speak, stream audio chunks to the AI, stream back responses. They were using PM2 in cluster mode because, you know, 'more instances equals better performance.'
>
> The problem was, PM2 cluster mode has a master process that receives all connections first, then distributes to workers using round-robin. For us, that meant every audio chunk - we're talking hundreds per second - all passing through one single process. That's your bottleneck right there.
>
> But it gets worse. WebSocket connections are stateful. They store session data in memory - which socket belongs to which interview, audio buffers, connection health metrics. With round-robin, request 1 hits Worker A, request 2 hits Worker B. Worker B doesn't have the session data. Connection just fails.
>
> My fix was actually pretty simple - switch to fork mode with a single instance. Sounds counterintuitive, right? Fewer instances? But for stateful services, one well-configured instance beats a misconfigured cluster every time.
>
> For future scaling, I documented a path - Docker containers with Nginx doing sticky sessions at the load balancer level, Redis Pub/Sub for cross-instance messaging. But we didn't need it yet. Premature optimization is waste.
>
> Result? Latency dropped from 200-500ms to under 50ms. Stuck interview reports dropped by 80%."

**If they ask: "Why not just add sticky sessions?"**

> "You can put Nginx with ip_hash in front, but here's the thing - Nginx routes to the PM2 cluster as a whole, not to specific workers inside it. The master process still distributes round-robin internally. You'd need to bypass PM2 cluster entirely, which is exactly what Docker plus Nginx does.
>
> The simple fix was good enough for current scale. I documented the proper scaling solution for when they actually need it. That's startup pragmatism - don't over-engineer for problems you don't have yet."

---

## Topic 2: BullMQ & Duplicate Processing
*Best for showing: Deep technical debugging*

**"What was the most interesting technical problem?"**

> "The duplicate processing issue was fascinating to debug. Candidates were getting multiple evaluation emails, and we were wasting like 15% of API credits on duplicates.
>
> So I investigated. They were using BullMQ for AI evaluation jobs. These jobs call the Gemini API and take 3-5 minutes to complete. BullMQ has this lock mechanism with a 30-second default timeout.
>
> Here's where it gets interesting. Node.js is single-threaded, right? When you await an HTTP call to Gemini, the event loop is blocked waiting for that response. BullMQ has a timer that's supposed to renew the lock, but that timer callback can't fire while you're waiting for Gemini to respond. So the lock expires, the job gets marked as stalled, another worker picks it up. Now you have two workers processing the exact same evaluation.
>
> Short-term fix was configuring proper lock duration and renewal. Long-term, I recommended migrating to RabbitMQ for these long-running jobs because it uses ACK-based delivery. No timeout - the message stays unacknowledged until you explicitly confirm you're done. Take 3 minutes, take 10 minutes, doesn't matter.
>
> Duplicates went from 50+ per day to literally zero. That's real money saved on API credits."

**If they ask: "Why RabbitMQ over Kafka?"**

> "Different tools for different problems. RabbitMQ is a task queue - you send a job, one worker processes it, done. Kafka is an event log - messages are retained, multiple consumers can read the same stream, you can replay history.
>
> For background jobs, RabbitMQ. For analytics pipelines where you need to reprocess historical data, Kafka. A common mistake I see is teams using Kafka for everything because 'Netflix uses it' - but that just adds complexity without any real benefit for simple job queues."

---

## Topic 3: Deployment & SDLC Chaos
*Best for showing: Process maturity*

**"Tell me about a process problem you fixed"**

> "Their deployment process was... well, it wasn't really a process. SSH into production server, git pull, pm2 restart, and pray. No CI/CD, no staging environment, no database migrations. TypeORM was configured with synchronize true in production - that's the setting that auto-modifies your database schema, which is terrifying.
>
> Schema changes were happening via Slack messages. Someone would post 'Hey, run this SQL in prod' and someone else would just... do it. No version control, no rollback capability, no audit trail.
>
> The worst part was this endless bug cycle. Bug gets reported, developer checks dev environment, can't reproduce it, deploys a 'fix,' bug still happens in production. Without metrics or proper logging, there was no way to prove anything actually got fixed. Same bugs getting 'fixed' 3-4 times. And sometimes I see customer complaints coinciding with production deployment.
>
> So I implemented a proper pipeline. GitHub Actions for CI/CD - tests have to pass before you can deploy. Added a staging environment that mirrors production. Switched to TypeORM migrations instead of synchronize. Added health checks and metrics to actually verify deployments worked.
>
> Deploy time went from 30 minutes of manual work to 5 minutes automated. Zero downtime now with blue-green deployment. And we finally stopped having those 'fixed in dev, still broken in prod' situations."

**If they ask: "How did you convince them to invest in this?"**

> "Numbers. I calculated that every manual deployment had roughly a 20% chance of causing some kind of incident. Each incident took 2-4 hours to debug and fix. With 3-4 deployments per week, that's 30-40 engineering hours per month just dealing with deployment problems.
>
> The CI/CD pipeline took about 2 weeks to set up properly. It paid for itself in the first month. When you frame technical debt as actual business cost, priorities change pretty quickly."

---

## Topic 4: Database & Query Optimization
*Best for showing: Database expertise*

**"Did you find any database performance issues?"**

> "Oh, plenty. The classic N+1 problem was everywhere. They'd load a list of interviews, then loop through and query candidates one by one. 100 interviews meant 101 database queries. Page load times were hitting 5-10 seconds.
>
> JSONB was another issue. They stored evaluation results as JSONB and were querying inside it without any indexes. Full table scans every time.
>
> I also found missing indexes on foreign keys, no pagination on large queries, SELECT * everywhere instead of selecting just the columns they needed.
>
> For N+1, the fix was eager loading with proper TypeORM relations. For JSONB, I added GIN indexes on the fields we actually query.
>
> Dashboard load time went from 5-10 seconds to under 500ms. Database CPU dropped by 60%."

**If they ask: "How did you identify the slow queries?"**

> "First thing I did was enable query logging in TypeORM to see what was actually hitting the database. Then I used PostgreSQL's pg_stat_statements to find the slowest queries by total execution time. Ran EXPLAIN ANALYZE on the worst offenders - that's when I saw all the sequential scans.
>
> The pattern is always: measure first, then optimize. Don't guess where the problem is - let the database tell you."

---

## Topic 5: Observability
*Best for showing: Production mindset*

**"How did you handle debugging?"**

> "When I joined, debugging meant SSH into a server, grep through logs, hope you find something useful. With 10+ microservices, that was basically impossible. The team would find out about outages when customers complained.
>
> So I implemented what I call the three pillars. Tracing with OpenTelemetry - you can follow a single request as it flows through all your services. Metrics with Prometheus - queue depths, latency percentiles, error rates. Centralized logging with Loki, correlated with traces so you can jump from a log line to the full request trace.
>
> All of this feeds into Grafana dashboards with alerting to Slack. If error rate spikes or queue depth grows abnormally, we know immediately.
>
> Before: customer reports a problem, takes 2+ hours to diagnose, maybe find the root cause. After: alert fires, click the trace ID, see exactly which service failed and why, fix it in 5-15 minutes. That's a game-changer for production operations."

---

## Topic 6: Memory & Video Processing
*Best for showing: Node.js expertise*

**"Tell me about a performance issue you solved"**

> "Video processing workers were crashing 5-10 times daily. Out of memory errors constantly.
>
> Root cause was pretty straightforward once I looked at the code. They were loading entire video files into memory - readFileSync on a 200MB video. Run 5 of those concurrently, that's a gigabyte just in video buffers. Plus Node.js overhead, FFmpeg processes, everything else.
>
> The team also had empty catch blocks everywhere. Cleanup failures were completely silent. Temp files accumulating on disk, nobody knew.
>
> The fix was stream-based processing. Instead of loading the whole file into memory, you pipe it through FFmpeg. Constant memory usage regardless of file size - maybe 10MB instead of 200MB per job. Added proper error handling with logging, queued cleanup retries for failed deletions.
>
> Crashes dropped to basically zero. Job completion rate went from 85% to over 99%."

---

## Topic 7: Race Conditions
*Best for showing: Concurrency understanding*

**"Did you encounter any concurrency issues?"**

> "Classic race conditions all over the place. The code was written assuming single-instance deployment, but they were running multiple workers.
>
> Example: they had an in-memory Map for deduplication. Works perfectly with one instance. But with two instances, each has its own Map - so you still get duplicates across instances.
>
> Another example: check-then-act pattern. Load a record, check if status is 'pending,' update it to 'processing.' But between the check and the update, another request can do the exact same thing. Both think they won the race.
>
> Solutions were pretty standard. Distributed locking with Redis Redlock for cross-instance coordination. Atomic database updates with WHERE clauses - instead of check then update, just UPDATE WHERE status = pending and see if any rows were affected. Deterministic job IDs so BullMQ ignores duplicates automatically.
>
> The lesson is always think about what happens when you have multiple instances handling concurrent requests. Code that works in dev often fails at scale."

---

## Topic 8: Testing Strategy
*Best for showing: Quality mindset*

**"How do you approach testing?"**

> "When I joined, there were basically no tests. The team would deploy and pray. So part of my work was establishing a proper testing culture.
>
> For unit tests, we use Jest - it's the standard for NestJS. I focused on testing the critical business logic first - evaluation scoring, queue job handlers, the deduplication logic. Each service has its dependencies mocked so tests run fast and isolated. We test edge cases too - what happens when Gemini returns an empty response, what if the candidate disconnects mid-interview.
>
> For integration tests, we use Supertest to hit the actual API endpoints. We spin up a test database - same schema as production, but isolated. This catches things unit tests miss - like TypeORM relation issues, middleware problems, authentication flows. Before my changes, they had bugs where the API worked fine in Postman but failed in production because of missing guards or interceptors.
>
> The key insight is test what matters. I don't aim for 100% coverage - that's vanity. I aim for confidence. Can I deploy on Friday afternoon without worrying? That's the real metric. Critical paths like interview flow and evaluation get thorough coverage. Internal admin endpoints get basic happy-path tests.
>
> We also added tests to CI/CD - no merge if tests fail. Sounds obvious, but before that, broken code would just get deployed because nobody ran tests locally."

**If they ask: "What's your testing philosophy?"**

> "Test behavior, not implementation. I've seen teams with 90% coverage that break on every refactor because they're testing internal details. If I change how a function works internally but the output stays the same, tests shouldn't break.
>
> Also, tests are documentation. When a new developer joins, they can read the test file to understand what a service is supposed to do. That's more valuable than comments that go stale."

---

## Topic 9: Performance Profiling
*Best for showing: Production optimization skills*

**"How do you handle performance issues?"**

> "Performance debugging was a big part of my work. The system was slow, but nobody knew why - just 'it's slow sometimes.'
>
> First step is always measurement. You can't optimize what you can't measure. I used Node.js built-in profiling with --inspect flag and Chrome DevTools. For CPU profiling, I'd capture flame graphs to see where time is spent. Found some surprises - one handler was doing synchronous JSON parsing on large payloads, blocking the event loop for 200ms.
>
> For memory profiling, I used heapdump to capture heap snapshots. That's how I found the video processing memory leak - buffers not being released after FFmpeg finished. You compare snapshots over time and look for objects that keep growing.
>
> We also use clinic.js in development - it's fantastic for Node.js. It runs your app and generates visual reports showing event loop delays, memory usage, CPU hotspots. Much easier than reading raw profiler output.
>
> In production, our observability stack does continuous monitoring. Prometheus tracks p50, p95, p99 latencies. Grafana dashboards show trends over time. If p99 suddenly spikes, we get an alert before customers complain. OpenTelemetry traces show exactly which service and which database query is slow.
>
> The pattern I follow: measure in production with lightweight monitoring, reproduce locally with heavy profiling tools, fix, verify the metrics improved. Don't guess - let the data tell you where the problem is."

**If they ask: "Can you give a specific example?"**

> "The dashboard was taking 5-10 seconds to load. I started with Prometheus metrics - API latency was fine, around 200ms. So the problem wasn't the API itself.
>
> Dug into OpenTelemetry traces and saw the database queries. Multiple N+1 queries, each taking 50-100ms, but there were 40 of them. That's 4 seconds just in database round trips.
>
> Used pg_stat_statements to confirm - these queries were hitting the database millions of times per day. Added eager loading, proper indexes, and the dashboard dropped to under 500ms. The fix took an hour, but finding the root cause took most of the day. That's why observability matters - without traces, I'd still be guessing."

---

## Topic 10: Anti-Patterns & Code Quality
*Best for showing: Engineering fundamentals*

**"What kind of code quality issues did you find?"**

> "The codebase was full of anti-patterns that made debugging nearly impossible. No code review process meant these patterns just spread everywhere.
>
> First big issue: dynamic imports inside functions. They were doing require('fluent-ffmpeg') inside a function that gets called hundreds of times per hour. Every single call does file I/O, parsing, execution. Just moved it to a module-level import and we saw immediate performance gains.
>
> Second: silent error handling. Empty catch blocks everywhere. Try-catch with just curly braces, nothing inside. So errors happened, got swallowed, and nobody knew. Disk filled up because cleanup failures were silent. Candidates couldn't hear the AI because text-to-speech errors were swallowed. When I added proper logging and error handling, suddenly we could see all these hidden failures.
>
> Third: copy-paste code. The same translation initialization logic was duplicated in three different services. Each slightly different. When we needed to fix a bug, we had to change three files. If you missed one, inconsistent behavior. I extracted these into a shared library - single source of truth.
>
> Fourth: hardcoded configuration. Found actual credentials in the codebase. Magic numbers everywhere - 'retry 3 times' but why 3? 'Wait 5 seconds' but why 5? No documentation. Moved everything to environment variables and configuration files with proper comments explaining the reasoning."

**If they ask: "How did you address this systematically?"**

> "I introduced code review. Sounds basic, but they didn't have it. Every PR now gets reviewed before merge. We created a shared commons library for reusable code. Added linting rules to catch some of these patterns automatically - no empty catch blocks, no require() inside functions.
>
> But honestly, the biggest impact was documentation. I started adding comments explaining not just what the code does, but why. 'Retry 3 times because Gemini occasionally returns transient 503 errors.' Now new developers understand the reasoning, not just the code."

---

## Topic 11: LLM Integration
*Best for showing: AI/ML production experience*

**"Tell me about the AI integration challenges"**

> "The platform uses Gemini for evaluating candidate interviews. When I joined, the AI integration was basically 'call the API and hope it works.' No resilience patterns, no cost tracking, no observability.
>
> First problem: no content safety handling. Gemini can refuse to generate a response if it triggers safety filters - returns finishReason 'SAFETY' or empty candidates. The code just assumed there would always be a response. When safety filters triggered, users got cryptic errors.
>
> Second: no circuit breaker. So when Gemini had an outage - and every LLM provider has outages - every single request tried and failed. Users waited 90 seconds for timeout, then got an error. With a circuit breaker, after 5 failures you stop trying and fail fast, give users a meaningful message.
>
> Third: zero cost visibility. I'd ask 'how much did we spend on Gemini last month?' Nobody knew. 'Which company uses the most tokens?' Can't tell. 'Why did this interview evaluation fail?' No traces to debug.
>
> The good news is they already had some things right - rate limiting per API key, key rotation, context caching that saved like 90% on token costs. So it wasn't all bad.
>
> For fixes: I implemented proper response validation - check for safety blocks, empty responses, handle gracefully with fallbacks. Enabled the circuit breaker with proper thresholds. And set up Langfuse for LLM observability."

**If they ask: "What is Langfuse?"**

> "Langfuse is like Datadog but specifically for LLM calls. We self-host it. Every LLM request gets traced - we see the prompt, the response, token usage, latency, errors. We can trace a single interview through the entire AI pipeline.
>
> Now when something fails, I can pull up the exact trace, see what prompt was sent, what response came back, whether it was a content filter issue or an API error. Before, we were blind. 'Interview evaluation failed' - okay, but why? Now we know.
>
> We also track costs per company, per interview type. The business can actually see where AI spend is going. And we can identify patterns - maybe certain types of questions trigger safety filters more often. That's actionable insight."

**If they ask: "How do you handle LLM reliability?"**

> "Multiple layers. First, retry with exponential backoff for transient errors. Second, circuit breaker to fail fast during outages. Third, fallback responses - if AI evaluation completely fails, we at least save the transcript so a human can review later.
>
> For content safety, we have graceful degradation. If Gemini refuses to evaluate due to safety filters, we flag the interview for human review instead of just failing. The candidate still gets processed, just not automatically.
>
> We also monitor error rates by error type. 'Rate limited' means we need to spread load better. 'Safety filtered' means we might need to adjust prompts. 'Timeout' means the model is overloaded. Different problems, different solutions."

---

# Part 4: Passion & Startup Mindset (25-28 min)

## "Why do you want to work at a startup?"

> "I've seen both worlds now. Enterprise systems have scale, but decisions take forever and you're often just maintaining someone else's architecture. In startups, you can actually shape how things are built from the ground up.
>
> What I like about startups is the ownership. When something breaks at 2am, it's your problem - but when it works and scales, that's your success too. I'd rather have that responsibility than be a small piece of a giant machine.
>
> I also learn faster in startup environments. In my consulting role, I touched everything - infrastructure, backend, DevOps, observability, database optimization. That kind of breadth is hard to get in a larger company where roles are more siloed."

## "How do you balance speed vs quality?"

> "I don't think they're opposites, honestly. Moving fast with bad code is actually slower - you pay with debugging time, duplicate work, customer complaints. I saw this firsthand at Flowmingo.
>
> My approach is prioritize ruthlessly. Not everything needs perfect architecture. But critical paths - the things that directly affect customers, data integrity, core flows - those need to be solid. Internal admin tools? Simpler is fine.
>
> During my audit, I used P0, P1, P2 prioritization. P0 issues like crashes and duplicates got fixed immediately because they were hurting customers. Code quality improvements were P2 - important, scheduled, but not blocking everything else."

## "What drives you as an engineer?"

> "Solving real problems. The most satisfying moment at Flowmingo was watching stuck interview reports drop from 80+ per week to under 10. That's real users who can now complete their interviews without issues.
>
> I also genuinely enjoy the detective work of debugging production issues. The BullMQ lock problem took me a whole day to fully understand - tracing through how Node.js event loop blocking prevents timer callbacks. That kind of deep investigation is what I find rewarding."

## "Tell me about a time you went above and beyond"

> "The observability stack wasn't in my original scope. I was brought in for specific bug fixes. But once I saw how the team was debugging - SSHing into servers, grepping logs manually - I knew we couldn't operate properly without proper monitoring.
>
> So I built it on my own initiative. OpenTelemetry, Prometheus, Grafana, the whole thing. When we caught a payment provider issue before it affected customers, leadership suddenly understood why observability matters. After that, it became a priority.
>
> I also documented everything I found - not just the fixes, but why things were broken and how to prevent similar issues. I wanted the team to actually learn from this, not just have their problems magically fixed."

---

# Red Flags to Mention (Shows Experience)

- "synchronize: true in production TypeORM - terrifying"
- "Empty catch blocks - silent failures fill up disks"
- "In-memory state across clustered instances - race conditions"
- "SSH and git pull as a deployment process"
- "require() inside functions - loaded hundreds of times per hour"
- "Circuit breaker code existed but was commented out"
- "Hardcoded credentials in the codebase"
- "LLM calls without checking for safety filter responses"
- "No staging environment - 'works on my machine' bugs"
- "Schema changes via Slack messages - no version control"

---

# Closing Statement

> "Coming into Flowmingo as a consultant was eye-opening. I'd heard about 'vibe coding' but I'd never seen it at this scale - a production system serving thousands of users, built entirely without code review, without tests, without any understanding of software lifecycle. Just ship features as fast as possible and hope it works.
>
> Honestly, the first week was overwhelming. Every file I opened had problems. Empty catch blocks, hardcoded credentials, race conditions, memory leaks. I kept asking myself 'how is this even running?' But here's the thing - it was running. Real candidates were doing interviews. Real companies were hiring through it. The product had value, the engineering just couldn't keep up.
>
> What I found rewarding wasn't just fixing bugs. It was watching the team start to understand why these practices matter. When we set up observability and they could actually see what was happening in production - that was a shift. When we introduced code review and caught bugs before deployment instead of after - they got it. I wasn't just cleaning up code, I was helping a team level up.
>
> That's what I care about. I've seen what happens when you skip engineering fundamentals, and I've seen how much better things can be when you do it right. I want to bring that experience wherever I go next - whether it's building something new or helping a team mature their practices. I'm not just a developer who writes code. I think about how systems operate in production, how teams should work, how to build something that lasts."
