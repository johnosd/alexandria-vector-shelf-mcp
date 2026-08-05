# ADR-006: Library Deduplication and Catalog Management

## Status
Accepted

## Date
2026-08

## Context

The original design (README, ADR-001–005) assumed the client pre-creates a `book_id`
before calling the ingestion service (`IngestRequest` requires an existing `book_id`).
This left a gap: nothing in the system identifies whether an uploaded epub is a book
already in the library or a genuinely new one. Every `books/{book_id}` document was
also scoped to a single `user_id`, meaning two different users uploading the same
book would each get their own copy of the chunks and embeddings — the same content
processed and stored twice, at double the embedding API cost.

Alexandria owns the reading library. Identifying and organizing that library —
including avoiding duplicate processing — is Alexandria's responsibility, not the
client's. This requires a step between epub upload and ingestion that decides:
is this book already in the catalog, or does it need to be processed?

## Decision

### Global catalog, not per-user copies

`books/{book_id}` becomes a canonical catalog entry shared by all users. Ownership
is tracked separately in a new `user_library/{user_id}/books/{book_id}` subcollection
(the "shelf"). Chunk content (`chunks/{chunk_id}`) is also shared — it no longer
carries `user_id`. If 50 users upload the same book, embedding runs once; the other
49 uploads only create a `user_library` entry.

```
books/{book_id}                              ← canonical catalog, no user_id
  isbn:                 string | null
  title:                string | null
  author:                string | null
  language:              string | null        ← ISO 639-1, from epub dc:language
  normalized_title:       string
  normalized_author:      string
  file_hash:              string               ← sha256 of the raw .epub bytes
  content_hash:            string | null        ← sha256 of extracted normalized text
  possibly_duplicate_of:   string | null         ← Tier 3 fuzzy match candidate (see below)
  status:                  pending | processing | ready | error
  chunk_count:              number
  created_at / updated_at

user_library/{user_id}/books/{book_id}        ← the "shelf", per user
  added_at:               timestamp

chunks/{chunk_id}                              ← canonical, no user_id
  book_id, content, embedding, chunk_index, chapter, created_at
```

### The Library Manager component

A new module, `ingestion/library_manager.py`, sits before the parse/chunk/embed
pipeline. It is **not** a fifth microservice — folding it into the existing
ingestion Cloud Run service keeps it consistent with ADR-002's principle of
minimizing deployable units and avoiding unnecessary infrastructure. It runs as
the first step of the same request.

Public API changes: `POST /ingest` (which assumed a pre-created `book_id`) is
replaced by `POST /library/books`, taking only `epub_path` and `user_id`. The
Library Manager decides the `book_id` — the client no longer does.

### Tiered deduplication algorithm

Matching runs cheapest-to-most-expensive, stopping at the first deterministic
hit. Only deterministic signals cause an automatic merge. A high-confidence
fuzzy match is recorded but never auto-merged, because merging two different
texts under one `book_id` corrupts a catalog every other user's library depends
on — worse than the cost of a duplicate.

| Tier | Signal | Runs | Confidence | Action |
|---|---|---|---|---|
| 0 | `file_hash` = sha256 of raw `.epub` bytes | Immediately after upload, before opening the epub | Deterministic | Auto-merge |
| 1 | Normalized, checksum-validated ISBN | After reading OPF metadata (no full parse) | Deterministic | Auto-merge |
| 2 | `content_hash` = sha256 of extracted, normalized text | After full parse, **before** calling the embedding API | Deterministic | Auto-merge |
| 3 | Fuzzy `normalized_title` + `normalized_author` similarity | Same time as Tier 1 (cheap) | Probabilistic | Flag only (`possibly_duplicate_of`), never auto-merge |

Tier 2 is placed deliberately after parsing but before embedding: it is the
last checkpoint before the pipeline's only real cost (the embedding API call).
Tier 0 catches the common case of the same file (e.g. the same scan) re-uploaded
by different users, without needing to open the epub at all.

**Normalization rules:**

- *ISBN:* strip hyphens/spaces, validate the check digit (ISBN-10 or ISBN-13/EAN-13),
  convert ISBN-10 → ISBN-13 (prefix `978`, recompute the check digit). An ISBN that
  fails validation is discarded, not trusted — malformed or copy-pasted-from-a-different-edition
  ISBNs are common in epub metadata.
- *Title/author:* Unicode NFKD to strip accents, lowercase, strip punctuation,
  collapse whitespace.
- *Fuzzy similarity:* `rapidfuzz` (`token_sort_ratio`, handles reordering like
  "Rowling, J.K." vs "J.K. Rowling"). Thresholds: title ≥ 95, author ≥ 90 — both
  must pass to record a Tier 3 candidate. This is a new, small dependency for
  `ingestion/requirements.txt` — not a framework, in the same spirit as the
  existing BeautifulSoup4 dependency.

### Pipeline sequencing

