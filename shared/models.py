"""
shared/models.py
----------------
Pydantic schemas shared across all services (ingestion, chat, mcp).

CONCEPT: Why Pydantic?
Pydantic validates data at runtime using Python type hints. Instead of manually
checking if a field is the right type, Pydantic raises a clear error at the
boundary of your system (API input, database output) rather than deep inside
your logic. Think of it as a schema contract — like defining a struct in a
typed language.

All services import from this file. If the schema needs to change, it changes
in one place.
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

    CONCEPT: Using an Enum instead of plain strings prevents typos like
    "proccessing" from silently passing through the system. The database
    stores the string value ("pending", "ready", etc.) but Python code
    always uses BookStatus.READY — the Enum member.
    """

    PENDING = "pending"         # book record created, ingestion not started
    PROCESSING = "processing"   # ingestion pipeline running
    READY = "ready"             # chunks stored, book available for chat
    ERROR = "error"             # ingestion failed, see error_message field


# ---------------------------------------------------------------------------
# Book schemas
# ---------------------------------------------------------------------------


class BookBase(BaseModel):
    """Fields common to all book representations."""

    title: str | None = None
    author: str | None = None


class BookCreate(BookBase):
    """
    Schema for creating a new book record.
    Called by the client before uploading the epub to storage.
    The book record must exist before the ingestion service is called,
    because ingestion needs the book_id to associate chunks.
    """

    user_id: UUID


class BookRecord(BookBase):
    """
    Full book record as stored in the database.
    Returned by the API when the client polls for book status.
    """

    id: UUID
    user_id: UUID
    epub_path: str | None = None        # path in Supabase Storage
    status: BookStatus = BookStatus.PENDING
    chunk_count: int = 0
    error_message: str | None = None    # populated only when status == ERROR
    created_at: datetime
    updated_at: datetime

    class Config:
        # Allow instantiation from ORM/dict objects (Supabase returns dicts)
        from_attributes = True


# ---------------------------------------------------------------------------
# Chunk schemas
# ---------------------------------------------------------------------------


class ChunkCreate(BaseModel):
    """
    Schema for a single chunk ready to be stored.
    Created by the chunker, populated with embedding by the embedder,
    then passed to store.py.
    """

    book_id: UUID
    user_id: UUID
    content: str
    embedding: list[float]              # 1536 floats from text-embedding-3-small
    chunk_index: int                    # position in the original book (0-based)
    chapter: str | None = None          # chapter title if extractable from epub


class ChunkResult(BaseModel):
    """
    Schema for a chunk returned by the retriever.

    CONCEPT: This is THE stable interface of the entire system.
    The chat service, MCP server, and RAG evaluator all work with ChunkResult.
    The retriever implementation (pgvector today, Weaviate tomorrow) must always
    return List[ChunkResult]. If this contract holds, nothing else needs to change
    when the database is swapped.

    Fields:
        content     : the raw text of the chunk — this is what the LLM reads
        book_id     : which book this chunk belongs to
        score       : similarity score (0.0 to 1.0, higher = more relevant)
                      cosine similarity for pgvector, hybrid score for Weaviate
        chunk_index : original position in the book — useful for ordering results
                      by book position instead of relevance score
        chapter     : chapter title if available — included in the RAG prompt
                      so the LLM can cite the source chapter
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

    CONCEPT: The ingestion service receives this payload and starts the
    processing pipeline asynchronously. The client gets a 202 Accepted
    immediately and polls for status via Supabase Realtime.
    """

    epub_url: str       # full URL to the epub in Supabase Storage
    book_id: UUID       # pre-created book record ID
    user_id: UUID       # authenticated user ID


class IngestResponse(BaseModel):
    """Response body for POST /ingest — always 202 Accepted."""

    job_id: str
    book_id: UUID
    status: BookStatus = BookStatus.PROCESSING
    message: str = "Ingestion started. Monitor status via Supabase Realtime."


# ---------------------------------------------------------------------------
# Chat schemas
# ---------------------------------------------------------------------------


class ChatRequest(BaseModel):
    """
    Request body for the chat endpoint.
    In the SSE implementation, these are passed as query parameters.
    """

    book_id: UUID
    user_id: UUID
    question: str = Field(min_length=1, max_length=2000)


class ChatContext(BaseModel):
    """
    Internal schema representing the assembled RAG context before
    it is passed to the LLM. Used by prompt.py and useful for
    logging/debugging the retrieval quality.
    """

    question: str
    chunks: list[ChunkResult]
    book_title: str | None = None

    @property
    def formatted_context(self) -> str:
        """
        Formats chunks into a readable string for injection into the prompt.
        Chunks are ordered by chunk_index (book position) not by relevance score,
        because narrative order helps the LLM understand context better.
        """
        sorted_chunks = sorted(self.chunks, key=lambda c: c.chunk_index)

        parts = []
        for chunk in sorted_chunks:
            header = f"[Chapter: {chunk.chapter}]" if chunk.chapter else "[excerpt]"
            parts.append(f"{header}\n{chunk.content}")

        return "\n\n---\n\n".join(parts)
