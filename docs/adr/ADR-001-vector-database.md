# ADR-001: Vector Database Selection

## Status
Accepted

## Date
2025-01

## Context

The alexandria-vector-shelf-mcp system needs a vector database to store and query text embeddings generated
from epub book content. Each chunk of text is converted to a 1536-dimensional vector using
OpenAI's `text-embedding-3-small` model, then stored for similarity search at query time.

Requirements for the MVP stage:
- Store vectors of dimension 1536 (OpenAI text-embedding-3-small output)
- Filter by `book_id` and `user_id` on every query
- Similarity search returning top-k most relevant chunks
- Free tier that does not expire (single user, personal portfolio project)
- Minimal operational overhead

Desirable but not required for MVP:
- Hybrid search (semantic + keyword/BM25)
- High performance at scale (>1M vectors)

## Decision

Use **Supabase pgvector** as the vector database for Phases 1–4.

pgvector is a PostgreSQL extension that adds vector storage and similarity search.
Supabase provides a managed PostgreSQL instance with pgvector enabled, along with
Auth, Storage, and Realtime — all on the same free tier.

## Alternatives Considered

### Weaviate Cloud (WCS)
- Native vector database with excellent hybrid search (BM25 + vector)
- Better performance than pgvector at scale
- **Rejected:** free tier expires after 14 days. Paid tier starts at ~$25/month.
  For a single-user MVP, paying $25/month for a vector database is not justified.

### Qdrant Cloud
- Native vector database, open source, permanent free tier (1GB)
- Native hybrid search
- Good Python SDK
- **Rejected:** adds a separate account and dependency without providing meaningful
  benefits over pgvector at MVP scale. If Supabase were not already in the stack,
  Qdrant would be the preferred choice.

### Pinecone
- Industry standard for production vector search
- Managed, zero operational overhead
- **Rejected:** free tier is too limited (1 index), high vendor lock-in,
  and expensive at scale. Overkill for a single-user MVP.

## Consequences

### Positive
- Single platform for auth, storage, vector search, and realtime status updates
- Permanent free tier — no cost for MVP
- SQL-native — straightforward to query, debug, and inspect data
- Row Level Security built in — user data isolation is handled at the database level
- No additional account or dependency

### Negative
- No native hybrid search (BM25 + vector combined). Keyword search would require
  implementing `tsvector` manually, which adds complexity.
- Lower performance than native vector databases at scale (>500k vectors per index)
- pgvector's IVFFlat index requires approximate search tuning (`lists` parameter)

### Migration path
The retriever interface (`shared/retriever.py`) is designed to abstract the underlying
database completely. The function signature:

```python
async def retrieve(
    question_embedding: list[float],
    book_id: str,
    top_k: int = 5
) -> list[ChunkResult]:
```

...never changes regardless of which database backs it.

When hybrid search quality becomes a real need (multiple users, large libraries,
queries with proper nouns or technical terms), the migration plan is:

1. Provision a Weaviate Cloud instance
2. Write `shared/retriever_weaviate.py` implementing the same interface
3. Run both retrievers in parallel on a sample of queries — compare result quality
4. Switch `shared/retriever.py` to import the Weaviate implementation
5. Backfill existing chunks into Weaviate (the embeddings are already stored and
   can be re-used — no need to call the OpenAI API again)

The chat service, MCP server, ingestion pipeline, and all tests remain unchanged.
See `notebooks/04_pgvector_vs_weaviate.ipynb` for a side-by-side quality comparison.
