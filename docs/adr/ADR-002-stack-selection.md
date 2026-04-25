# ADR-002: Stack and Infrastructure Selection

## Status
Accepted

## Date
2025-01

## Context

alexandria-vector-shelf-mcp is a backend system with two independent microservices:

1. **Ingestion Service** — processes epub files (parse, chunk, embed, store).
   Called once per book upload. Processing takes 10–60 seconds.
   No latency requirement at call time — user sees a "processing" status screen.

2. **Chat Service** — answers questions using RAG.
   Called on every user message. Latency is critical — cold starts are unacceptable.

Strategic constraint: **everything must run within the Google Cloud / Firebase ecosystem.**
One account, one console, one IAM, one billing dashboard. No external services.

Additional constraints:
- Minimum possible cost (single user, personal/portfolio project)
- Python 3.11 (author's primary language)
- No unnecessary frameworks or abstractions
- Code must be readable by someone learning RAG engineering

## Decisions

### Platform: 100% Google Cloud / Firebase

All services run within a single GCP project. This means:
- Firebase Auth for user identity
- Firebase Storage for epub files
- Firestore for chunks, embeddings, and book status (with Realtime built in)
- Cloud Run for both ingestion and chat compute
- Vertex AI for embeddings (or OpenAI as fallback — same interface)
- Gemini for LLM generation

This eliminates Supabase, Fly.io, Railway, and any other external dependency.

**Tradeoff accepted:** Firebase/Firestore has a steeper initial learning curve than
Supabase for developers coming from a SQL background. This is offset by the benefit
of mastering the GCP ecosystem end-to-end, which is valuable for portfolio positioning.

### Language: Python 3.11
Rich AI/ML ecosystem. Mature asyncio support. First-class SDKs for Firebase Admin,
Google Cloud, and OpenAI.

### API Framework: FastAPI
Async request handling, automatic OpenAPI docs, Pydantic validation, native SSE support.
Standard for Python AI services.

**Rejected:** Flask (no async), Django (too heavy)

### Ingestion Compute: Cloud Run (serverless, no minimum instances)
Serverless — spins up on request, shuts down when idle. Near-zero cost for a service
called a few times per day. Cold start (3–8s) is acceptable for ingestion since the
user is already waiting for processing.

**Pub/Sub readiness:** The `process_epub()` function is designed so that Google Cloud
Pub/Sub can invoke it as a consumer later without internal changes. See ADR-002 note
on future evolution.

### Chat Compute: Cloud Run (always-on via min-instances=1)
Cold start is unacceptable for chat. Cloud Run supports `--min-instances=1`, which
keeps one container always warm. Cost is approximately $5-8/month for a small instance
kept alive — equivalent to Fly.io but within the same GCP account.

```bash
gcloud run deploy chat-service \
  --min-instances=1 \
  --max-instances=10 \
  ...
```

**Rejected:**
- Cloud Run with 0 min instances: cold start kills chat UX
- Cloud Functions: less control over runtime, no persistent connections for SSE
- GKE: massive overkill for single-user MVP

### Embeddings: Vertex AI text-embedding-004 (primary) / OpenAI (fallback)

Vertex AI `text-embedding-004` produces 768-dimensional vectors by default,
configurable up to 3072 dimensions. It runs within GCP — no data leaves the network.
The `embedder.py` module abstracts the provider so switching is a one-line config change.

**Important constraint:** The embedding model must never change after the first ingestion.
All stored vectors and all query-time embeddings must use the same model.
See `.env.example` — `EMBEDDING_MODEL` is set once and treated as immutable.

**OpenAI text-embedding-3-small as fallback:** If Vertex AI quotas are an issue during
development, OpenAI's model produces 1536 dimensions and is also supported. The interface
in `embedder.py` is identical for both.

### LLM: Gemini 1.5 Flash
Cheapest capable Google model. Excellent for RAG-style prompts where the answer is
grounded in retrieved context. Native GCP integration — no separate API key needed
beyond Application Default Credentials.

**Rejected:**
- GPT-4o-mini: works well but adds an external API dependency (OpenAI)
- Gemini Ultra: overkill and expensive for a chat-with-book use case
- Gemini Nano: not available via API

### RAG Framework: None (direct API calls)
LangChain and LlamaIndex were evaluated and rejected.

Reasons:
- The RAG pipeline is 4 sequential steps — no orchestration framework needed
- Direct API calls give full control over chunking strategy (most critical RAG variable)
- Frameworks add abstraction layers that make debugging harder for someone learning RAG
- LangChain has broken API compatibility multiple times between versions
- The `retriever.py` interface pattern achieves the same decoupling without a framework

### Epub Processing: EbookLib + BeautifulSoup4
EbookLib is the standard Python library for epub. BeautifulSoup4 strips HTML from
epub chapters (which are HTML documents internally). Both are mature and well-maintained.

## Consequences

### Positive
- Single GCP account covers everything — one dashboard, one IAM, one bill
- No data leaves GCP at any point in the pipeline
- Portfolio demonstrates full GCP ecosystem mastery
- Cloud Run min-instances solves cold start without a separate always-on server
- Firebase Security Rules + Firebase Auth provide solid multi-user isolation
  when the project grows beyond single-user

### Negative
- Firestore is a document database — no SQL, no JOINs, no complex aggregations
- Cloud Run min-instances costs ~$5-8/month (versus $0 with Fly.io free tier)
- Vertex AI embeddings have regional availability constraints
- Firebase Admin SDK (Python) is less ergonomic than supabase-py for some operations

### Future evolution
- **Pub/Sub:** Add Cloud Pub/Sub between the NeoReader app and Cloud Run ingestion
  when concurrent users require queue management. `process_epub()` becomes a Pub/Sub
  consumer with zero internal changes.
- **Vector search:** Migrate from Firestore vector search to Weaviate (on GKE or cloud)
  when hybrid search (BM25 + vector) becomes necessary. Only `retriever.py` changes.
- **MCP Server (Phase 5):** New `mcp/` module added on top of existing infrastructure.
  No changes to ingestion or chat services.
- **Scale:** Cloud Run auto-scales horizontally. Firestore scales automatically.
  The architecture supports growth without infrastructure rewrites.
