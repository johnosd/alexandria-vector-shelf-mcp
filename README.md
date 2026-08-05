# alexandria-vector-shelf-mcp

A production-grade RAG pipeline for epub books, designed to evolve into a fully compliant MCP server.

Ingest any epub → query it semantically → expose your reading library as context to any LLM agent.

Built as a portfolio project demonstrating RAG engineering, vector search, and agentic AI integration
patterns — running entirely on Google Cloud Platform / Firebase.

---

## What this project is

`alexandria-vector-shelf-mcp` is a backend system that processes epub books and enables semantic
conversation with their content. It is intentionally built in two stages:

**Stage 1 — RAG Service (Phases 1–4):** Two independent microservices — an ingestion pipeline and
a chat API — backed entirely by Firebase and Google Cloud. Any client can upload an epub, wait for
processing, and then chat with it via streaming.

**Stage 2 — MCP Server (Phase 5):** The same retrieval logic is wrapped with the Model Context
Protocol SDK, making the entire reading library available as context tools to any MCP-compatible
agent (Claude Desktop, Cursor, custom agents).

The core retrieval logic (`shared/retriever.py`) is written once and shared by both stages.
No rewriting, no duplication.

---

## Architecture overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                          Clients                                    │
│                                                                     │
│   NeoReader App          Claude Desktop        Cursor / Agent       │
│   (mobile, SSE)          (MCP client)          (MCP client)         │
└────────┬────────────────────────┬───────────────────┬──────────────┘
         │ HTTP + SSE             │ MCP protocol      │ MCP protocol
         ▼                        ▼                   ▼
┌─────────────────┐    ┌────────────────────────────────────────────┐
│  Chat Service   │    │              MCP Server                    │
│  Cloud Run      │    │              Phase 5                       │
│                 │    │  tools: search_book, ingest_epub           │
│  FastAPI + SSE  │    │  resources: library://books                │
│  gemini-flash   │    │  prompts: analyze_book                     │
└────────┬────────┘    └──────────────┬─────────────────────────────┘
         │                            │
         └────────────┬───────────────┘
                      │ calls retrieve()
                      ▼
             ┌──────────────────┐
             │  shared/         │
             │  retriever.py    │  ← heart of the system
             │  embedder.py     │
             │  models.py       │
             └────────┬─────────┘
                      │
                      ▼
        ┌─────────────────────────────────┐
        │  Firebase / Google Cloud        │
        │                                 │
        │  Firestore  (chunks + vectors)  │  ← vector search native
        │  Firestore  (books catalog +    │  ← global, shared across users
        │              user_library)      │  ← per-user shelf (ADR-006)
        │  Firebase Storage  (.epub)      │
        │  Firebase Auth  (user_id)       │
        │  Firestore Realtime  (status)   │
        └─────────────────────────────────┘
                      ▲
                      │ dedup → parse → chunk → embed → store
                      │
        ┌─────────────────────────────────┐
        │  Ingestion Service              │
        │  Google Cloud Run               │
        │                                 │
        │  library_manager.py             │  ← dedup gate, ADR-006
        │  parser.py                      │
        │  chunker.py                     │
        │  embedder.py                    │
        │  store.py                       │
        └─────────────────────────────────┘
