# alexandria-vector-shelf-mcp

A production-grade RAG pipeline for epub books, designed to evolve into a fully compliant MCP server.

Ingest any epub → query it semantically → expose your reading library as context to any LLM agent.

#RAG engineering #VectorSearch #agenticAIIntegrationPatterns.

---

## What this project is

`alexandria-vector-shelf-mcp` is a backend system that processes epub books and enables semantic conversation with their content. It is intentionally built in two stages:

**Stage 1 — RAG Service (Phases 1–4):** A self-contained backend with two microservices — an ingestion pipeline and a chat API — that allows any client to upload an epub and chat with it via streaming.

**Stage 2 — MCP Server (Phase 5):** The same retrieval logic is wrapped with the Model Context Protocol SDK, making the entire reading library available as context tools to any MCP-compatible agent (Claude Desktop, Cursor, custom agents).

The core retrieval logic (`shared/retriever.py`) is written once and shared by both stages. No rewriting, no duplication.

---

## Architecture overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Clients                                  │
│                                                                 │
│   NeoReader App          Claude Desktop        Cursor / Agent   │
│   (mobile, SSE)          (MCP client)          (MCP client)     │
└────────┬─────────────────────────┬──────────────────┬──────────┘
         │ HTTP + SSE              │ MCP protocol     │ MCP protocol
         ▼                         ▼                  ▼
┌────────────────┐      ┌──────────────────────────────────────┐
│  Chat Service  │      │           MCP Server                 │
│  (Fly.io)      │      │           (Phase 5)                  │
│                │      │  tools: search_book, ingest_epub     │
│  FastAPI + SSE │      │  resources: library://books          │
│  gpt-4o-mini   │      │  prompts: analyze_book               │
└───────┬────────┘      └──────────────┬───────────────────────┘
        │                              │
        └──────────────┬───────────────┘
                       │ calls retrieve()
                       ▼
              ┌─────────────────┐
              │  shared/        │
              │  retriever.py   │  ← heart of the system
              │  embedder.py    │
              │  models.py      │
              └───────┬─────────┘
                      │
                      ▼
         ┌────────────────────────┐
         │  Supabase              │
         │                        │
         │  pgvector  (chunks)    │
         │  Storage   (.epub)     │
         │  Auth      (user_id)   │
         │  Realtime  (status)    │
         └────────────────────────┘
                      ▲
                      │ parse → chunk → embed → store
                      │
         ┌────────────────────────┐
         │  Ingestion Service     │
         │  (Google Cloud Run)    │
         │                        │
         │  parser.py             │
         │  chunker.py            │
         │  embedder.py           │
         │  store.py              │
         └────────────────────────┘
```

---

## Design principles

**Separation of concerns.** The ingestion pipeline and the chat service are independent microservices. They share data through Supabase, not through direct coupling.

**Retriever as the stable interface.** `shared/retriever.py` defines a typed contract (`list[ChunkResult]`) that never changes. The chat service and the MCP server both call it. The underlying database implementation can be swapped (pgvector → Weaviate) without touching anything else.

**Built to migrate.** Every architectural decision that locks in a technology is documented in an ADR with a migration path. The most important: `retriever.py` abstracts the vector database so migrating from pgvector to Weaviate means changing one file.

**Documented as it is built.** Every non-obvious decision has an ADR. Every concept introduced in the code has a corresponding notebook. The project is designed to be readable by someone learning RAG engineering.

---

## Repository structure

```
alexandria-vector-shelf-mcp/
│
├── ingestion/                  # Microservice 1 — Google Cloud Run
│   ├── main.py                 # FastAPI entrypoint — POST /ingest
│   ├── parser.py               # epub → clean text
│   ├── chunker.py              # text → overlapping chunks
│   ├── embedder.py             # chunks → OpenAI embeddings
│   ├── store.py                # embeddings → Supabase pgvector
│   ├── requirements.txt
│   └── Dockerfile
│
├── chat/                       # Microservice 2 — Fly.io / Railway
│   ├── main.py                 # FastAPI entrypoint — GET /chat (SSE)
│   ├── retriever.py            # question → relevant chunks (pgvector impl)
│   ├── prompt.py               # chunks + question → RAG prompt
│   ├── streamer.py             # prompt → OpenAI streaming → SSE
│   ├── requirements.txt
│   └── Dockerfile
│
├── mcp/                        # Phase 5 — MCP Server
│   ├── server.py               # MCP SDK entrypoint
│   ├── tools.py                # wraps shared/retriever.py as MCP tools
│   ├── resources.py            # exposes book library as MCP resources
│   ├── prompts.py              # reusable MCP prompt templates
│   ├── requirements.txt
│   └── Dockerfile
│
├── shared/                     # Shared logic — imported by all services
│   ├── db.py                   # Supabase client (singleton)
│   ├── models.py               # Pydantic schemas (ChunkResult, Book, etc.)
│   └── retriever.py            # THE stable interface — never changes signature
│
├── notebooks/                  # Learning artifacts
│   ├── 01_embeddings_explained.ipynb
│   ├── 02_chunking_strategies.ipynb
│   ├── 03_retrieval_evaluation.ipynb
│   └── 04_pgvector_vs_weaviate.ipynb
│
├── docs/
│   └── adr/                    # Architecture Decision Records
│       ├── ADR-001-vector-database.md
│       ├── ADR-002-stack-selection.md
│       ├── ADR-003-chunk-strategy.md
│       ├── ADR-004-prompt-design.md
│       └── ADR-005-mcp-integration.md
│
├── tests/
│   ├── test_parser.py
│   ├── test_chunker.py
│   ├── test_retriever.py
│   └── test_integration.py
│
├── .env.example                # All required env vars documented
├── docker-compose.yml          # Full local development stack
├── Makefile                    # Standardized commands
└── ARCHITECTURE.md             # Deep dive into design decisions
```

---

## Tech stack

| Layer | Technology | Why |
|---|---|---|
| Language | Python 3.11 | async support, rich AI ecosystem |
| API framework | FastAPI | async, auto docs, SSE support |
| Vector database | Supabase pgvector | free tier permanent, includes auth + storage + realtime |
| Embeddings | OpenAI text-embedding-3-small | best cost/quality ratio, 1536 dimensions |
| LLM | OpenAI gpt-4o-mini | cheapest capable model for RAG responses |
| Ingestion compute | Google Cloud Run | serverless, pay-per-use, zero cost when idle |
| Chat compute | Fly.io | always-on container, no cold start, ~$5/month |
| MCP protocol | Anthropic MCP Python SDK | official SDK, Claude Desktop compatible |
| Epub parsing | EbookLib + BeautifulSoup4 | mature, handles malformed epubs |
| Containerization | Docker | consistent environments across services |

---

## Database schema

```sql
-- Enable pgvector extension
create extension if not exists vector;

