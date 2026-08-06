# alexandria-vector-shelf-mcp

A production-grade RAG pipeline for epub books, designed to evolve into a fully compliant MCP server.

Ingest any epub → query it semantically → expose your reading library as context to any LLM agent.

Built as a portfolio project demonstrating RAG engineering, vector search, and agentic AI integration
patterns — running entirely on Google Cloud Platform / Firebase.

---

## Current implementation status

This README documents the full target architecture (Phases 1–5). As of now, only a
slice of it is actually built:

| Component | Status |
|---|---|
| `shared/` — `models.py`, `db.py`, `retriever.py` | ✅ implemented |
| `shared/embedder.py` | ❌ not started (referenced by ADR-007, no file yet) |
| `ingestion/` (parser, chunker, embedder, store, library_manager, FastAPI app) | ❌ empty directory, no files |
| `chat/` (FastAPI app, prompt builder, streamer) | ❌ empty directory, no files |
| `mcp/` (server, tools, resources, prompts) | ❌ empty directory, no files |
| `notebooks/` | ❌ empty — see `docs/training/` for the notebooks that do exist |
| `tests/` | ❌ empty — no test suite yet despite `unit`/`integration` markers being configured |
| `docker-compose.yml` | ❌ referenced by `make dev` but does not exist |
| `infra/` (Terraform) | ⚠️ root module (`main.tf`) references `./modules/{iam,storage,firestore,cloud_run}`, which don't exist at that path — `terraform init`/`plan` would fail today |

Everything below the line describes the intended end state, not what runs today.
Treat the "Repository structure" and "Roadmap" sections as a design target.

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

**GCP-first, not GCP-only.** Every service defaults to Firebase or GCP — one account,
one console, one IAM, one billing dashboard. A non-GCP dependency is accepted when it
clears a real, written-down gain (ADR-010), e.g. Google Books/Open Library for book
metadata lookup. The default is single-vendor simplicity; exceptions are deliberate,
not accidental.

**Separation of concerns.** The ingestion pipeline and the chat service are independent
microservices. They share data through Firestore, not through direct coupling.

**Retriever as the stable interface.** `shared/retriever.py` defines a typed contract
(`list[ChunkResult]`) that never changes. The chat service and the MCP server both call it.
The underlying database implementation can be swapped without touching anything else —
see ADR-001's migration path for current candidates if that's ever needed.

**Built to migrate.** Every architectural decision is documented in an ADR with a migration path.
Pub/Sub can be added before Cloud Run without changing `process_epub()`. A different vector
database can replace Firestore vector search by changing one file, `shared/retriever.py`
(ADR-001) — though a Firestore-only hybrid search path should be tried first (see backlog).

**Documented as it is built.** Every non-obvious decision has an ADR. Every concept introduced
in the code has a corresponding notebook. The project is designed to be readable by someone
learning RAG engineering.

---

## Repository structure

