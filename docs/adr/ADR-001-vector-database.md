# ADR-001: Vector Database Selection

## Status
Accepted

## Date
2025-01

## Context

The alexandria-vector-shelf-mcp system needs a vector database to store and query text embeddings
generated from epub book content. Each chunk of text is converted to a vector using an embedding
model (768 dimensions — Vertex AI `text-embedding-004`, the primary provider decided in ADR-002),
then stored for similarity search at query time.

Requirements:
- Store vectors of dimension 768 (primary provider's output — ADR-002)
- Filter by `book_id` and `user_id` on every query
- K-nearest neighbor (KNN) similarity search returning top-k chunks
- Free tier that does not expire (single user, personal/portfolio project)
- Minimum operational overhead
- Preference for staying within the Google Cloud / Firebase ecosystem

**Update (ADR-006):** the second requirement above is stale. `chunks` became a
global catalog collection with no `user_id` field at all — every query filters
by `book_id` only. Ownership/access is tracked separately in
`user_library/{user_id}/books/{book_id}`, not as a field on the chunk. The
code sample and "Negative" section below are corrected to match; see ADR-006
for the full reasoning.

## Decision

Use **Firestore vector search** (native KNN capability within Cloud Firestore) as the
vector database for Phases 1–4.

Firestore added native vector embedding support with K-nearest neighbor (KNN) search,
allowing vector fields to be stored in documents and queried using cosine, Euclidean,
or dot product distance measures. This keeps the entire system — auth, storage, realtime
updates, and vector search — within a single Firebase/GCP project and billing account.

### How it works in practice

Vectors are stored as a native Firestore `Vector` type in each chunk document:

```python
from google.cloud.firestore_v1.vector import Vector
from google.cloud.firestore_v1.base_vector_query import DistanceMeasure

# storing a chunk with its embedding — no user_id (ADR-006: chunks are a
# global catalog, not owned by a single user; ownership is tracked separately
# in user_library/{user_id}/books/{book_id})
doc = {
    "book_id": book_id,
    "content": chunk_text,
    "embedding": Vector(embedding_list),   # native Firestore vector type
    "chunk_index": index,
    "chapter": chapter_title,
}
db.collection("chunks").add(doc)

# querying — filter by book_id then KNN search
results = db.collection("chunks")\
    .where("book_id", "==", book_id)\
    .find_nearest(
        vector_field="embedding",
        query_vector=Vector(question_embedding),
        distance_measure=DistanceMeasure.COSINE,
        limit=top_k
    ).stream()
```

A composite vector index must be created before the first query. The
dimension must match the primary embedding provider's output — Vertex AI
`text-embedding-004` (ADR-002), 768:

```bash
gcloud firestore indexes composite create \
  --collection-group=chunks \
  --query-scope=COLLECTION \
  --field-config=order=ASCENDING,field-path="book_id" \
  --field-config=field-path="embedding",vector-config='{"dimension":"768","flat":"{}"}'
```

## Alternatives Considered

### Supabase pgvector
- PostgreSQL with vector extension
- Permanent free tier, excellent SQL tooling
- **Rejected:** requires a second platform outside GCP, splitting auth/storage/realtime
  from vector search across two accounts. The consolidation benefit of staying in Firebase
  outweighs the marginal SQL ergonomics advantage of pgvector.

### Vertex AI Vector Search
- Google's dedicated, managed vector database
- Excellent performance and hybrid search at scale
- **Rejected:** no meaningful free tier. Minimum cost ~$65/month regardless of usage.
  Completely unjustifiable for a single-user MVP. Revisit when the project has real
  scale and revenue.

### Weaviate Cloud (WCS)
- Native vector database with excellent hybrid search (BM25 + vector)
- **Rejected:** free tier expires after 14 days. Adds a third-party dependency outside GCP.

### Qdrant Cloud
- Open source native vector database, permanent free tier (1GB)
- **Rejected:** adds a separate account and dependency without meaningful benefit
  at MVP scale. Good alternative if leaving the GCP ecosystem.

### Pinecone
- Industry standard for production vector search
- **Rejected:** high vendor lock-in, expensive at scale, limited free tier, overkill
  for single-user MVP.

## Consequences

### Positive
- Single GCP/Firebase project covers auth, storage, realtime updates, and vector search
- Permanent free tier on Firestore Spark plan
- Native Firestore Realtime on the same collection used for vector search
- One account, one IAM, one billing dashboard, one SDK
- No data leaving the GCP network during retrieval
- Firebase Security Rules enforce user data isolation at the database level

### Negative
- No native hybrid search (BM25 + vector combined). Firestore vector search is pure
  KNN — keyword-boosted retrieval is not available without a separate full-text search
  solution (e.g., Algolia or Elasticsearch).
- Requires creating a composite vector index via gcloud CLI before the first query.
  This is a one-time manual step, but it is not automatic like pgvector's index.
- Maximum vector dimension is 2048. The primary embedding model
  (Vertex AI `text-embedding-004`, ADR-002) produces 768 dimensions by default —
  safely within limits. The OpenAI fallback (`text-embedding-3-small`, 1536
  dimensions) also fits, but switching providers after the index is created
  means deleting and recreating it at the new dimension (see "Migration path"
  below) — not a drop-in swap.
- Firestore is a document database, not a relational one. Complex SQL-style joins and
  aggregations are not possible.

### Migration path

The retriever interface (`shared/retriever.py`) abstracts the database completely.
The function signature never changes:

```python
async def retrieve(
    question_embedding: list[float],
    book_id: str,
    top_k: int = 5
) -> list[ChunkResult]:
```

When hybrid search or ANN-scale query cost becomes a real need — not the case
today. A Firestore-only hybrid search path (in-memory BM25 + RRF, scoped per
`book_id`) was already found viable without switching databases at all; see
`docs/backlog.md`. Try that first.

If a database switch is still needed:

1. Re-evaluate candidates against pricing at the time — this list shifts.
   As of 2026-08, the two strongest by cost are **Qdrant Cloud** (permanent
   free tier, HNSW ANN, native hybrid search) and **MongoDB Atlas Vector
   Search** (permanent M0 free tier, HNSW ANN, native hybrid search, can
   co-locate its region with this project's GCP compute). Weaviate Cloud —
   this ADR's original named target — no longer has a permanent free tier
   (pricing restructured, $45/month minimum as of Oct 2025) and is no longer
   the default candidate. Re-check current pricing before committing to any
   of the three; none of this is GCP-native, so a real, written-down gain is
   required under ADR-010 regardless of which one is picked.
2. Write `shared/retriever_<provider>.py` implementing the same interface
3. Run both retrievers in parallel — compare result quality on a sample
4. Switch `shared/retriever.py` to import the new implementation
5. Backfill existing chunks: the embeddings are already stored in Firestore
   and can be re-used without calling the embedding API again

The chat service, MCP server, ingestion pipeline, and all tests remain unchanged.
See `notebooks/04_firestore_vs_vector_db.ipynb` for a side-by-side quality
comparison (generalized from "vs weaviate" — the migration target is no
longer fixed to one candidate).