-- Books table — tracks ingestion status and epub metadata
create table books (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null,
  title       text,
  author      text,
  epub_path   text,           -- path in Supabase Storage
  status      text default 'pending',  -- pending | processing | ready | error
  chunk_count integer default 0,
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);

-- Chunks table — stores text + embedding for each book segment
create table chunks (
  id          uuid primary key default gen_random_uuid(),
  book_id     uuid references books(id) on delete cascade,
  user_id     uuid not null,
  content     text not null,
  embedding   vector(1536),   -- text-embedding-3-small output dimension
  chunk_index integer,        -- position in the original book
  chapter     text,           -- chapter title if extractable
  created_at  timestamptz default now()
);

-- IVFFlat index for approximate nearest neighbor search
-- lists = 100 is a good starting point for up to ~1M vectors
create index on chunks
  using ivfflat (embedding vector_cosine_ops)
  with (lists = 100);

-- Index for fast filtering by book_id
create index on chunks (book_id);

-- Row Level Security — users can only see their own data
alter table books enable row level security;
alter table chunks enable row level security;

create policy "users see own books"
  on books for all
  using (auth.uid() = user_id);

create policy "users see own chunks"
  on chunks for all
  using (auth.uid() = user_id);
```

---

## API contracts

### Ingestion Service — `POST /ingest`

```
Request
  epub_url  string  URL of the epub file in Supabase Storage
  book_id   string  UUID of the book record already created
  user_id   string  UUID of the authenticated user

Response 202 Accepted
  job_id    string  Internal processing job identifier
  status    string  "processing"

Status updates are delivered via Supabase Realtime
on the books table (status field).
```

### Chat Service — `GET /chat`

```
Request (query params)
  book_id   string  UUID of the book to query
  user_id   string  UUID of the authenticated user
  question  string  The user's question in natural language

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

class ChunkResult(BaseModel):
    content: str
    book_id: str
    score: float
    chunk_index: int
    chapter: str | None
