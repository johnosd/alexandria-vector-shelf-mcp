"""
shared/retriever.py
-------------------
The stable retrieval interface — the heart of the RAG system.

CONCEPT: Why this is the most important file in the project
Every other component exists to serve this one function.
The ingestion pipeline stores chunks so this can find them.
The chat service calls this to build the RAG context.
The MCP server calls this to respond to tool calls.

The function signature is a contract that NEVER changes:

    retrieve(question_embedding, book_id, top_k) -> list[ChunkResult]

The implementation underneath can be swapped (Firestore → Weaviate) by
changing only this file. The chat service, MCP server, and all tests
are completely unaware of this change.

CONCEPT: Firestore KNN vector search
Firestore's find_nearest() performs a K-nearest neighbor (KNN) search
over the vector field of a collection. It:
  1. Filters documents by book_id (equality filter — uses the composite index)
  2. Computes cosine distance between each document's embedding and the query vector
  3. Returns the top_k documents with smallest distance (highest similarity)

This requires a composite vector index created in Phase 1 setup:
  gcloud firestore indexes composite create \
    --collection-group=chunks \
    --field-config=order=ASCENDING,field-path="book_id" \
    --field-config=field-path="embedding",vector-config='{"dimension":"1536","flat":"{}"}'

CURRENT IMPLEMENTATION: Firestore vector search (native KNN)
FUTURE IMPLEMENTATION: Weaviate (when hybrid BM25+vector search is needed)
  → See ADR-001 migration path and notebooks/04_firestore_vs_weaviate.ipynb
"""

from __future__ import annotations

import logging

from google.cloud.firestore_v1.base_vector_query import DistanceMeasure
from google.cloud.firestore_v1.vector import Vector

from shared.db import CHUNKS_COLLECTION, db
from shared.models import ChunkResult

logger = logging.getLogger(__name__)


async def retrieve(
    question_embedding: list[float],
    book_id: str,
    top_k: int = 5,
) -> list[ChunkResult]:
    """
    Finds the most semantically relevant chunks for a given question embedding.

    This is the ONLY function the chat service and MCP server call.
    They receive a list of ChunkResult objects and do not know or care
    how the search was performed internally.

    Args:
        question_embedding : Vector from the embedding model.
                             MUST use the same model used during ingestion.
                             Mixing models (e.g., OpenAI at ingest, Vertex AI
                             at query time) produces meaningless similarity scores.
        book_id            : Firestore document ID of the book to search within.
                             Every query is scoped to a single book — chunks from
                             different books are never mixed in one response.
        top_k              : Number of chunks to return. Default 5.
                             Too few: LLM lacks context.
                             Too many: context window fills, LLM gets confused.
                             Tune via RETRIEVAL_TOP_K in .env

    Returns:
        List of ChunkResult ordered by relevance (most similar first).
        Empty list if the book has no chunks or book_id is wrong.

    Raises:
        Exception: Propagates Firestore errors to the caller.
    """
    logger.info("Retrieving chunks", extra={"book_id": book_id, "top_k": top_k})

    # CONCEPT: Why filter by book_id before the vector search?
    # Without the book_id filter, find_nearest() would search across ALL chunks
    # from ALL users and ALL books — both a privacy issue and a quality issue.
    # The composite index (book_id ASC + embedding KNN) makes this filter fast.
    collection = db.collection(CHUNKS_COLLECTION)

    vector_query = collection\
        .where("book_id", "==", book_id)\
        .find_nearest(
            vector_field="embedding",
            query_vector=Vector(question_embedding),
            distance_measure=DistanceMeasure.COSINE,
            limit=top_k,
            # distance_result_field stores the computed distance in the result
            # so we can convert it to a similarity score
            distance_result_field="distance",
        )

    docs = vector_query.stream()
    results = []

    async for doc in docs:
        data = doc.to_dict()

        # CONCEPT: Distance to similarity score conversion
        # Firestore returns cosine DISTANCE (0 = identical, 2 = opposite).
        # We convert to cosine SIMILARITY (1 = identical, -1 = opposite)
        # so that higher scores mean more relevant — consistent with convention.
        distance = data.pop("distance", 0.0)
        similarity_score = 1.0 - distance

        results.append(ChunkResult(
            content=data["content"],
            book_id=data["book_id"],
            score=max(0.0, min(1.0, similarity_score)),  # clamp to [0, 1]
            chunk_index=data["chunk_index"],
            chapter=data.get("chapter"),
        ))

    if not results:
        logger.warning("No chunks found", extra={"book_id": book_id})
        return []

    logger.info(
        "Retrieved chunks",
        extra={
            "book_id": book_id,
            "count": len(results),
            "top_score": results[0].score if results else None,
        },
    )

    # Results arrive ordered by distance (ascending) from Firestore.
    # We return them ordered by similarity (descending) — highest relevance first.
    return sorted(results, key=lambda r: r.score, reverse=True)
