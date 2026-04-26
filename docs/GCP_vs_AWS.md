# Stack Comparison: GCP vs AWS

## Purpose

This document exists as a reference comparison — not as a decision to be made.
**alexandria-vector-shelf-mcp uses 100% Google Cloud / Firebase** (see ADR-002).

This comparison is included for two reasons:
1. Portfolio value — demonstrates understanding of both ecosystems
2. Future reference — if the project ever needs to be ported or adapted for a
   client running on AWS

---

## Side-by-side: Every service, both platforms

| Responsibility | GCP / Firebase (chosen) | AWS equivalent |
|---|---|---|
| **Auth** | Firebase Auth | Amazon Cognito |
| **Storage (epub files)** | Firebase Storage | Amazon S3 |
| **Vector database** | Firestore vector search | Amazon OpenSearch (k-NN plugin) or Amazon Aurora pgvector |
| **Realtime status** | Firestore Realtime listeners | AWS AppSync (GraphQL subscriptions) or API Gateway WebSocket |
| **Ingestion compute** | Cloud Run (serverless) | AWS Lambda + ECS Fargate |
| **Chat compute** | Cloud Run (min-instances=1) | ECS Fargate (always-on) or App Runner |
| **Embeddings** | Vertex AI text-embedding-004 | Amazon Titan Embeddings (Bedrock) |
| **LLM** | Gemini 1.5 Flash | Claude 3 Haiku or Llama 3 (Bedrock) |
| **Queue (future)** | Cloud Pub/Sub | Amazon SQS |
| **Container registry** | Artifact Registry | Amazon ECR |
| **Secrets** | Secret Manager | AWS Secrets Manager |
| **Logging** | Cloud Logging | Amazon CloudWatch |
| **SDK (Python)** | `firebase-admin`, `google-cloud-firestore` | `boto3`, `aws-cdk` |

---

## Architecture comparison

### GCP / Firebase

```
NeoReader App
    │
    ├── Firebase Auth          ← identity
    ├── Firebase Storage       ← epub files
    │
    ├── Cloud Run (ingestion)  ← serverless, $0 idle
    │       └── writes to Firestore
    │
    ├── Cloud Run (chat)       ← min-instances=1, always on
    │       └── reads from Firestore
    │
    └── Firestore              ← chunks + vectors + status + realtime
```

### AWS

```
NeoReader App
    │
    ├── Cognito                ← identity
    ├── S3                     ← epub files
    │
    ├── Lambda + SQS           ← ingestion (event-driven)
    │       └── writes to OpenSearch / Aurora pgvector
    │
    ├── ECS Fargate            ← chat service (always-on task)
    │       └── reads from OpenSearch / Aurora pgvector
    │
    ├── OpenSearch or Aurora   ← vector search
    └── AppSync                ← realtime status updates
```

---

## Cost comparison (single user, MVP)

| Service | GCP / Firebase | AWS |
|---|---|---|
| Auth | Free (Spark plan) | Free (50k MAU) |
| Storage | Free (5GB) | Free (5GB S3) |
| Vector search | Free (Firestore Spark) | OpenSearch: ~$25-50/month · Aurora pgvector: ~$15/month |
| Realtime | Free (Firestore) | AppSync: ~$2/month · API GW WebSocket: ~$1/month |
| Ingestion compute | Free (Cloud Run, 2M req/month) | Lambda: Free (1M req/month) |
| Chat compute (always-on) | ~$5-8/month (Cloud Run min=1) | ~$15-20/month (Fargate always-on) |
| Embeddings | Free (Vertex AI generous free tier) | Bedrock Titan: ~$0.0001/1K tokens |
| LLM | Gemini Flash: ~$0.075/1M tokens | Claude Haiku via Bedrock: ~$0.25/1M tokens |
| **Estimated total** | **~$5-8/month** | **~$40-75/month** |

**GCP wins on cost for this use case** — primarily because Firestore's free tier eliminates
the need for a paid vector database service, which is the dominant cost on AWS.

---

## Developer experience comparison

| Dimension | GCP / Firebase | AWS |
|---|---|---|
| Initial setup complexity | Low (Firebase console is beginner-friendly) | High (IAM, VPC, security groups) |
| Python SDK quality | Good (`google-cloud-*` libraries) | Excellent (`boto3` is very mature) |
| Local emulation | Excellent (Firebase Emulator Suite) | Good (LocalStack, SAM CLI) |
| Documentation | Good, improving | Excellent, very extensive |
| Ecosystem maturity | Strong for mobile/web apps | Strongest for enterprise backend |
| Learning curve for ML/AI | Low (Vertex AI integrated) | Medium (Bedrock is newer) |

---

## Vector search quality comparison

| Dimension | Firestore vector search | OpenSearch k-NN | Aurora pgvector | Weaviate Cloud |
|---|---|---|---|---|
| Search type | Pure KNN (cosine, euclidean, dot) | KNN + hybrid (BM25 + vector) | Pure KNN (cosine, L2) | KNN + hybrid (BM25 + vector) |
| Hybrid search | ❌ Not available | ✅ Native | ❌ Manual with tsvector | ✅ Native |
| Setup complexity | Medium (gcloud index command) | High (cluster config) | Medium (SQL extension) | Low (managed cloud) |
| Cost (MVP) | Free | ~$25-50/month | ~$15/month | Free 14 days, then ~$25/month |
| Scales to | Millions of docs | Billions of docs | Hundreds of millions | Billions of docs |
| SQL/analytics | ❌ Document model | ❌ Search index model | ✅ Full SQL | ❌ GraphQL only |
| Platform | GCP native | AWS native | AWS native | Cloud-agnostic |
| Migration path | Change retriever.py only | Change retriever.py only | Change retriever.py only | Change retriever.py only |

**When to use OpenSearch (AWS):** If hybrid search is required from day one and the project
is already on AWS. The BM25 + vector combination significantly improves retrieval quality
for queries containing proper nouns (character names, technical terms).

**When to use Aurora pgvector (AWS):** If the project needs both vector search and relational
data (complex user data models, reporting) and SQL is preferred over document queries.

---

## Code portability

The project architecture is designed so that porting to AWS requires changing exactly
**two files**:

**`shared/db.py`** — swap Firebase Admin SDK for boto3/AppSync client

**`shared/retriever.py`** — swap Firestore KNN query for OpenSearch or pgvector query

The function signature never changes:
```python
async def retrieve(
    question_embedding: list[float],
    book_id: str,
    top_k: int = 5
) -> list[ChunkResult]:
```

Everything else — parser, chunker, embedder, prompt builder, streamer, MCP server —
is platform-agnostic Python. A port from GCP to AWS could be completed in a single day.

---

## Recommendation

**Stay on GCP for this project.** The cost advantage is significant (~$5/month vs ~$40-75/month),
the Firestore-as-vector-database decision eliminates a major paid dependency, and the
Firebase ecosystem provides everything needed in a single account.

**Consider AWS if:**
- The project needs to integrate with an existing AWS workload
- Hybrid search (BM25 + vector) is required from Phase 1
- The team has deep AWS expertise and the learning curve of GCP is a constraint
- The project grows to require Aurora's relational capabilities alongside vector search
