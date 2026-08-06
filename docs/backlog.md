# Backlog

## In Progress

<!-- No feature in progress right now. -->

## Next

<!-- No item queued right now. -->

## Ideas

<!-- Loose ideas, tech debt, future improvements. -->
<!-- When adding, include enough context to resume without rebuilding the reasoning. -->
<!-- Format: - [description]. Context: [why it came up, what it affects]. -->
- Add Google Books API (primary) + Open Library API (fallback) for book metadata
  lookup in `ingestion/library_manager.py`. Context: complements ADR-006's Tier 1/3
  dedup signals and ADR-009's LLM metadata-extraction fallback for epubs with
  missing/unusable OPF metadata — a real catalog lookup is more accurate than fuzzy
  matching and cheaper than an LLM call, and both APIs are free/no-key. Accepted
  under the external-dependency policy in ADR-010. Sequencing against the ADR-009
  fallback (query catalog before or after LLM extraction) is not yet designed — do
  that as part of scoping this into a Phase 2 plan with `plan-feature`.
  Reference implementation found: `src/metadata_fetcher.py` in the prior MVP
  (`claude-pergunte-ao-livro`, sibling repo) implements this exact lookup — stdlib
  `urllib` only, isbn→title/author fallback chain, network errors silenced by
  design, three sources (epub/google/openlibrary) kept separate. Good starting
  point to adapt: needs to move sync calls to `async`, and the storage shape needs
  a decision (store the three source blobs separately like the reference does, or
  normalize into the single `title`/`author`/`isbn`/`language` fields already in
  `schema.md`).

- Evaluate whether hybrid search (semantic + BM25 via Reciprocal Rank Fusion) is
  achievable directly on Firestore, without adding an external search service.
  Context: ADR-001's "Negative" section states hybrid search would require "a
  separate full-text search solution (e.g., Algolia or Elasticsearch)". The prior
  MVP's `src/retriever_firestore.py` shows a working counter-example: since every
  query is already scoped to one `book_id` (same as `shared/retriever.py` today),
  it fetches that book's chunks and runs `rank_bm25` in memory, then combines with
  the vector search results via RRF (`src/retriever.py`'s `_rrf`) — no separate
  search service needed at this chunk-per-book scale. This changes the cost/benefit
  of a future hybrid-search decision and should be reflected as a note or
  alternative in ADR-001 (or a new ADR) before `shared/retriever.py` gains a
  lexical path — not implemented yet, needs its own scoping pass.

- Evaluate parent-child chunking (small "child" chunks indexed for precise search,
  larger "parent" blocks substituted in before reranking/generation for coherent
  context) as an addition to ADR-003's chunking strategy. Context: ADR-003's
  "Alternatives Considered" covers recursive splitting, semantic chunking, and
  token-based chunking, but not this two-level approach — it's a different axis
  (granularity split by role, not where the split point falls). The prior MVP's
  `src/chunker.py` (`chunk_chapters_hierarchical`) implements it: ~450-char
  children indexed for embedding/BM25, ~1000-char parents (100-char overlap)
  stored separately and substituted in via `expand_to_parents` (with dedup by
  `parent_id`) before the top-k is finalized. Worth adding as a candidate for the
  Phase 4 chunking-quality experiment ADR-003 already earmarks, with the
  reference's own before/after comparison as a starting data point.

- Note for the record: the prior MVP's `src/clients.py` hand-rolls a
  multi-provider (Anthropic/OpenAI/Gemini/DeepSeek/Qwen) client dispatch dict —
  structurally the exact thing ADR-007 rejected doing manually and chose
  LangChain's `BaseChatModel`/`Embeddings` interfaces to solve instead. No action
  needed; this is supporting evidence that the ADR-007/ADR-011 scoping decision
  was the right call if multi-provider support is ever revisited, not a
  counter-argument to it.

- Add Voyage AI as a second embedding-provider option alongside Vertex AI (primary)
  in `ingestion/embedder.py`, on top of the OpenAI fallback ADR-002 already
  accepted. Context: raised when comparing against the prior MVP, which used
  Voyage AI (`voyage-3.5`) as its only embedding provider. Voyage is not a GCP
  product, so per ADR-010's three-part test this needs a written-down real gain
  (e.g. retrieval-quality comparison via `notebooks/03_retrieval_evaluation.ipynb`,
  not just "another option") before it's accepted as a third provider — scope as
  an ADR-002 update if/when picked up, not a silent addition to `embedder.py`.

- Add contextual enrichment to the ingestion pipeline: before embedding, prefix
  each chunk with 1-2 LLM-generated sentences situating it in the chapter
  (Anthropic's Contextual Retrieval technique). Context: the prior MVP's
  `src/enricher.py` implements this — batches ~10 chunks per LLM call (one call
  covers the whole chapter as context), parallelized across threads, with
  Anthropic prompt-caching cutting the repeated chapter-text cost. The MVP's own
  numbers (unverified, from its README, worth re-measuring here): RAG pass@10
  87% baseline → 92% with enrichment. Explicitly wanted in this project, but must
  ship as an **opt-in, easily toggled flag** on the ingestion pipeline (mirrors
  the reference's `--no-enrich` CLI flag) — it adds one LLM call per chunk-batch
  at ingest time, a real cost/latency tradeoff that shouldn't be forced on every
  ingestion run. Needs scoping: which phase it belongs to (Phase 2 ingestion vs.
  Phase 4 quality hardening), which provider/model, and how the toggle is exposed
  (env var, request param, or both).

- Build a lightweight interface for manually exercising ingestion + chat during
  development — upload an epub, ask questions, inspect retrieved chunks/scores.
  Context: CLAUDE.md's "Verification philosophy" already reserves manual
  verification for exactly this ("does a chat answer read as good/relevant") since
  it's not something a unit test can check. The prior MVP's `app.py` (Streamlit,
  three tabs: ask/ingest/books) is one concrete way to do this cheaply, but no
  commitment yet to Streamlit specifically — open to alternatives (e.g. a thin
  FastAPI + HTML page, or just a REPL-style script) when this gets scoped. Not
  part of the target architecture's shipped surface (NeoReader app + MCP clients
  are the real consumers) — this is dev tooling only.

## Done

<!-- Shipped features. Moved here by ship-feature. -->
