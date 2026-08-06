# ADR-011: Consolidate Structured LLM Output on LangChain, Narrow Pydantic AI to Demonstrated Need

## Status
Accepted — narrows ADR-009, expands ADR-007's scope

## Date
2026-08-06

## Context

ADR-009 adopted Pydantic AI as a second LLM-facing framework, scoped to two structured-output
call sites: the RAG evaluation judge (`notebooks/03_retrieval_evaluation.ipynb`) and the
metadata-extraction fallback (`ingestion/library_manager.py`). It explicitly considered and
rejected using LangChain's `with_structured_output()` for these, reasoning that it would dilute
ADR-007's deliberately narrow LangChain scope and that Pydantic AI's output type integrates more
directly with the project's existing `shared/models.py` schema discipline.

Revisiting with a different priority: default to LangChain wherever it can do the job without a
real downside, and bring in Pydantic AI only where a demonstrated need justifies a second
framework — not preemptively. Both current Pydantic AI use cases are, structurally, the same
shape as `embedder.py`/`chat/streamer.py`: a leaf call to an external LLM provider, not RAG
mechanics that need full control (chunking, retrieval, prompt construction stay out of scope,
unaffected by this ADR).

The one substantive technical difference between the two libraries here: Pydantic AI's
`Agent(output_type=...)` retries automatically, feeding the validation error back to the model,
when returned data fails schema validation. LangChain's `with_structured_output()` validates
against the same Pydantic model but does not auto-retry on failure — that requires wiring
`RetryWithErrorOutputParser`/`OutputFixingParser` or a manual loop. Neither call site has any
implementation yet, so there is no evidence this retry behavior is actually needed at either site;
paying for it now would be speculative.

## Decision

Move both current Pydantic AI use cases to LangChain's `with_structured_output()`, using the same
`BaseChatModel` classes already established elsewhere in the project. Pydantic AI is not a
project dependency by default going forward — it returns only if a concrete, observed failure
mode demonstrates the need for validation-aware auto-retry, recorded via an ADR update at that
time.

### `notebooks/03_retrieval_evaluation.ipynb` — LLM-as-judge

```python
from langchain_google_genai import ChatGoogleGenerativeAI
from pydantic import BaseModel, Field

class EvaluationResult(BaseModel):
    faithfulness: float = Field(ge=0.0, le=1.0)
    answer_relevance: float = Field(ge=0.0, le=1.0)
    context_recall: float = Field(ge=0.0, le=1.0)
    reasoning: str

judge = ChatGoogleGenerativeAI(model="gemini-1.5-flash", temperature=0).with_structured_output(
    EvaluationResult
)

result: EvaluationResult = await judge.ainvoke(
    f"Question: {question}\nContext: {context}\nAnswer: {answer}\n"
    "Score faithfulness, answer_relevance, and context_recall from 0 to 1."
)
```

Swapping the judge to a different model family for evaluator diversity (e.g. `langchain-anthropic`'s
`ChatAnthropic`) becomes a class swap — the same ergonomics ADR-007 already established for
`chat/streamer.py`.

### `ingestion/library_manager.py` — metadata extraction fallback

```python
from langchain_google_genai import ChatGoogleGenerativeAI
from pydantic import BaseModel

class ExtractedMetadata(BaseModel):
    title: str | None
    author: str | None
    language: str | None  # ISO 639-1

extractor = ChatGoogleGenerativeAI(model="gemini-1.5-flash").with_structured_output(
    ExtractedMetadata
)

async def fallback_extract_metadata(front_matter_text: str) -> ExtractedMetadata:
    return await extractor.ainvoke(
        f"Extract the book title, author, and language from this front matter:\n{front_matter_text}"
    )
```

This also removes a dependency from the ingestion service rather than adding one: `ingestion/`
already depends on LangChain via `embedder.py` (ADR-007), so the metadata fallback no longer
needs `pydantic-ai` as a second framework alongside it.

### Scope note (amends ADR-007)

ADR-007's boundary — LangChain only where the job *is* talking to an external provider, never
where the job is RAG mechanics needing full control — is unchanged. What changes is the count of
call sites inside that boundary: four (`embedder.py`, `chat/streamer.py`, the eval judge, the
metadata fallback), not two. ADR-007's rejected alternative, "full LangChain adoption across all
services," is not being reopened — that rejection was specifically about chunking/retrieval/prompt
construction, which remain framework-free.

### Pydantic AI's status

Not removed in principle — narrowed to "adopt only when a specific, observed need justifies it,"
the same real-gain-and-written-down bar ADR-010 set for external dependencies generally. If either
call site later shows a concrete pattern of malformed/invalid LLM output that ad hoc LangChain
retry-wiring doesn't handle well, re-open this ADR with that evidence.

## Alternatives Considered

### Keep Pydantic AI for both use cases (status quo, ADR-009)
Rejected — no evidence yet that either use case needs the validation-aware auto-retry Pydantic AI
provides, so carrying a second framework's surface area (version churn risk, a second mental
model for structured LLM calls) is speculative rather than demonstrated.

### Keep Pydantic AI only for the metadata fallback (production data-integrity path), move only the eval judge to LangChain
Considered — the metadata fallback feeds a shared catalog (ADR-006) where a bad merge is costly,
a real argument for the extra safety net. **Not adopted as the default**: the fallback only fires
when OPF metadata is already missing/unusable, and a malformed extraction just means the book
falls through to being treated as new (normal ingestion, no merge) — Tiers 0-2 of ADR-006 remain
deterministic and unaffected by a bad LLM extraction here. If ingestion later shows this path
producing bad merges in practice, this alternative is the first thing to revisit.

### Drop structured-output validation retries entirely, accept occasional bad output
Rejected — `with_structured_output()` still validates against the Pydantic model; a malformed
response raises rather than silently passing through. This is an availability tradeoff (a failed
call needs handling upstream), not a data-integrity one — `shared/models.py`'s schema-at-the-boundary
guarantee still holds.

## Consequences

### Positive
- One fewer framework in the project; `pydantic-ai` drops out of every `pyproject.toml` unless a
  concrete need brings it back
- `ingestion/` and the eval notebook use the same LLM-calling pattern already established for
  `embedder.py`/`chat/streamer.py` — one mental model for "talking to an LLM" across the codebase
- Provider swapping for the judge (e.g. comparing Gemini vs. Claude as evaluator) is a class swap

### Negative
- Loses Pydantic AI's built-in validation-aware retry; a malformed structured-output response now
  raises rather than self-correcting. Both call sites (an offline eval notebook, and a narrow
  already-degraded ingestion fallback) tolerate a raised exception more easily than the production
  chat path would — why this trade is accepted here specifically, not universally
- If a future call site needs robust structured output under noisier conditions, LangChain's
  retry parsers must be hand-wired, which is exactly the boilerplate Pydantic AI existed to
  remove — accepted as a deliberate trade favoring fewer frameworks, revisitable per the migration
  path below

### Migration path
- If Pydantic AI returns, scope it narrowly to the specific call site with the demonstrated need,
  not project-wide — mirroring how ADR-007 itself started scoped to two leaf modules
- Neither `ingestion/library_manager.py` nor the eval notebook exist in code yet — this ADR is
  written ahead of implementation, so Phase 2/4 plans (`plan-feature`) should reflect LangChain
  from the start rather than migrating code later
