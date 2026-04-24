"""
shared/retriever.py
-------------------
The stable retrieval interface — the heart of the RAG system.

CONCEPT: Why this file is the most important in the project
Everything else in this system exists to serve this function:
  - The ingestion pipeline stores chunks so this can find them
  - The chat service calls this to build the RAG context
  - The MCP server calls this to respond to tool calls

The function signature is a contract:

    retrieve(question_embedding, book_id, top_k) -> list[ChunkResult]

This contract NEVER changes. The implementation can be swapped (pgvector → Weaviate)
by changing only this file. Nothing else in the system needs to know or care.

CONCEPT: Vector similarity search
When the user asks a question, we convert the question to an embedding (a list of
1536 floats) using the same model that created the chunk embeddings. Then we find
the chunks whose embeddings are "closest" to the question embedding in vector space.

"Closest" is measured by cosine similarity:
  - Score = 1.0 means the vectors point in the same direction (very similar)
  - Score = 0.0 means the vectors are perpendicular (unrelated)
  - Score = -1.0 means the vectors point in opposite directions (opposite meaning)

In practice, relevant chunks score above 0.7 and irrelevant ones below 0.5.
The exact threshold depends on the embedding model and the content.

CURRENT IMPLEMENTATION: Supabase pgvector
Uses a PostgreSQL stored function `match_chunks` (defined in the schema SQL).
The function takes the query embedding and returns the top-k most similar chunks
filtered by book_id.

FUTURE IMPLEMENTATION: Weaviate (when hybrid search is needed)
Replace the body of `retrieve()` with a Weaviate hybrid search query.
The signature stays the same. See ADR-001 for the migration plan.
"""

from __future__ import annotations

import logging

from shared.db import supabase
from shared.models import ChunkResult

logger = logging.getLogger(__name__)


async def retrieve(
    question_embedding: list[float],
    book_id: str,
    top_k: int = 5,
) -> list[ChunkResult]:
    """
    Finds the most semantically relevant chunks for a given question embedding.

    This is the ONLY function the chat service and MCP server need to call.
    They do not know how the search works internally — they only know what
    they receive: a list of ChunkResult objects ordered by relevance.

    Args:
        question_embedding : 1536-dimensional vector from text-embedding-3-small.
                             Must use the SAME model used during ingestion, or
                             the similarity scores will be meaningless.
        book_id            : Filters results to a single book.
                             Every query is scoped to one book — we never
                             mix chunks from different books in a single response.
        top_k              : Number of chunks to return. 5 is a good default.
                             Too few: LLM lacks context.
                             Too many: context window fills up, LLM gets confused.
                             The right value depends on chunk size and question type.

    Returns:
        List of ChunkResult ordered by relevance score (highest first).
        Empty list if no chunks are found (book not ingested or wrong book_id).

    Raises:
        Exception: Propagates database errors to the caller for proper handling.
    """
    logger.info(
        "Retrieving chunks",
        extra={"book_id": book_id, "top_k": top_k},
    )

    # CONCEPT: Why a stored function instead of raw SQL?
    # Supabase's Python client doesn't support the <=> (cosine distance) operator
    # directly in the .select() builder. A PostgreSQL stored function lets us
    # write the vector search query in SQL and call it cleanly from Python.
    # The function is defined in the schema SQL file (Phase 1 deliverable).
    response = supabase.rpc(
        "match_chunks",
        {
            "query_embedding": question_embedding,
            "filter_book_id": book_id,
            "match_count": top_k,
        },
    ).execute()

    if not response.data:
        logger.warning(
            "No chunks found",
            extra={"book_id": book_id},
        )
        return []

    # CONCEPT: Why validate with Pydantic here?
    # The database can return unexpected shapes (null fields, wrong types) if the
    # schema changes. Pydantic catches this at the boundary — before the bad data
    # reaches the prompt builder or MCP tool response.
    results = [ChunkResult(**row) for row in response.data]

    logger.info(
        "Retrieved chunks",
        extra={
            "book_id": book_id,
            "count": len(results),
            "top_score": results[0].score if results else None,
        },
    )

    return results