```
alexandria-vector-shelf-mcp/
│
├── ingestion/                  # ❌ EMPTY — Microservice 1, planned for Google Cloud Run (serverless)
│   ├── main.py                 # FastAPI entrypoint — POST /library/books
│   ├── library_manager.py      # dedup gate: file hash → ISBN → content hash → fuzzy match (ADR-006)
│   │                           # + LangChain metadata fallback when OPF is unusable (ADR-011)
│   ├── parser.py               # epub → clean text (EbookLib + BeautifulSoup4)
│   ├── chunker.py              # text → overlapping chunks
│   ├── embedder.py             # chunks → Vertex AI / OpenAI embeddings (LangChain, ADR-007)
│   ├── store.py                # embeddings → Firestore vector collection
│   ├── pyproject.toml          # uv workspace member, depends on shared (ADR-008)
│   └── Dockerfile
│
├── chat/                       # ❌ EMPTY — Microservice 2, planned for Google Cloud Run (always-on)
│   ├── main.py                 # FastAPI entrypoint — GET /chat (SSE)
│   ├── prompt.py               # chunks + question → RAG prompt
│   ├── streamer.py             # prompt → Gemini Flash → SSE stream (LangChain, ADR-007)
│   ├── pyproject.toml          # uv workspace member, depends on shared (ADR-008)
│   └── Dockerfile
│
├── mcp/                        # ❌ EMPTY — Phase 5, MCP Server
│   ├── server.py               # MCP SDK entrypoint
│   ├── tools.py                # wraps shared/retriever.py as MCP tools
│   ├── resources.py            # exposes book library as MCP resources
│   ├── prompts.py              # reusable MCP prompt templates
│   ├── pyproject.toml          # uv workspace member, depends on shared (ADR-008)
│   └── Dockerfile
│
├── shared/                     # ✅ IMPLEMENTED — shared logic, imported by all services
│   ├── __init__.py
│   ├── pyproject.toml          # real uv workspace package (ADR-008)
│   ├── db.py                   # Firestore client (singleton)
│   ├── models.py               # Pydantic schemas (ChunkResult, Book, etc.)
│   ├── retriever.py            # THE stable interface — never changes signature
│   └── embedder.py             # ❌ not written yet (ADR-007 scopes LangChain here)
│
├── notebooks/                  # ❌ EMPTY — see docs/training/ for the notebooks that exist today
│   ├── 01_embeddings_explained.ipynb
│   ├── 02_chunking_strategies.ipynb
│   ├── 03_retrieval_evaluation.ipynb
│   ├── 04_firestore_vs_vector_db.ipynb
│   └── 05_mcp_demo.ipynb
│
├── docs/
│   ├── schema.md               # Firestore collection design
│   ├── DEVELOPMENT.md          # recommended MCP servers for AI-assisted dev on this repo
│   ├── BIBLIOGRAPHY.md         # learning resources + technical reference, by phase/ADR
│   ├── training/                # actual learning notebooks (chunking, embeddings) + reports
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
│       ├── ADR-009-pydantic-ai-structured-outputs.md
│       ├── ADR-010-external-dependency-policy.md
│       └── ADR-011-langchain-default-pydantic-ai-narrowed.md
│
├── tests/                      # ❌ EMPTY — no test suite yet
│   ├── test_parser.py
│   ├── test_chunker.py
│   ├── test_embedder.py
│   ├── test_retriever.py
│   └── test_integration.py
│
├── infra/                      # ⚠️ root module references ./modules/* which don't exist at that path
│
├── .env.example
├── docker-compose.yml          # ❌ referenced by `make dev` but not yet created
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
| Structured LLM output | LangChain (`with_structured_output()`) | typed output for the RAG eval judge and the metadata-extraction fallback, same `BaseChatModel` pattern as embedding/chat (ADR-011, narrows ADR-009 — Pydantic AI reserved for a future demonstrated need) |
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
    ├── embedding: Vector(768)         ← Firestore native vector type (Vertex AI
    │                                     text-embedding-004 dimension, ADR-002)
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
  --field-config=field-path="embedding",vector-config='{"dimension":"768","flat":"{}"}'
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

### Phase 1 — Foundation `week 1` — 🔶 in progress
Firebase project setup, Firestore collection design, vector index creation,
repository structure, first two ADRs.

**Deliverables:** Firebase project configured, Firestore indexes created,
repo structure, README, ADR-001, ADR-002, `.env.example`, `PHASE_1_SETUP.md`

**Done so far:** repo structure, README, ADRs, `.env.example`, `PHASE_1_SETUP.md`,
`shared/models.py` + `shared/db.py` + `shared/retriever.py`.
**Not yet verified from the repo:** whether the Firebase project, Firestore vector
index, and security rules described in `PHASE_1_SETUP.md` have actually been created
on GCP — that state lives outside this repository.

### Phase 2 — Ingestion Service `week 2–3` — ⬜ not started
Complete epub processing pipeline deployed to Cloud Run, including the
Library Manager dedup gate in front of it.

**Deliverables:** Cloud Run deployed, pipeline testable via `curl`,
`notebooks/02_chunking_strategies.ipynb`, ADR-003, ADR-006

### Phase 3 — Chat Service `week 4` — ⬜ not started
Retrieval and streaming chat API with stable retriever interface.

**Deliverables:** Cloud Run always-on deployed, SSE streaming end-to-end,
retriever interface abstracted for future migration, ADR-004, ADR-007

### Phase 4 — Hardening + Docs `week 5` — ⬜ not started
Integration tests, RAG evaluation, full documentation.

**Deliverables:** integration tests, evaluation notebooks,
vector-database migration guide (candidates re-evaluated per ADR-001, not fixed to one
vendor), `docker-compose.yml`

### Phase 5 — MCP Server `week 6–7` — ⬜ not started
MCP SDK wrapper exposing retrieval as tools for any LLM agent.

**Deliverables:** MCP server tested with Claude Desktop,
`mcp/` module complete, ADR-005, demo notebook

---

## Local development

```bash
cp .env.example .env        # fill in your Firebase and Google Cloud credentials
uv sync                     # install the whole workspace into one .venv (ADR-008)
uv run pytest tests/        # run the test suite — currently empty, no tests written yet
```

`docker-compose up` and `make ingest`/`make chat` are not usable yet — they depend on
`docker-compose.yml` and the `ingestion`/`chat` services, none of which exist yet
(see "Current implementation status" above). Today, `shared/` can only be exercised
by importing it directly from a Python shell or a script, against a real Firebase
project (there's no mock/emulator wiring yet).

---

## Environment variables

```bash
# Google Cloud / Firebase
GOOGLE_CLOUD_PROJECT=
FIREBASE_STORAGE_BUCKET=
GOOGLE_APPLICATION_CREDENTIALS=./service-account.json   # local dev only

# Embeddings (choose one — see ADR-002; the Firestore vector index is built for
# whichever dimension is primary and is expensive to change afterward, ADR-001)
EMBEDDING_PROVIDER=vertex_ai             # option A (primary): Vertex AI, 768 dimensions
VERTEX_AI_LOCATION=us-central1
# EMBEDDING_PROVIDER=openai              # option B (fallback): OpenAI, 1536 dimensions
# OPENAI_API_KEY=

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