```

---

## Design principles

**100% Google Cloud.** Every service runs on Firebase or GCP. One account, one console,
one IAM, one billing dashboard. No external dependencies.

**Separation of concerns.** The ingestion pipeline and the chat service are independent
microservices. They share data through Firestore, not through direct coupling.

**Retriever as the stable interface.** `shared/retriever.py` defines a typed contract
(`list[ChunkResult]`) that never changes. The chat service and the MCP server both call it.
The underlying database implementation can be swapped (Firestore → Weaviate) without
touching anything else.

**Built to migrate.** Every architectural decision is documented in an ADR with a migration path.
Pub/Sub can be added before Cloud Run without changing `process_epub()`. Weaviate can replace
Firestore vector search by changing one file.

**Documented as it is built.** Every non-obvious decision has an ADR. Every concept introduced
in the code has a corresponding notebook. The project is designed to be readable by someone
learning RAG engineering.

---

## Repository structure

```
alexandria-vector-shelf-mcp/
│
├── ingestion/                  # Microservice 1 — Google Cloud Run (serverless)
│   ├── main.py                 # FastAPI entrypoint — POST /library/books
│   ├── library_manager.py      # dedup gate: file hash → ISBN → content hash → fuzzy match (ADR-006)
│   │                           # + Pydantic AI metadata fallback when OPF is unusable (ADR-009)
│   ├── parser.py               # epub → clean text (EbookLib + BeautifulSoup4)
│   ├── chunker.py              # text → overlapping chunks
│   ├── embedder.py             # chunks → Vertex AI / OpenAI embeddings (LangChain, ADR-007)
│   ├── store.py                # embeddings → Firestore vector collection
│   ├── pyproject.toml          # uv workspace member, depends on shared (ADR-008)
│   └── Dockerfile
│
├── chat/                       # Microservice 2 — Google Cloud Run (always-on)
│   ├── main.py                 # FastAPI entrypoint — GET /chat (SSE)
│   ├── prompt.py               # chunks + question → RAG prompt
│   ├── streamer.py             # prompt → Gemini Flash → SSE stream (LangChain, ADR-007)
│   ├── pyproject.toml          # uv workspace member, depends on shared (ADR-008)
│   └── Dockerfile
│
├── mcp/                        # Phase 5 — MCP Server
│   ├── server.py               # MCP SDK entrypoint
│   ├── tools.py                # wraps shared/retriever.py as MCP tools
│   ├── resources.py            # exposes book library as MCP resources
│   ├── prompts.py              # reusable MCP prompt templates
│   ├── pyproject.toml          # uv workspace member, depends on shared (ADR-008)
│   └── Dockerfile
│
├── shared/                     # Shared logic — imported by all services
│   ├── __init__.py
│   ├── pyproject.toml          # real uv workspace package (ADR-008)
│   ├── db.py                   # Firestore client (singleton)
│   ├── models.py               # Pydantic schemas (ChunkResult, Book, etc.)
│   └── retriever.py            # THE stable interface — never changes signature
│
├── notebooks/                  # Learning artifacts — one per concept
│   ├── 01_embeddings_explained.ipynb
│   ├── 02_chunking_strategies.ipynb
│   ├── 03_retrieval_evaluation.ipynb
│   ├── 04_firestore_vs_weaviate.ipynb
│   └── 05_mcp_demo.ipynb
│
├── docs/
│   ├── schema.md               # Firestore collection design
│   ├── DEVELOPMENT.md          # recommended MCP servers for AI-assisted dev on this repo
│   ├── BIBLIOGRAPHY.md         # learning resources + technical reference, by phase/ADR
│   ├── ARCHITECTURE.md         # Deep dive into design decisions
│   ├── comparisons/
│   │   └── GCP_vs_AWS.md       # Full stack comparison GCP vs AWS
│   └── adr/
│       ├── ADR-001-vector-database.md
│       ├── ADR-002-stack-selection.md
│       ├── ADR-003-chunk-strategy.md
│       ├── ADR-004-prompt-design.md
│       ├── ADR-005-mcp-integration.md
│       ├── ADR-006-library-deduplication.md
│       ├── ADR-007-scoped-langchain-adoption.md
│       ├── ADR-008-uv-dependency-management.md
│       └── ADR-009-pydantic-ai-structured-outputs.md
│
├── tests/
│   ├── test_parser.py
│   ├── test_chunker.py
│   ├── test_embedder.py
│   ├── test_retriever.py
│   └── test_integration.py
│
├── .env.example
├── docker-compose.yml
├── Makefile
├── pyproject.toml              # uv workspace root (ADR-008)
├── uv.lock                     # single lockfile for the whole workspace
├── .gitignore
├── PHASE_1_SETUP.md
└── README.md                   ← you are here
```

---

## Tech stack — 100% Google Cloud

| Layer | Technology | Why |
|---|---|---|
| Language | Python 3.11 | async support, rich AI ecosystem |
| API framework | FastAPI | async, auto docs, SSE support |
| Vector database | Firestore vector search | native KNN, same platform as auth/storage/realtime |
| Embeddings | Vertex AI text-embedding-004 or OpenAI text-embedding-3-small | both work, Vertex AI keeps everything in GCP |
| LLM | Gemini 1.5 Flash | cheapest capable Google model, native GCP integration |
| Ingestion compute | Cloud Run (serverless) | pay-per-use, zero cost when idle |
| Chat compute | Cloud Run (min-instances=1) | always-on via min instance setting, no cold start |
| Storage | Firebase Storage | epub files, same account as everything else |
| Auth | Firebase Auth | anonymous + Google OAuth, battle-tested |
| Realtime status | Firestore Realtime | live processing status, built into Firestore |
| MCP protocol | Anthropic MCP Python SDK | official SDK, Claude Desktop compatible |
| Epub parsing | EbookLib + BeautifulSoup4 | mature, handles malformed epubs |
| Library dedup | rapidfuzz | fuzzy title/author matching for catalog dedup (ADR-006) — small, not a framework |
| Embeddings client | LangChain (`Embeddings` interface) | provider-agnostic Vertex AI ↔ OpenAI swap, batching/retry built in — scoped to `embedder.py` (ADR-007) |
| Chat LLM client | LangChain (`BaseChatModel` interface) | provider-agnostic streaming call to Gemini Flash — scoped to `chat/streamer.py` (ADR-007) |
| Dependency management | uv workspaces | one lockfile across ingestion/chat/mcp/shared — no cross-service version drift (ADR-008) |
| Structured LLM output | Pydantic AI | typed, validated output for the RAG eval judge and the metadata-extraction fallback — not chat/embedding (ADR-009) |
| MCP server framework | FastMCP | official SDK's built-in `FastMCP` for local stdio mode; standalone `fastmcp` package as the candidate if remote mode is ever built (ADR-005) |
| Containerization | Docker | consistent environments |

---

## Firestore collection design

`books` and `chunks` form a **global catalog** shared by all users — a book
uploaded by one user is not reprocessed if another user uploads the same one.
Per-user ownership lives separately in `user_library`. See ADR-006 and
`docs/schema.md` for the full deduplication design.

```
firestore/
│
├── users/{user_id}
│   ├── displayName: string
│   └── createdAt: timestamp
│
├── books/{book_id}                    ← global catalog, not user-owned
│   ├── isbn: string | null            ← normalized ISBN-13, checksum-validated
│   ├── title: string | null
│   ├── author: string | null
│   ├── language: string | null        ← ISO 639-1, from epub dc:language
│   ├── normalized_title: string       ← fuzzy-match key
│   ├── normalized_author: string      ← fuzzy-match key
│   ├── file_hash: string              ← sha256 of raw .epub bytes
│   ├── content_hash: string | null    ← sha256 of extracted normalized text
│   ├── possibly_duplicate_of: string | null  ← fuzzy candidate, flagged not merged
│   ├── epub_path: string              ← path in Firebase Storage
│   ├── status: string                 ← pending | processing | ready | error
│   ├── chunk_count: number
│   ├── error_message: string | null
│   ├── created_at: timestamp
│   └── updated_at: timestamp
│
├── user_library/{user_id}/books/{book_id}   ← the "shelf", per user
│   └── added_at: timestamp
│
└── chunks/{chunk_id}                  ← global catalog, not user-owned
    ├── book_id: string
    ├── content: string
    ├── embedding: Vector(1536)        ← Firestore native vector type
    ├── chunk_index: number
    ├── chapter: string | null
    └── created_at: timestamp
