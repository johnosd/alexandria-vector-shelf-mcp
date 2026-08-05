# Firestore Collection Design

## Overview

alexandria-vector-shelf-mcp uses Cloud Firestore as the single database for all data:
the book catalog, chunk text, vector embeddings, and processing status. Firestore's
native vector search capability (KNN) replaces a separate vector database.

`books` and `chunks` form a global catalog shared by all users; `user_library`
tracks per-user ownership separately. See ADR-006 for why and how deduplication
works across users.

---

## Collections

### `users/{user_id}`

Stores basic user profile. `user_id` is the Firebase Auth UID.

```
users/
  {uid}/
    displayName:  string
    email:        string | null
    createdAt:    timestamp
    updatedAt:    timestamp
```

### `books/{book_id}`

A **global catalog entry** — shared across all users, not owned by any single one.
See ADR-006. If two users upload the same book, they share one `books` document
and one set of `chunks`; only their `user_library` entry differs.

```
books/
  {book_id}/
    isbn:                   string | null   ← normalized ISBN-13, checksum-validated
    title:                  string | null   ← extracted from epub metadata
    author:                 string | null   ← extracted from epub metadata
    language:               string | null   ← ISO 639-1, from epub dc:language
    normalized_title:       string          ← lowercase, no accents/punctuation — fuzzy match key
    normalized_author:      string          ← same normalization, for fuzzy match
    file_hash:              string          ← sha256 of the raw .epub bytes (Tier 0 dedup key)
    content_hash:           string | null   ← sha256 of extracted normalized text (Tier 2 dedup key)
    possibly_duplicate_of:  string | null   ← Tier 3 fuzzy-match candidate book_id, flagged not merged
    epub_path:              string          ← path in Firebase Storage (gs://bucket/path)
    status:                 string          ← "pending" | "processing" | "ready" | "error"
    chunk_count:             number          ← populated when status = "ready"
    error_message:           string | null   ← populated when status = "error"
    created_at:              timestamp
    updated_at:              timestamp
```

**Status lifecycle:**
```
pending → processing → ready
                    ↘ error
```

### `user_library/{user_id}/books/{book_id}`

The per-user "shelf" — tracks which catalog books a user has access to. This is
the only user-scoped piece of library data; the book content itself
(`books`, `chunks`) is shared. The NeoReader app subscribes to the referenced
`books/{book_id}` document via Firestore Realtime to receive live processing
status updates.

```
user_library/
  {user_id}/
    books/
      {book_id}/
        added_at:  timestamp
```

**Realtime subscription (NeoReader app):**
```javascript
// NeoReader — useBookStatus.ts
db.collection("books").doc(bookId)
  .onSnapshot((doc) => {
    const status = doc.data().status
    if (status === "ready") unlockChatButton()
    if (status === "error") showError(doc.data().error_message)
  })
```

### `chunks/{chunk_id}`

Stores every text segment of every catalog book with its vector embedding. Shared
across all users who have the book on their shelf — not duplicated per user. This
is the largest collection — a typical 300-page book produces ~500–800 chunks.

```
chunks/
  {chunk_id}/
    book_id:       string          ← reference to books/{book_id}
    content:       string          ← raw text of this chunk
    embedding:     Vector(1536)    ← Firestore native vector type
    chunk_index:   number          ← 0-based position in the original book
    chapter:       string | null   ← chapter title if extractable from epub
    created_at:    timestamp
```

**Why there's no `user_id` on chunks:**
Chunks belong to the catalog book, not to a user — that's the point of the
global catalog (ADR-006). Access control is enforced via a Firestore Security
Rules `exists()` lookup against the requesting user's `user_library` entry
instead of a denormalized field (see Security Rules below).

---

## Indexes

### Vector index (required before first query)

Create once via gcloud CLI:

```bash
gcloud firestore indexes composite create \
  --collection-group=chunks \
  --query-scope=COLLECTION \
  --field-config=order=ASCENDING,field-path="book_id" \
  --field-config=field-path="embedding",vector-config='{"dimension":"1536","flat":"{}"}'
```

This creates a composite index that:
1. Filters by `book_id` (equality filter)
2. Performs KNN vector search on `embedding`

**Important:** The `dimension` value (1536) must match the embedding model output.
If you change models, you must delete the index and recreate it with the new dimension.

### Standard indexes (auto-created by Firestore for simple queries)

Firestore auto-creates single-field indexes. Composite indexes for queries like
`WHERE isbn == X` or `WHERE normalized_title == X AND normalized_author == X` on
`books` (used by the Library Manager's Tier 1/3 dedup checks, ADR-006) must be
created manually or will be suggested by Firestore in error messages during
development.

---

## Security Rules

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Users can only read and write their own profile
    match /users/{userId} {
      allow read, write: if request.auth != null
                         && request.auth.uid == userId;
    }

    // Books: global catalog, not user-owned (ADR-006).
    // Metadata isn't sensitive — any authenticated user can read it, which is
    // needed to discover "this book already exists" before uploading.
    // All writes go through the Library Manager via the Admin SDK.
    match /books/{bookId} {
      allow read: if request.auth != null;
      allow write: if false;
    }

    // User library: the per-user "shelf" — which catalog books this user has.
    match /user_library/{userId}/books/{bookId} {
      allow read, write: if request.auth != null
                         && request.auth.uid == userId;
    }

    // Chunks: shared catalog content, not user-owned.
    // Read access requires the requesting user to have this book on their shelf.
    // Write is restricted to server-side (Admin SDK bypasses rules).
    match /chunks/{chunkId} {
      allow read: if request.auth != null &&
        exists(/databases/$(database)/documents/user_library/$(request.auth.uid)/books/$(resource.data.book_id));

      allow write: if false;
    }
  }
}
```

---

## Capacity estimates (single user, MVP)

| Item | Estimate |
|---|---|
| Average book size | 300 pages |
| Characters per page | ~1800 |
| Total characters per book | ~540,000 |
| Chunks per book (500 chars, 50 overlap) | ~600 |
| Embedding size per chunk | 1536 floats × 4 bytes = ~6KB |
| Storage per book (chunks only) | ~3.6MB |
| 20 books in library | ~72MB |
| Firestore free tier (Spark) | 1GB storage |

A 20-book personal library uses ~7% of the free tier storage quota.
Reads/writes are well within free tier limits for single-user usage.

This is per **distinct** book, not per user — the global catalog (ADR-006) means
a book uploaded by multiple users is stored once, so this estimate scales with
library variety, not with user count.

---

## Setup checklist (Phase 1)

- [ ] Create Firebase project at https://console.firebase.google.com
- [ ] Enable Firestore in Native mode
- [ ] Enable Firebase Auth (Anonymous + Google)
- [ ] Create Firebase Storage bucket
- [ ] Deploy Security Rules above via Firebase CLI
- [ ] Create vector index via gcloud CLI command above
- [ ] Download service account JSON for local development
- [ ] Set `GOOGLE_APPLICATION_CREDENTIALS` in `.env`
