# ADR-002: Stack and Infrastructure Selection

## Status
Accepted

## Date
2025-01

## Context

alexandria-vector-shelf-mcp is a backend system with two independent microservices:

1. **Ingestion Service** — processes epub files (parse, chunk, embed, store).
   Called once per book upload. Processing takes 10–60 seconds depending on book size.
   No latency requirements at call time — the user is shown a "processing" status.

2. **Chat Service** — answers questions about a book using RAG.
   Called on every user message. Latency is critical — cold starts are unacceptable.

Constraints:
- Minimum possible cost (single user, personal project)
- Python ecosystem (author's primary language)
- No unnecessary frameworks or abstractions
- Code must be readable and debuggable by someone learning RAG engineering

## Decisions

### Language: Python 3.11
Python has the richest ecosystem for AI/ML engineering. `asyncio` support in 3.11
is mature and stable. All relevant libraries (httpx, openai, supabase-py, fastapi,
ebooklib, beautifulsoup4) have first-class Python support.

### API Framework: FastAPI
FastAPI provides async request handling, automatic OpenAPI documentation, Pydantic
validation, and native Server-Sent Events (SSE) support. It is the standard choice
for Python AI services.

**Rejected:** Flask (no async), Django (too heavy), raw ASGI (too low-level)

### Ingestion Compute: Google Cloud Run
Cloud Run is serverless — the container spins up on request and shuts down when idle.
For a service that is called at most a few times per day, this means near-zero cost.
Cold start of 3–8 seconds is acceptable for the ingestion use case.

**Rejected:** Always-on VPS (unnecessary cost for an infrequently called service),
AWS Lambda (Python cold start worse than Cloud Run, less memory for epub processing)

### Chat Compute: Fly.io
The chat service must have no cold start. An always-on container is required.
Fly.io provides a free tier with one always-on container and has excellent
latency characteristics for streaming workloads.

**Rejected:**
- Hugging Face Spaces: free tier sleeps after inactivity, defeating the purpose
- Cloud Run: cold start unacceptable for chat latency
- Railway: viable alternative to Fly.io, similar cost (~$5/month)

### RAG Framework: None (direct API calls)
LangChain and LlamaIndex were evaluated and rejected for this project.

Reasons:
- The RAG pipeline is simple enough (4 sequential steps) to not need orchestration
- Frameworks add abstraction layers that make debugging harder
- LangChain's API has broken compatibility between versions multiple times
- Direct API calls give full control over chunking strategy, which is the most
  critical factor in RAG quality
- When migrating from pgvector to Weaviate, only `retriever.py` changes — no
  framework migration required

The system uses `openai` Python SDK, `httpx` for async HTTP, and `supabase-py`
for database operations. Total dependencies are minimal.

### Epub Processing: EbookLib + BeautifulSoup4
EbookLib is the standard Python library for reading epub files. BeautifulSoup4
is used to strip HTML tags from epub chapters, which are HTML documents internally.

**Rejected:** Tika (Java dependency, overkill), Calibre (binary tool, hard to
containerize), pypdf (PDF only)

## Consequences

### Positive
- Minimal cost: Cloud Run + Fly.io free tiers cover single-user MVP at ~$0/month
- Full control over every step of the pipeline
- Easy to read, debug, and explain in a portfolio context
- No framework migration debt when scaling

### Negative
- More boilerplate than framework-based approaches
- SSE streaming requires manual implementation (not a framework abstraction)
- Cloud Run cold starts require client-side handling (status polling via Realtime)

### Future evolution
When the project scales beyond single-user:
- Chat Service: migrate to a VPS with more resources or Kubernetes
- Ingestion: add Google Cloud Pub/Sub before Cloud Run for queue management
  (the `process_epub()` function signature is already designed for this — it can
  become a Pub/Sub consumer without internal changes)
- MCP Server (Phase 5): new `mcp/` module added on top of existing infrastructure,
  no changes to existing services
