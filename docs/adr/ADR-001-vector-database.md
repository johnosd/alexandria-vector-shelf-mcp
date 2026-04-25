# ADR-001: Vector Database Selection

## Status
Accepted

## Date
2025-01

## Context

The alexandria-vector-shelf-mcp system needs a vector database to store and query text embeddings
generated from epub book content. Each chunk of text is converted to a vector using an embedding
model (1536 dimensions), then stored for similarity search at query time.

Requirements:
- Store vectors of dimension 1536
- Filter by `book_id` and `user_id` on every query
- K-nearest neighbor (KNN) similarity search returning top-k chunks
- Free tier that does not expire (single user, personal/portfolio project)
- Minimum operational overhead
- Preference for staying within the Google Cloud / Firebase ecosystem

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

# storing a chunk with its embedding
doc = {
    "book_id": book_id,
    "user_id": user_id,
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

A composite vector index must be created before the first query:

```bash
gcloud firestore indexes composite create \
  --collection-group=chunks \
  --query-scope=COLLECTION \
  --field-config=order=ASCENDING,field-path="book_id" \
  --field-config=field-path="embedding",vector-config='{"dimension":"1536","flat":"{}"}'
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
- Maximum vector dimension is 2048. The chosen model (text-embedding-3-small) produces
  1536 dimensions — safely within limits.
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

When hybrid search quality becomes a real need:

1. Provision a Weaviate Cloud instance or self-hosted Weaviate on GKE
2. Write `shared/retriever_weaviate.py` implementing the same interface
3. Run both retrievers in parallel — compare result quality on a sample
4. Switch `shared/retriever.py` to import the Weaviate implementation
5. Backfill existing chunks: the embeddings are already stored in Firestore
   and can be re-used without calling the embedding API again

The chat service, MCP server, ingestion pipeline, and all tests remain unchanged.
See `notebooks/04_firestore_vs_weaviate.ipynb` for a side-by-side quality comparison.
