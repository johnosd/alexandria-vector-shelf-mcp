"""
shared/db.py
------------
Supabase client — singleton pattern for connection reuse.

CONCEPT: Why a singleton?
Creating a new database connection on every request is expensive. A singleton
ensures the client is created once at startup and reused across all requests.
In Python, module-level variables are initialized once — importing this module
from multiple places always returns the same client instance.

CONCEPT: Service key vs Anon key
Supabase has two types of API keys:

  ANON KEY    — safe to expose to clients (browsers, mobile apps).
                Respects Row Level Security (RLS) policies.
                A user can only read/write their own rows.

  SERVICE KEY — bypasses RLS entirely. Has full database access.
                NEVER expose this in client-side code.
                Used only in server-side services (this file).

The ingestion and chat services run server-side, so they use the SERVICE KEY.
The NeoReader app uses the ANON KEY via the official Supabase JS SDK.
"""

import os

from supabase import Client, create_client


def _create_supabase_client() -> Client:
    """
    Creates and returns a Supabase client using environment variables.

    Raises:
        ValueError: If required environment variables are not set.
                    Fails loudly at startup rather than silently at query time.
    """
    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_KEY")

    if not url:
        raise ValueError(
            "SUPABASE_URL environment variable is not set. "
            "Check your .env file."
        )
    if not key:
        raise ValueError(
            "SUPABASE_SERVICE_KEY environment variable is not set. "
            "Check your .env file. "
            "Note: use the SERVICE KEY here, not the anon key."
        )

    return create_client(url, key)


# ---------------------------------------------------------------------------
# Module-level singleton
# ---------------------------------------------------------------------------

# This is created once when the module is first imported.
# All services import `supabase` from this module.
supabase: Client = _create_supabase_client()


# ---------------------------------------------------------------------------
# Typed helpers
# ---------------------------------------------------------------------------


async def get_book(book_id: str) -> dict | None:
    """
    Fetches a single book record by ID.

    Returns None if the book does not exist.
    The service key bypasses RLS, so this returns results regardless of user_id.
    The caller is responsible for verifying ownership if needed.
    """
    response = (
        supabase.table("books")
        .select("*")
        .eq("id", book_id)
        .single()
        .execute()
    )
    return response.data


async def update_book_status(
    book_id: str,
    status: str,
    chunk_count: int | None = None,
    error_message: str | None = None,
) -> None:
    """
    Updates the processing status of a book.

    This triggers a Supabase Realtime event that the client app listens to,
    enabling real-time status updates without polling.

    Args:
        book_id       : UUID of the book to update
        status        : new status string (use BookStatus enum values)
        chunk_count   : total number of chunks stored (set when status = "ready")
        error_message : error details (set when status = "error")
    """
    payload: dict = {"status": status, "updated_at": "now()"}

    if chunk_count is not None:
        payload["chunk_count"] = chunk_count

    if error_message is not None:
        payload["error_message"] = error_message

    supabase.table("books").update(payload).eq("id", book_id).execute()