```

**Vector index** (created via gcloud CLI before first query):
```bash
gcloud firestore indexes composite create \
  --collection-group=chunks \
  --query-scope=COLLECTION \
  --field-config=order=ASCENDING,field-path="book_id" \
  --field-config=field-path="embedding",vector-config='{"dimension":"1536","flat":"{}"}'
```

---

## API contracts

### Ingestion Service — `POST /library/books`

The public entry point (ADR-006). The client no longer pre-creates a `book_id` —
the Library Manager decides it, after running the Tier 0-3 deduplication checks
(file hash, ISBN, content hash, fuzzy title/author) against the global catalog.

```
Request body (JSON)
  epub_path  string   Path of the epub already uploaded to Firebase Storage
  user_id    string   Firebase Auth UID

Response 202 Accepted
  book_id        string   Catalog book ID (existing or newly created)
  status         string   "processing" | "ready"
  deduplicated   bool     true if matched an existing book — no reprocessing triggered

Status updates delivered via Firestore Realtime on books/{book_id}.status
```

### Chat Service — `GET /chat`

```
Request (query params)
  book_id   string   Firestore book document ID
  user_id   string   Firebase Auth UID
  question  string   User's question (max 2000 chars)

Response  text/event-stream (SSE)
  data: {"token": "The"}
  data: {"token": " answer"}
  ...
  data: [DONE]
```

### Retriever interface (internal — shared by chat and MCP)

```python
async def retrieve(
    question_embedding: list[float],
    book_id: str,
    top_k: int = 5
) -> list[ChunkResult]:
    ...

