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

## Consequences

### Positive
- The project becomes genuinely useful beyond the NeoReader app
- Any MCP-compatible agent can query the user's entire book library as context
- Demonstrates Phase 5 agentic AI engineering on the portfolio
- Zero rewriting — the MCP wrapper sits cleanly on top of existing infrastructure

### Negative
- MCP is still a relatively new protocol — tooling and client support are maturing
- Adds a fourth deployable unit (mcp/) to the repository
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
