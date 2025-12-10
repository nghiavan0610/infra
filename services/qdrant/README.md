# Qdrant Vector Database

High-performance vector similarity search engine for AI applications.

## Quick Start

```bash
# Start
docker compose up -d

# Check health
curl http://localhost:6333/readyz

# List collections
curl http://localhost:6333/collections
```

## Endpoints

| Endpoint | URL |
|----------|-----|
| REST API | http://localhost:6333 |
| gRPC | localhost:6334 |
| Metrics | http://localhost:6333/metrics |
| Dashboard | http://localhost:6333/dashboard |

## Usage Examples

### Create Collection
```bash
curl -X PUT http://localhost:6333/collections/my_collection \
  -H "Content-Type: application/json" \
  -d '{
    "vectors": {
      "size": 1536,
      "distance": "Cosine"
    }
  }'
```

### Insert Vectors
```bash
curl -X PUT http://localhost:6333/collections/my_collection/points \
  -H "Content-Type: application/json" \
  -d '{
    "points": [
      {
        "id": 1,
        "vector": [0.1, 0.2, ...],
        "payload": {"text": "example"}
      }
    ]
  }'
```

### Search
```bash
curl -X POST http://localhost:6333/collections/my_collection/points/search \
  -H "Content-Type: application/json" \
  -d '{
    "vector": [0.1, 0.2, ...],
    "limit": 10
  }'
```

## Client Libraries

```bash
# Python
pip install qdrant-client

# Node.js
npm install @qdrant/js-client-rest

# Go
go get github.com/qdrant/go-client
```

### Python Example
```python
from qdrant_client import QdrantClient

client = QdrantClient(host="qdrant", port=6333)

# Create collection
client.create_collection(
    collection_name="my_collection",
    vectors_config={"size": 1536, "distance": "Cosine"}
)

# Search
results = client.search(
    collection_name="my_collection",
    query_vector=[0.1, 0.2, ...],
    limit=10
)
```

## Connection from Your Backend

In your `.env`:
```env
QDRANT_HOST=qdrant
QDRANT_PORT=6333
QDRANT_API_KEY=your-api-key
```

In your `docker-compose.yml`:
```yaml
services:
  myapp:
    environment:
      - QDRANT_HOST=qdrant
      - QDRANT_PORT=6333
    networks:
      - infra

networks:
  infra:
    external: true
```

## Backup & Restore

### Create Snapshot
```bash
curl -X POST "http://localhost:6333/collections/my_collection/snapshots"
```

### List Snapshots
```bash
curl "http://localhost:6333/collections/my_collection/snapshots"
```

### Restore
```bash
curl -X PUT "http://localhost:6333/collections/my_collection/snapshots/recover" \
  -H "Content-Type: application/json" \
  -d '{"location": "file:///qdrant/snapshots/my_collection/snapshot.snapshot"}'
```

## Performance Tuning

For large datasets (1M+ vectors), adjust in `.env`:

```env
# Use more RAM for better performance
QDRANT_MEMORY_LIMIT=4G

# Lower threshold = faster queries, more RAM
QDRANT_MEMMAP_THRESHOLD=100000

# Use all CPUs for search
QDRANT_MAX_SEARCH_THREADS=0
```

## Monitoring

Metrics available at: http://localhost:6333/metrics

Grafana dashboard: Import ID `18406` (Qdrant dashboard)