# This signature NEVER changes regardless of which database backs it.
```

---

## Roadmap

### Phase 1 — Foundation `week 1`
Firebase project setup, Firestore collection design, vector index creation,
repository structure, first two ADRs.

**Deliverables:** Firebase project configured, Firestore indexes created,
repo structure, README, ADR-001, ADR-002, `.env.example`, `PHASE_1_SETUP.md`

### Phase 2 — Ingestion Service `week 2–3`
Complete epub processing pipeline deployed to Cloud Run, including the
Library Manager dedup gate in front of it.

**Deliverables:** Cloud Run deployed, pipeline testable via `curl`,
`notebooks/02_chunking_strategies.ipynb`, ADR-003, ADR-006

### Phase 3 — Chat Service `week 4`
Retrieval and streaming chat API with stable retriever interface.

**Deliverables:** Cloud Run always-on deployed, SSE streaming end-to-end,
retriever interface abstracted for future migration, ADR-004, ADR-007

### Phase 4 — Hardening + Docs `week 5`
Integration tests, RAG evaluation, full documentation.

**Deliverables:** integration tests, evaluation notebooks,
`ARCHITECTURE.md`, Weaviate migration guide, `docker-compose.yml`

### Phase 5 — MCP Server `week 6–7`
MCP SDK wrapper exposing retrieval as tools for any LLM agent.

**Deliverables:** MCP server tested with Claude Desktop,
`mcp/` module complete, ADR-005, demo notebook

---

## Local development

```bash
cp .env.example .env        # fill in your Firebase and Google Cloud credentials
uv sync                     # install the whole workspace into one .venv (ADR-008)
docker-compose up           # start all services locally
make test                   # run all tests
make ingest EPUB_PATH=...   # test the /library/books pipeline via curl (ADR-006)
```

---

## Environment variables

```bash
# Google Cloud / Firebase
GOOGLE_CLOUD_PROJECT=
FIREBASE_STORAGE_BUCKET=
GOOGLE_APPLICATION_CREDENTIALS=./service-account.json   # local dev only

# Embeddings (choose one)
OPENAI_API_KEY=                          # option A: OpenAI embeddings
VERTEX_AI_LOCATION=us-central1           # option B: Vertex AI embeddings

# LLM
GEMINI_API_KEY=                          # or use Application Default Credentials

# Service config
INGESTION_SERVICE_URL=http://localhost:8001
CHAT_SERVICE_URL=http://localhost:8002
ENVIRONMENT=development

# Chunking
CHUNK_SIZE=500
CHUNK_OVERLAP=50

# Retrieval
RETRIEVAL_TOP_K=5
```

---

## Learning resources

**Before starting**
- [DeepLearning.AI — Building Systems with the ChatGPT API](https://www.deeplearning.ai/short-courses/building-systems-with-chatgpt/) — RAG fundamentals, free
- [Andrej Karpathy — Intro to Large Language Models](https://www.youtube.com/watch?v=zjkBMFhNj_g) — best LLM intro
- [Firebase Firestore Vector Search docs](https://firebase.google.com/docs/firestore/vector-search) — read before Phase 1

**Phase 2 — Chunking and embeddings**
- *Hands-On Large Language Models* — Jay Alammar & Maarten Grootendorst (O'Reilly 2024)
- [Greg Kamradt — 5 Levels of Text Splitting](https://www.youtube.com/watch?v=8OJC21T2SL4)
- [Pinecone — Chunking Strategies](https://www.pinecone.io/learn/chunking-strategies/)

**Phase 3 — Retrieval and RAG**
- [DeepLearning.AI — Building and Evaluating Advanced RAG](https://www.deeplearning.ai/short-courses/building-evaluating-advanced-rag/)
- [RAG original paper — Lewis et al. 2020](https://arxiv.org/abs/2005.11401)
- *Building LLMs for Production* — Maximilian Ott (Manning 2024)

**Phase 4 — Evaluation**
- [DeepLearning.AI — Evaluating and Debugging Generative AI](https://www.deeplearning.ai/short-courses/evaluating-debugging-generative-ai/)
- *Designing Machine Learning Systems* — Chip Huyen (O'Reilly 2022)

**Phase 5 — MCP**
- [Model Context Protocol — Official Introduction](https://modelcontextprotocol.io/introduction)
- [MCP Python SDK](https://github.com/modelcontextprotocol/python-sdk)
- [Awesome MCP Servers](https://github.com/punkpeye/awesome-mcp-servers)

**Ongoing reference**
- [Firestore vector search docs](https://firebase.google.com/docs/firestore/vector-search)
- [Vertex AI text embeddings](https://cloud.google.com/vertex-ai/generative-ai/docs/embeddings/get-text-embeddings)
- [Lilian Weng — Prompt Engineering](https://lilianweng.github.io/posts/2023-03-15-prompt-engineering/)

---

## Author

Built by Johnny as a portfolio project in AI/Data Engineering.
Demonstrates end-to-end RAG system design on Google Cloud Platform,
from epub ingestion to MCP server — 100% within the Firebase/GCP ecosystem.
