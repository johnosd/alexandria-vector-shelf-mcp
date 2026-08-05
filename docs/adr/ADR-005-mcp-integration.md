# ADR-005: MCP Server Integration

## Status
Planned — Phase 5

## Date
2025-01

## Context

The alexandria-vector-shelf-mcp project is named for its end goal: becoming a fully
compliant Model Context Protocol (MCP) server that exposes a user's epub reading library
as context to any LLM agent.

MCP (Model Context Protocol) is an open protocol created by Anthropic that standardizes
how LLM agents communicate with external tools and data sources. An MCP server exposes:

- **Tools:** functions the LLM can call (search_book, ingest_epub)
- **Resources:** data the LLM can read (library://books, library://books/{id}/chapters)
- **Prompts:** reusable prompt templates (analyze_book, compare_themes)

## Decision

In Phase 5, wrap the existing retrieval infrastructure with the MCP Python SDK to expose
the reading library as a fully compliant MCP server.

The chat service (Phase 3) is NOT replaced — it continues to serve the NeoReader mobile
app via SSE. The MCP server is an additional interface that serves LLM agents (Claude
Desktop, Cursor, custom agents) using the same underlying retriever.

### What changes vs. what stays the same

**Stays the same (zero changes):**
- `shared/retriever.py` — the stable interface
- `shared/models.py` — all Pydantic schemas
- `shared/db.py` — Firestore client
- `ingestion/` — entire pipeline
- `chat/` — entire chat service

**Added in Phase 5:**
- `mcp/server.py` — MCP SDK entry point
- `mcp/tools.py` — wraps retrieve() and ingest as MCP tools
- `mcp/resources.py` — exposes book library as readable resources
- `mcp/prompts.py` — reusable prompt templates

### Key architectural difference: Chat Service vs MCP Server

```
Chat Service (Phase 3):
  question → embed → retrieve → BUILD PROMPT → call Gemini → stream SSE
  The LLM lives INSIDE the service.

MCP Server (Phase 5):
  tool_call(search_book, question) → embed → retrieve → return ChunkResult[]
  The LLM lives in the CLIENT (Claude Desktop, Cursor).
  The server only returns context — it never calls an LLM.
```

### Tools to be exposed

```python
@mcp.tool()
async def search_book(question: str, book_id: str, top_k: int = 5) -> list[ChunkResult]:
    """Search for relevant passages in an epub using semantic similarity."""
    embedding = await generate_embedding(question)
    return await retrieve(embedding, book_id, top_k)

@mcp.tool()
async def list_books(user_id: str) -> list[BookRecord]:
    """List all processed books in the user's library."""
    ...

@mcp.tool()
async def ingest_epub(epub_url: str, book_id: str, user_id: str) -> IngestResponse:
    """Trigger processing of a new epub book."""
    ...

@mcp.tool()
async def get_chapter(book_id: str, chapter_title: str) -> list[ChunkResult]:
    """Retrieve all chunks from a specific chapter."""
    ...

@mcp.tool()
async def compare_books(question: str, book_ids: list[str], top_k: int = 3) -> dict:
    """Search across multiple books simultaneously."""
    ...
```

### Resources to be exposed

```
library://books              → list of all user books with status
library://books/{book_id}    → single book metadata
library://books/{book_id}/chapters  → list of chapters in a book
```

### MCP-compatible clients (Phase 5 targets)

- Claude Desktop (Anthropic) — primary test target
- Cursor — AI-powered IDE
- NeoReader app — can adopt MCP protocol instead of direct HTTP
- Any custom LLM agent built with the MCP Python SDK

### Deployment topology: local stdio vs remote Cloud Run

The MCP server is not automatically "a fourth Cloud Run service." Chat and MCP
look similar because both call `retrieve()`, but they differ in every
operational dimension that actually determines deployment shape: protocol,
trust model, and — critically here — where the process runs.

The primary targets (Claude Desktop, Cursor) launch MCP servers as a **local
stdio subprocess** on the user's own machine, spawned on demand by the client
itself. This is the default mode for Phase 5:

- `mcp/server.py` runs locally, imports `shared/retriever.py` directly, and
  connects to Firestore using the same Application Default Credentials pattern
  as the other services (`shared/db.py`)
- **No Cloud Run deployment, no `min-instances`, no additional hosting cost** —
  the "deployable unit" is a process the desktop client starts and stops, not
  a service Alexandria operates
- This is why Option C (trust the calling agent) in the Authentication section
  below is sufficient for MVP: the process is running as the user, on the
  user's machine

A **remote mode** — an MCP server reachable over HTTP+SSE, e.g. if NeoReader
itself adopts MCP instead of direct REST — is deferred, not assumed. If and
when it's needed, it becomes a Cloud Run service with `min-instances=0`: a
tool call from an agent tolerates cold start far better than a human waiting
on a chat response, so it does not need to inherit the chat service's
always-on cost (ADR-002). It also would not merge with the chat service even
then — the response contract (structured `ChunkResult[]` vs. streamed prose)
and the auth model (agent-trust vs. end-user Firebase Auth) stay different
enough that combining them would mean branching logic behind one endpoint
serving two incompatible contracts.

### Implementation library: FastMCP

The `@mcp.tool()` / `@mcp.resource()` decorator style already used in the code
sketches above is the FastMCP pattern — this ADR names it explicitly rather
than leaving it implicit:

- **Local mode** (default, per the topology above): use `FastMCP` built into
  the official SDK (`mcp.server.fastmcp`). It's the same official, Claude
  Desktop-compatible SDK ADR-002/README already committed to — no extra
  dependency beyond `mcp` itself.
- **Remote mode** (deferred, only if a Cloud Run-hosted MCP server becomes
  necessary): reconsider the standalone `fastmcp` package instead. It carries
  more mature auth/OAuth scaffolding than the bare official SDK, which
  directly addresses Option B in the Authentication section below (OAuth 2.0
  with a Firebase Auth token) — exactly the unresolved piece remote mode would
  need. Not adopted now because remote mode itself isn't built yet.

## Consequences

### Positive
- The project becomes genuinely useful beyond the NeoReader app
- Any MCP-compatible agent can query the user's entire book library as context
- Demonstrates Phase 5 agentic AI engineering on the portfolio
- Zero rewriting — the MCP wrapper sits cleanly on top of existing infrastructure
- Local stdio mode adds zero cloud hosting cost — no min-instances, no idle Cloud Run bill

### Negative
- MCP is still a relatively new protocol — tooling and client support are maturing
- If remote mode is ever needed, it becomes a fifth deployable unit (four cloud
  services: ingestion, chat, remote MCP, plus the `mcp/` local-mode entrypoint
  that ships as part of the repo but isn't hosted) — deferred until there's an
  actual remote client to justify it
- Auth model for MCP server needs careful design — the server must verify that the
  calling agent is authorized to access a specific user's books

### Authentication in MCP context

The MCP server will receive tool calls from agents, not directly from authenticated users.
Auth strategy for Phase 5:

Option A: API key per user — simple, not scalable
Option B: OAuth 2.0 with Firebase Auth token passed in MCP tool call parameters
Option C: Trust the calling agent — acceptable for personal/local use

For MVP Phase 5 (personal use with Claude Desktop), Option C is sufficient.
Option B will be the production approach when the project opens to multiple users.