```
POST /library/books { epub_path, user_id }
        │
        ▼
Library Manager — Stage A (lightweight, no full parse)
  1. file_hash = sha256(epub bytes)         → Tier 0 check against books/
  2. Tier 0 hit → create user_library entry, return existing book_id, status=ready. DONE.
  3. Read OPF metadata (EbookLib) — isbn, title, author, language
  4. Normalize + validate ISBN                → Tier 1 check
  5. Tier 1 hit → create user_library entry, return existing book_id, status=ready. DONE.
  6. Normalize title/author                    → Tier 3 check (record candidate id, don't act on it)
  7. Create books/{id}: status=pending, file_hash, isbn, language,
     normalized_title, normalized_author, possibly_duplicate_of
  8. Create user_library entry
  9. Return 202 { book_id, status: "processing" }, hand off to the pipeline

Ingestion pipeline (same service, next steps)
  10. parser.py extracts full text
  11. content_hash = sha256(normalized text)   → Tier 2 check against other books/
  12a. Hit → delete the books/{id} created in step 7, repoint the user_library
       entry to the existing book_id, status=ready. Embedding is never called.
  12b. No hit → store content_hash on books/{id}, continue to
       chunker → embedder → store → status=ready
```

### Language handling — translations and editions are never merged

Only Tiers 0–2 are ever allowed to merge books, and all three require content
equivalence (identical bytes or identical extracted text). A translation is not
byte-identical and not text-identical to its source — it is deliberately treated
as a **separate `book_id`**, never merged, regardless of matching title/author.

This was evaluated explicitly and rejected as a simplification (import one
edition per book, treat translations as duplicates), for two reasons:

1. The embedding models chosen in ADR-002 (`text-embedding-004`,
   `text-embedding-3-small`) are general-purpose, not the dedicated multilingual
   variants (e.g. `text-multilingual-embedding-002`). Cross-lingual semantic
   similarity — a question in language A retrieving a passage in language B — is
   not guaranteed with these models, and failures are silent: a mediocre but
   plausible-looking similarity score, not an obvious error. This would violate
   the grounding principle in ADR-004, where a wrong answer is treated as worse
   than no answer.
2. The storage savings this simplification would buy are negligible — ADR-001
   already shows 20 books use ~7% of the Firestore free tier. There is no real
   resource pressure to solve for.

`language` (ISO 639-1, from the epub's `dc:language` OPF field) is stored on
`books/{book_id}` instead, purely as metadata — it lets a future UI group
editions of the same work without merging their retrieval content, and closes
the gap where the chat flow had no way to know a book's language at all.

### Security rules

```javascript
match /books/{bookId} {
  // Catalog metadata is not sensitive — any authenticated user can read it
  // (needed to discover "this book already exists" before uploading).
  allow read: if request.auth != null;
  allow write: if false; // Admin SDK only (Library Manager)
}

match /user_library/{userId}/books/{bookId} {
  allow read, write: if request.auth != null && request.auth.uid == userId;
}

match /chunks/{chunkId} {
  allow read: if request.auth != null &&
    exists(/databases/$(database)/documents/user_library/$(request.auth.uid)/books/$(resource.data.book_id));
  allow write: if false; // Admin SDK only
}
```

The chunk read rule can no longer check a denormalized `user_id` (chunks don't
have one anymore) — it checks shelf membership instead, via `exists()`.

## Alternatives Considered

### Per-user deduplication only
Keep `user_id` on `books`/`chunks`; only prevent the same user from uploading the
same book twice. **Rejected:** doesn't address the actual cost problem — popular
books still get embedded and stored once per user. Simpler, but doesn't deliver
what "avoiding duplicates" is meant to achieve.

### Merge translations/editions under one `book_id` (title+author match)
Treat the first imported language edition as canonical, ignore the rest.
**Rejected:** see "Language handling" above — gambles core retrieval quality
against an unproven cross-lingual capability, for a storage saving that ADR-001's
own numbers show is not needed.

### Auto-merge on high-confidence fuzzy title/author match
Skip creating a new book when Tier 3 similarity is very high, without requiring
a content hash. **Rejected:** title+author equality doesn't imply content
equality (different editions, revised editions, abridged versions). A false
merge here silently serves the wrong text to every user on that shelf — a data
integrity failure, not just a UX annoyance.

## Consequences

### Positive
- Embedding cost and chunk storage scale with distinct books in the system, not
  with (books × users) — the intended meaning of "avoiding duplicates"
- Deterministic-only merging means the catalog can't be silently corrupted by a
  bad fuzzy match
- `language` field closes a previously unaddressed gap in the chat flow
- No new deployable unit — Library Manager is a module inside the existing
  ingestion service

### Negative
- `chunks` security rule now requires a Firestore `exists()` lookup per read
  instead of a plain field comparison — marginally more expensive, still well
  within Firestore's rule evaluation limits at this scale
- Tier 3 candidates (`possibly_duplicate_of`) require a manual reconciliation
  step (an admin script/notebook) to actually resolve — not built in this ADR,
  left as a future tool
- **Known race condition, accepted for now:** two users uploading the same new
  book concurrently can both pass Tiers 0–3 with no match and create two
  `books/{id}` with the same eventual `content_hash`. Closing this requires
  wrapping the Tier 2 check-and-write in a Firestore transaction. Acceptable at
  single-user/low-volume MVP scale; revisit if concurrent uploads become common.

### Migration path
- If cross-lingual query support becomes an actual requirement, swap the
  embedding model to a dedicated multilingual variant
  (`text-multilingual-embedding-002`) and validate retrieval quality with
  `notebooks/03_retrieval_evaluation.ipynb` before trusting it — do not assume
  it works.
- A future admin tool can walk `books` where `possibly_duplicate_of` is set and
  merge them manually (reassign `user_library` entries, delete redundant
  `chunks`) once a human has confirmed content equivalence.
