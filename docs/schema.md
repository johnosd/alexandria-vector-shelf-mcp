# Firestore Collection Design

## Overview

alexandria-vector-shelf-mcp uses Cloud Firestore as the single database for all data:
user books, chunk text, vector embeddings, and processing status. Firestore's native
vector search capability (KNN) replaces a separate vector database.

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

Tracks every epub uploaded by a user. The NeoReader app subscribes to this document
via Firestore Realtime to receive live processing status updates.

```
books/
  {book_id}/
    user_id:        string          ← Firebase Auth UID
    title:          string | null   ← extracted from epub metadata
    author:         string | null   ← extracted from epub metadata
    epub_path:      string          ← path in Firebase Storage (gs://bucket/path)
    status:         string          ← "pending" | "processing" | "ready" | "error"
    chunk_count:    number          ← populated when status = "ready"
    error_message:  string | null   ← populated when status = "error"
    created_at:     timestamp
    updated_at:     timestamp
```

**Status lifecycle:**
```
pending → processing → ready
                    ↘ error
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

Stores every text segment of every book with its vector embedding. This is the
largest collection — a typical 300-page book produces ~500–800 chunks.

```
chunks/
  {chunk_id}/
    book_id:       string          ← reference to books/{book_id}
    user_id:       string          ← denormalized for faster security filtering
    content:       string          ← raw text of this chunk
    embedding:     Vector(1536)    ← Firestore native vector type
    chunk_index:   number          ← 0-based position in the original book
    chapter:       string | null   ← chapter title if extractable from epub
    created_at:    timestamp
```

**Why `user_id` is denormalized on chunks:**
Firestore Security Rules cannot do cross-collection lookups efficiently. Storing
`user_id` directly on each chunk allows a simple, fast rule:
`allow read: if request.auth.uid == resource.data.user_id`

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
`WHERE user_id == X ORDER BY created_at DESC` must be created manually or will be
suggested by Firestore in error messages during development.

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

    // Books: users can CRUD their own books only
    match /books/{bookId} {
      allow read, write: if request.auth != null
                         && request.auth.uid == resource.data.user_id;

      allow create: if request.auth != null
                    && request.auth.uid == request.resource.data.user_id;
    }

    // Chunks: users can only read their own chunks
    // Write is restricted to server-side (Admin SDK bypasses rules)
    match /chunks/{chunkId} {
      allow read: if request.auth != null
                  && request.auth.uid == resource.data.user_id;

      // No client-side write — ingestion service uses Admin SDK
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
