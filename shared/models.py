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
from enum import StrEnum

from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class BookStatus(StrEnum):
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
    Internal payload used by the Library Manager to create a new catalog entry.

    Only created after the ADR-006 Tier 0-3 deduplication checks (file hash,
    ISBN, content hash, fuzzy title/author) find no existing match. Books are
    a global catalog, not owned by a single user — see BookRecord.
    """

    isbn: str | None = None                # normalized ISBN-13, checksum-validated
    title: str | None = None               # extracted from epub metadata
    author: str | None = None              # extracted from epub metadata
    language: str | None = None            # ISO 639-1, from epub dc:language
    normalized_title: str                  # fuzzy-match key (ADR-006 Tier 3)
    normalized_author: str                 # fuzzy-match key (ADR-006 Tier 3)
    file_hash: str                         # sha256 of raw .epub bytes (Tier 0 key)
    epub_path: str | None = None           # gs://bucket/path in Firebase Storage
    possibly_duplicate_of: str | None = None  # Tier 3 candidate, flagged not merged


class BookRecord(BaseModel):
    """
    Full book document as returned by the API.

    CONCEPT: Global catalog, not per-user (ADR-006)
    A book is not owned by a single user — if two users upload the same book,
    they share one BookRecord and one set of chunks. Per-user access is tracked
    separately in `user_library` (see LibraryEntry). This is what makes
    deduplication actually save embedding cost and storage across users, not
    just prevent the same user from re-uploading their own book.
    """

    id: str
    isbn: str | None = None
    title: str | None = None
    author: str | None = None
    language: str | None = None
    normalized_title: str
    normalized_author: str
    file_hash: str
    content_hash: str | None = None        # set once parsing completes (Tier 2 key)
    possibly_duplicate_of: str | None = None
    epub_path: str | None = None
    status: BookStatus = BookStatus.PENDING
    chunk_count: int = 0
    error_message: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None

    class Config:
        from_attributes = True


class LibraryEntry(BaseModel):
    """
    A user's "shelf" record — stored at user_library/{user_id}/books/{book_id}.

    Tracks that a user has a catalog book in their library. Contains no book
    content; the content lives once in BookRecord/ChunkResult regardless of how
    many users' shelves reference it.
    """

    user_id: str
    book_id: str
    added_at: datetime | None = None


# ---------------------------------------------------------------------------
# Chunk schemas
# ---------------------------------------------------------------------------


class ChunkCreate(BaseModel):
    """
    Schema for a single chunk ready to be stored in Firestore.
    Created by chunker.py, populated with embedding by embedder.py,
    then passed to store.py.

    No user_id: chunks belong to the catalog book, not a user (ADR-006).
    """

    book_id: str
    content: str
    embedding: list[float]          # output of embedding model (768 floats, Vertex AI
                                     # text-embedding-004 — ADR-002; 1536 if the OpenAI
                                     # fallback is used, requires reindexing, ADR-001)
    chunk_index: int                # 0-based position in the book
    chapter: str | None = None      # chapter title if extractable


class ChunkResult(BaseModel):
    """
    Schema for a chunk returned by the retriever.

    CONCEPT: This is THE stable interface of the entire system.
    The chat service, MCP server, prompt builder, and RAG evaluator all work
    with ChunkResult. The retriever implementation (Firestore today, a different
    vector database possibly tomorrow — see ADR-001) must always return
    list[ChunkResult]. If this contract holds,
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
# Library / ingestion schemas
# ---------------------------------------------------------------------------


class LibraryUploadRequest(BaseModel):
    """
    Request body for POST /library/books — the public entry point (ADR-006).

    Replaces the old assumption that the client pre-creates a book_id. The
    Library Manager decides the book_id: it runs the Tier 0-3 dedup checks
    and either attaches the user to an existing catalog book or creates a
    new one and starts the ingestion pipeline.
    """

    epub_path: str      # path in Firebase Storage (gs://bucket/path), already uploaded
    user_id: str        # Firebase Auth UID


class LibraryUploadResponse(BaseModel):
    """Response body for POST /library/books."""

    book_id: str
    status: BookStatus
    deduplicated: bool = False   # True if matched an existing book (Tier 0/1/2) — no reprocessing
    message: str = "Monitor status via Firestore Realtime on the book document."


class IngestRequest(BaseModel):
    """
    Internal handoff from the Library Manager to the parse/chunk/embed pipeline,
    once a book_id has been assigned (new book, no dedup match found).

    Not a public endpoint — POST /library/books is the public entry point.
    No user_id: ingestion produces catalog content, not user-scoped content.
    """

    epub_path: str      # path in Firebase Storage (gs://bucket/path)
    book_id: str        # Firestore book document ID, assigned by the Library Manager


class IngestResponse(BaseModel):
    """Response body for the internal ingestion handoff — always 202 Accepted."""

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
