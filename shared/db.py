"""
shared/db.py
------------
Firebase Admin SDK client — singleton pattern.

CONCEPT: Why Firebase Admin SDK instead of the client SDK?
There are two Firebase SDKs:

  Client SDK (firebase-js-sdk, flutterfire, etc.)
    - Used in the mobile app (NeoReader)
    - Respects Firestore Security Rules
    - Authenticated as the end user

  Admin SDK (firebase-admin)
    - Used in server-side services (this file)
    - Bypasses Firestore Security Rules completely
    - Authenticated as a service account with full project access
    - NEVER expose Admin SDK credentials to the client app

The ingestion and chat services run server-side, so they use the Admin SDK.
The ingestion service needs to write chunks on behalf of any user.
The chat service needs to read chunks regardless of the requesting user's session.

CONCEPT: Application Default Credentials (ADC)
In local development, we point to a service-account.json file via
GOOGLE_APPLICATION_CREDENTIALS environment variable.

In production (Cloud Run), we do NOT set this variable. Cloud Run automatically
provides credentials via the attached service account — no JSON file needed.
This is called Application Default Credentials and is the recommended pattern.
"""

import os

import firebase_admin
from firebase_admin import credentials, firestore, storage
from google.cloud.firestore_v1 import AsyncClient

# ---------------------------------------------------------------------------
# Firebase app initialization — happens once at module import time
# ---------------------------------------------------------------------------

def _initialize_firebase() -> firebase_admin.App:
    """
    Initializes the Firebase Admin SDK app.

    In local development: uses service-account.json pointed to by
    GOOGLE_APPLICATION_CREDENTIALS environment variable.

    In Cloud Run production: uses Application Default Credentials
    automatically — no env var needed.
    """
    if firebase_admin._apps:
        # Already initialized — return existing app
        return firebase_admin.get_app()

    project_id = os.environ.get("GOOGLE_CLOUD_PROJECT")
    if not project_id:
        raise ValueError(
            "GOOGLE_CLOUD_PROJECT environment variable is not set. "
            "Check your .env file."
        )

    cred_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")

    if cred_path and os.path.exists(cred_path):
        # Local development: explicit service account file
        cred = credentials.Certificate(cred_path)
    else:
        # Cloud Run production: Application Default Credentials
        cred = credentials.ApplicationDefault()

    return firebase_admin.initialize_app(cred, {
        "projectId": project_id,
        "storageBucket": os.environ.get("FIREBASE_STORAGE_BUCKET"),
    })


# Initialize once at import time
_app = _initialize_firebase()

# ---------------------------------------------------------------------------
# Module-level singletons
# ---------------------------------------------------------------------------

# Firestore async client — used for all database operations
# CONCEPT: AsyncClient vs Client
# We use the async client because our FastAPI endpoints are async.
# Mixing sync Firestore calls inside async FastAPI handlers causes
# thread-blocking — the async client avoids this.
db: AsyncClient = firestore.AsyncClient(
    project=os.environ.get("GOOGLE_CLOUD_PROJECT"),
    database=os.environ.get("FIRESTORE_DATABASE_ID", "(default)"),
)

# Firebase Storage bucket reference — used by ingestion to download epubs
storage_bucket = storage.bucket()

# Collection name constants — change via environment variables if needed
BOOKS_COLLECTION = os.environ.get("FIRESTORE_BOOKS_COLLECTION", "books")
CHUNKS_COLLECTION = os.environ.get("FIRESTORE_CHUNKS_COLLECTION", "chunks")


# ---------------------------------------------------------------------------
# Typed helpers
# ---------------------------------------------------------------------------


async def get_book(book_id: str) -> dict | None:
    """
    Fetches a single book document by ID.

    Returns None if the book does not exist.
    The Admin SDK bypasses Security Rules — the caller is responsible
    for verifying ownership if needed.
    """
    doc = await db.collection(BOOKS_COLLECTION).document(book_id).get()
    if not doc.exists:
        return None
    return {"id": doc.id, **doc.to_dict()}


async def update_book_status(
    book_id: str,
    status: str,
    chunk_count: int | None = None,
    error_message: str | None = None,
) -> None:
    """
    Updates the processing status of a book.

    This write triggers a Firestore Realtime event. The NeoReader app
    subscribes to this document and receives the update instantly via
    WebSocket — no polling required.

    Args:
        book_id       : Firestore document ID of the book
        status        : new status ("pending" | "processing" | "ready" | "error")
        chunk_count   : total chunks stored — set when status = "ready"
        error_message : error details — set when status = "error"
    """
    from google.cloud import firestore as _fs

    payload: dict = {
        "status": status,
        "updated_at": _fs.SERVER_TIMESTAMP,
    }

    if chunk_count is not None:
        payload["chunk_count"] = chunk_count

    if error_message is not None:
        payload["error_message"] = error_message

    await db.collection(BOOKS_COLLECTION)\
            .document(book_id)\
            .update(payload)
