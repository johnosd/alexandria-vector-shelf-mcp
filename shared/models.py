"""
shared/models.py
----------------
Pydantic schemas shared across all services (ingestion, chat, mcp).

CONCEPT: Why Pydantic?
Pydantic validates data at runtime using Python type hints. Instead of manually
checking if a field is the right type, Pydantic raises a clear error at the
boundary of your system (API input, Firestore output) rather than deep inside
your logic. Think of it as a schema contract enforced at runtime.

All services import from this file. Schema changes happen in one place.
"""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from uuid import UUID

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class BookStatus(str, Enum):
    """
    Lifecycle states of a book in the system.

    Using an Enum prevents typos like "proccessing" from silently passing
    through. The Firestore document stores the string value; Python code
    always uses BookStatus.READY — the Enum member.
    """

    PENDING = "pending"         # book document created, ingestion not started
    PROCESSING = "processing"   # ingestion pipeline running
    READY = "ready"             # chunks stored, book available for chat
    ERROR = "error"             # ingestion failed, see error_message field


# ---------------------------------------------------------------------------
# Book schemas
# ---------------------------------------------------------------------------


class BookCreate(BaseModel):
    """
    Payload for creating a new book document in Firestore.
    The book document must exist before ingestion starts — the ingestion
    service needs the book_id to associate chunks.
    """

    user_id: str                # Firebase Auth UID
    title: str | None = None    # extracted from epub metadata
    author: str | None = None   # extracted from epub metadata
    epub_path: str | None = None  # gs://bucket/path in Firebase Storage


class BookRecord(BaseModel):
    """Full book document as returned by the API."""

    id: str
    user_id: str
    title: str | None = None
    author: str | None = None
    epub_path: str | None = None
    status: BookStatus = BookStatus.PENDING
    chunk_count: int = 0
    error_message: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None

    class Config:
        from_attributes = True


# ---------------------------------------------------------------------------
# Chunk schemas
# ---------------------------------------------------------------------------


class ChunkCreate(BaseModel):
    """
    Schema for a single chunk ready to be stored in Firestore.
    Created by chunker.py, populated with embedding by embedder.py,
    then passed to store.py.
    """

    book_id: str
    user_id: str
    content: str
    embedding: list[float]          # output of embedding model (1536 or 768 floats)
    chunk_index: int                # 0-based position in the book
    chapter: str | None = None      # chapter title if extractable


class ChunkResult(BaseModel):
    """
    Schema for a chunk returned by the retriever.

    CONCEPT: This is THE stable interface of the entire system.
    The chat service, MCP server, prompt builder, and RAG evaluator all work
    with ChunkResult. The retriever implementation (Firestore today, Weaviate
    tomorrow) must always return list[ChunkResult]. If this contract holds,
    nothing else in the system needs to change when the database is swapped.

    Fields:
        content     : raw text of the chunk — what the LLM reads
        book_id     : which book this chunk belongs to
        score       : similarity score (0.0 to 1.0, higher = more relevant)
        chunk_index : original position in the book — used to sort results
                      by narrative order rather than relevance score
        chapter     : chapter title if available — cited in the RAG prompt
    """

    content: str
    book_id: str
    score: float = Field(ge=0.0, le=1.0)
    chunk_index: int
    chapter: str | None = None


# ---------------------------------------------------------------------------
# Ingestion schemas
# ---------------------------------------------------------------------------


class IngestRequest(BaseModel):
    """
    Request body for POST /ingest.

    The ingestion service receives this, returns 202 Accepted immediately,
    then processes the epub asynchronously. The client polls for status
    via Firestore Realtime subscription on the book document.
    """

    epub_url: str       # signed Firebase Storage URL to download the epub
    book_id: str        # pre-created Firestore book document ID
    user_id: str        # Firebase Auth UID


class IngestResponse(BaseModel):
    """Response body for POST /ingest — always 202 Accepted."""

    job_id: str
    book_id: str
    status: BookStatus = BookStatus.PROCESSING
    message: str = "Ingestion started. Monitor status via Firestore Realtime."


# ---------------------------------------------------------------------------
# Chat schemas
# ---------------------------------------------------------------------------


class ChatRequest(BaseModel):
    """Request parameters for the chat endpoint (passed as query params for SSE)."""

    book_id: str
    user_id: str
    question: str = Field(min_length=1, max_length=2000)


class ChatContext(BaseModel):
    """
    Internal schema for the assembled RAG context before LLM generation.
    Used by prompt.py. Useful for logging and debugging retrieval quality.
    """

    question: str
    chunks: list[ChunkResult]
    book_title: str | None = None

    @property
    def formatted_context(self) -> str:
        """
        Formats chunks for injection into the RAG prompt.

        Chunks are sorted by chunk_index (book position), not by relevance score.
        Narrative order helps the LLM understand context — if two passages both
        score 0.85, reading them in book order is more coherent than relevance order.
        """
        sorted_chunks = sorted(self.chunks, key=lambda c: c.chunk_index)

        parts = []
        for chunk in sorted_chunks:
            header = f"[{chunk.chapter}]" if chunk.chapter else "[excerpt]"
            parts.append(f"{header}\n{chunk.content}")

        return "\n\n---\n\n".join(parts)