```

---

## Roadmap

### Phase 1 — Foundation ✅ `week 1`
Configure Supabase, define the database schema, set up the repository structure, write the first two ADRs.

**Deliverables:** schema SQL, Supabase project configured, repo structure, README, ADR-001, ADR-002, `.env.example`

### Phase 2 — Ingestion Service `week 2–3`
Build the complete epub processing pipeline: parse → chunk → embed → store. Deploy to Google Cloud Run.

**Deliverables:** Cloud Run deployed, pipeline testable via `curl`, `notebooks/02_chunking_strategies.ipynb`, ADR-003

### Phase 3 — Chat Service `week 4`
Build the retrieval and streaming chat API. Implement the stable retriever interface. Deploy to Fly.io.

**Deliverables:** Fly.io deployed, SSE streaming working end-to-end, retriever interface abstracted for pgvector → Weaviate migration, ADR-004

### Phase 4 — Hardening + Docs `week 5`
Add integration tests, observability, RAG evaluation notebook, and full documentation.

**Deliverables:** integration tests, `notebooks/03_retrieval_evaluation.ipynb`, `notebooks/04_pgvector_vs_weaviate.ipynb`, `ARCHITECTURE.md`, Weaviate migration guide, `docker-compose.yml` complete

### Phase 5 — MCP Server `week 6–7`
Wrap the retrieval logic with the MCP Python SDK. Expose `search_book`, `ingest_epub`, `list_books`, `compare_books` as MCP tools. Test with Claude Desktop.

**Deliverables:** MCP server running locally with Claude Desktop, `mcp/` module complete, ADR-005, `notebooks/05_mcp_demo.ipynb`, integration guide

---

## Migration path: pgvector → Weaviate

The retriever interface is designed so that migrating the vector database requires changing exactly one file: `shared/retriever.py`.

The signature never changes:

```python
async def retrieve(
    question_embedding: list[float],
    book_id: str,
    top_k: int = 5
) -> list[ChunkResult]:
```

The implementation switches from a Supabase RPC call to a Weaviate hybrid search query. The chat service, MCP server, and all tests are completely unaware of this change.

See `docs/adr/ADR-001-vector-database.md` for the full decision context and `notebooks/04_pgvector_vs_weaviate.ipynb` for a side-by-side comparison.

---

## Local development

```bash
# Copy and fill environment variables
cp .env.example .env

# Start all services
docker-compose up

# Run ingestion pipeline only
make ingest EPUB=path/to/book.epub BOOK_ID=<uuid> USER_ID=<uuid>

# Run chat service only
make chat

# Run all tests
make test
```

---

## Environment variables

```bash
# Supabase
SUPABASE_URL=
SUPABASE_SERVICE_KEY=        # server-side only — never expose to clients
SUPABASE_ANON_KEY=           # client-side safe key

# OpenAI
OPENAI_API_KEY=

# Service URLs (set in production, auto-resolved locally)
INGESTION_SERVICE_URL=
CHAT_SERVICE_URL=
```

---

## Learning resources

Resources are ordered by the phase in which the concept appears in the code.

**Before starting — conceptual foundation**
- [DeepLearning.AI — Building Systems with the ChatGPT API](https://www.deeplearning.ai/short-courses/building-systems-with-chatgpt/) — free, 1 hour, covers RAG fundamentals
- [DeepLearning.AI — LangChain: Chat with Your Data](https://www.deeplearning.ai/short-courses/langchain-chat-with-your-data/) — chunking and retrieval concepts explained well even if we don't use LangChain
- [Andrej Karpathy — Intro to Large Language Models](https://www.youtube.com/watch?v=zjkBMFhNj_g) — 1 hour, best technical introduction to LLMs

**Phase 2 — Chunking and embeddings**
- *Hands-On Large Language Models* — Jay Alammar & Maarten Grootendorst (O'Reilly 2024) — best practical LLM book available, excellent embeddings coverage
- [Pinecone — Chunking Strategies for LLM Applications](https://www.pinecone.io/learn/chunking-strategies/) — technical reference for chunking strategies
- [Greg Kamradt — 5 Levels of Text Splitting](https://www.youtube.com/watch?v=8OJC21T2SL4) — essential, covers naive to semantic splitting

**Phase 3 — Retrieval and RAG**
- [DeepLearning.AI — Building and Evaluating Advanced RAG](https://www.deeplearning.ai/short-courses/building-evaluating-advanced-rag/) — retrieval, reranking, and evaluation
- *Building LLMs for Production* — Maximilian Ott (Manning 2024) — production-focused, not just prototypes
- [RAG original paper — Lewis et al. 2020](https://arxiv.org/abs/2005.11401) — foundational reading

**Phase 4 — Evaluation and production**
- [DeepLearning.AI — Evaluating and Debugging Generative AI](https://www.deeplearning.ai/short-courses/evaluating-debugging-generative-ai/) — how to know if your RAG is working well
- *Designing Machine Learning Systems* — Chip Huyen (O'Reilly 2022) — serving and monitoring chapters directly applicable

**Phase 5 — MCP**
- [Model Context Protocol — Official Introduction](https://modelcontextprotocol.io/introduction) — 30 minutes, covers tools, resources, and prompts
- [MCP Python SDK](https://github.com/modelcontextprotocol/python-sdk) — the SDK used in Phase 5
- [Awesome MCP Servers](https://github.com/punkpeye/awesome-mcp-servers) — reference implementations

**Ongoing reference**
- [Supabase pgvector guide](https://supabase.com/docs/guides/ai/vector-columns)
- [Lilian Weng — Prompt Engineering](https://lilianweng.github.io/posts/2023-03-15-prompt-engineering/) — dense but precise

---

## Author

Built by Johnny as a portfolio project in AI/Data Engineering.
Designed to demonstrate end-to-end RAG system design, from epub ingestion to MCP server.
