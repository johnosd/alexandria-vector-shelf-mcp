# ADR-004: RAG Prompt Design

## Status
Accepted

## Date
2025-01

## Context

The chat service retrieves relevant chunks from Firestore and passes them to Gemini Flash
as context for answering the user's question. The prompt structure directly determines
the quality, accuracy, and behavior of the LLM's responses.

Key goals:
- LLM must only answer from the retrieved context — not from its training data
- Responses must be honest about what the book says vs. what the LLM infers
- Source chapters should be cited when possible
- The LLM must gracefully say "I don't know" rather than hallucinate

## Decision

Use a **strict grounded RAG prompt** with the following structure:

```python
SYSTEM_PROMPT = """You are Alexandria, a reading assistant specialized in the book
the user is currently reading.

Your rules:
1. Answer ONLY based on the context passages provided below.
2. If the answer is not in the context, say: "I couldn't find that in the book."
3. When possible, mention which chapter the information comes from.
4. Do not use knowledge from your training that isn't supported by the context.
5. Keep answers concise and cite the source passage when relevant.
"""

def build_prompt(question: str, chunks: list[ChunkResult], book_title: str) -> str:
    # Sort by book position for narrative coherence
    sorted_chunks = sorted(chunks, key=lambda c: c.chunk_index)

    context_parts = []
    for chunk in sorted_chunks:
        header = f"[{chunk.chapter}]" if chunk.chapter else "[excerpt]"
        context_parts.append(f"{header}\n{chunk.content}")

    context = "\n\n---\n\n".join(context_parts)

    return f"""Book: {book_title}

Context passages from the book:
{context}

---

User question: {question}

Answer based strictly on the context above:"""
```

### Why sort by chunk_index instead of score

Chunks are ordered by their position in the book (chunk_index), not by their
relevance score (cosine similarity). This preserves narrative flow — if two chunks
both score 0.85, it is more coherent to present them in book order so the LLM
reads them as the author intended.

### Why "I couldn't find that in the book" over hallucination

LLMs tend to fill gaps with plausible-sounding but fabricated information. For a
reading assistant, a wrong answer about a book's content is worse than no answer —
it undermines trust in the tool. The strict grounding instruction forces the model
to be honest about the limits of its retrieved context.

## Alternatives Considered

### Permissive prompt (use training knowledge + context)
Allows the LLM to supplement context with general knowledge.
Rejected: hallucination risk is too high for book-specific facts. A character's name,
a plot point, or a technical definition stated incorrectly would be worse than silence.

### Structured JSON output
Force the LLM to return `{"answer": "...", "source_chapter": "...", "confidence": 0.9}`.
Deferred to Phase 4 — useful for the evaluation notebook but adds parsing complexity
and breaks streaming SSE (streaming JSON is harder to render token-by-token).

### Reranking before prompting
Re-score the top-k chunks using a cross-encoder model before building the prompt.
Produces better context selection. Deferred to Phase 4 as a quality improvement —
adds latency and a model dependency not justified for MVP.

## Consequences

### Positive
- Predictable, auditable behavior — easy to understand why an answer is good or bad
- Honest "I don't know" responses build user trust
- Chapter citations help users find source passages independently
- Narrative ordering makes context coherent for the LLM

### Negative
- Strict grounding may refuse to answer questions that require synthesizing multiple
  books (cross-book queries) — acceptable for single-book chat
- Chapter metadata may be missing for poorly structured epubs — handled gracefully
  by the `[excerpt]` fallback

### Evaluation

RAG prompt quality should be evaluated with the metrics in `notebooks/03_retrieval_evaluation.ipynb`:
- **Faithfulness:** does the answer only use information from the context?
- **Answer relevance:** does the answer actually address the question?
- **Context recall:** do the retrieved chunks contain the information needed?
