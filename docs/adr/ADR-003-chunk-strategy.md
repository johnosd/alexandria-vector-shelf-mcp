# ADR-003: Chunking Strategy

## Status
Accepted

## Date
2025-01

## Context

The ingestion pipeline must split epub book text into chunks before generating embeddings.
The chunking strategy is the single most important factor in RAG quality — more than the
choice of embedding model or LLM. A poor chunking strategy produces irrelevant retrievals
regardless of how good the rest of the system is.

Key tensions in chunking:
- **Too large:** chunks contain multiple topics — embedding represents an average of meanings,
  similarity search loses precision
- **Too small:** chunks lose surrounding context — the LLM can't reason about the passage
- **Boundary problem:** important information that falls at the boundary between two chunks
  gets cut off and may be missed by retrieval

## Decision

Use **fixed-size character chunking with overlap**, with the following parameters as defaults:

```
CHUNK_SIZE    = 500 characters  (~100–150 words, ~1–2 paragraphs)
CHUNK_OVERLAP = 50 characters   (~1–2 sentences of repeated content)
```

Both values are configurable via environment variables so they can be tuned without
code changes.

### Why fixed-size over semantic chunking

Semantic chunking (splitting on sentence or paragraph boundaries detected by an NLP model)
produces better chunks in theory but:

1. Requires an additional NLP library (spaCy, NLTK) — more dependencies
2. Processing time increases significantly for long books
3. Semantic chunkers are sensitive to epub parsing quality, which varies widely
4. For a portfolio MVP, the quality difference is not perceptible with well-written books

Fixed-size chunking with overlap is the industry-standard baseline. It is simple,
fast, predictable, and debuggable.

### Why overlap

The overlap solves the boundary problem. If an important passage falls at chunk boundary
N/N+1, it will appear fully in either chunk N (in the tail) or chunk N+1 (in the head).
The retriever will find it in at least one of the two.

```
CONCEPT: Sliding window
Chunk 0: [0 ........... 500]
Chunk 1:         [450 ........... 950]   ← 50-char overlap with chunk 0
Chunk 2:                  [900 ........... 1400]
```

This is analogous to a sliding window operation in time series data — a concept
familiar from data engineering.

### Chapter boundary preservation

When an epub chapter boundary is detected, the chunk is finalized at that boundary
regardless of its current size. This prevents the chunker from mixing content from
two different chapters into a single chunk, which would confuse the embedding.

The chapter title is stored as metadata on each chunk (`chapter` field) so the
RAG prompt can cite the source chapter in its response.

## Alternatives Considered

### Recursive character splitting
Tries to split on paragraphs first, then sentences, then characters.
More natural boundaries, but harder to reason about chunk sizes.
Deferred to Phase 4 as a quality improvement experiment
(see `notebooks/02_chunking_strategies.ipynb`).

### Semantic chunking (embedding-based)
Splits where the embedding similarity between adjacent sentences drops sharply.
Best quality, but slow and adds NLP dependencies.
Planned as a Phase 4 experiment — compare RAG evaluation scores.

### Token-based chunking
Splits by token count instead of character count.
More precise for LLM context window management.
Deferred — adds tiktoken dependency and character-based is simpler to explain.

## Consequences

### Positive
- Simple to implement, test, and explain
- Configurable without code changes
- Predictable chunk sizes — easy to reason about context window usage
- Chapter metadata preserved for source citation in RAG responses

### Negative
- May split mid-sentence if sentence length exceeds CHUNK_SIZE
- Does not respect semantic boundaries — a topic can span multiple chunks
- Overlap means ~10% storage overhead (acceptable at this scale)

### Tuning guidance

If RAG response quality is poor, the first thing to tune is chunk size:
- Questions about specific facts → smaller chunks (300–400 chars) improve precision
- Questions about themes or summaries → larger chunks (700–1000 chars) improve context
- Technical books with dense content → smaller overlap is sufficient (20–30 chars)
- Narrative fiction → larger overlap helps preserve story flow (80–100 chars)

See `notebooks/02_chunking_strategies.ipynb` for a systematic comparison.
