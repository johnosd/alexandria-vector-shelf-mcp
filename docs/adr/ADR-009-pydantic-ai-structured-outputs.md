# ADR-009: Pydantic AI for Structured LLM Outputs

## Status
Accepted — narrowed by ADR-011

## Date
2026-08

## Context

ADR-007 scoped LangChain to `ingestion/embedder.py` and `chat/streamer.py` —
the two modules whose job is talking to an external provider for
provider-agnostic embedding/chat calls. That decision deliberately kept
`chat/streamer.py` as the one place a chat-facing LLM is called, streaming
plain text.

Separately, two gaps exist where the actual need isn't "call an LLM," it's
"get a validated, typed object back from an LLM call," which is a different
problem than ADR-007 solved:

1. **RAG evaluation (Phase 4).** ADR-004 defines metrics to evaluate —
   faithfulness, answer relevance, context recall — intended for
   `notebooks/03_retrieval_evaluation.ipynb`. An LLM-as-judge is the standard
   way to score these, but a judge that returns free text is fragile to parse
   and easy to get subtly wrong (e.g. silently misreading "4/5" vs "0.8").
2. **Library Manager metadata fallback (ADR-006 gap).** The dedup pipeline
   assumes usable OPF metadata (`dc:identifier`, `dc:title`, `dc:creator`).
   Malformed or scanned epubs sometimes have this missing or empty, not just
   a wrong ISBN — a case ADR-006 didn't address. Tier 1 (ISBN) and Tier 3
   (fuzzy title/author) both degrade to no signal at all in that case, which
   currently just means the book always gets treated as new.

**Update (ADR-011):** both use cases below were later moved to LangChain's
`with_structured_output()` instead — the project's preference shifted to
defaulting to LangChain wherever it can do the job without a real downside,
reserving Pydantic AI for a call site with a demonstrated need for its
validation-aware auto-retry. The reasoning that follows explains why Pydantic
AI was chosen originally; see ADR-011 for why it was narrowed back out.

`shared/models.py` already frames Pydantic as the project's schema contract
("Pydantic validates data at runtime... raises a clear error at the boundary
of your system"). Pydantic AI extends exactly that discipline to LLM calls: a
`BaseModel` declared as the expected output, with automatic validation and
retry if the model doesn't conform — rather than parsing free text and hoping.

## Decision

Adopt Pydantic AI in two scoped, non-overlapping places. Neither touches
`chat/streamer.py` — that stays LangChain per ADR-007. Using both libraries
for the same job (calling the chat LLM) would be the same redundancy already
rejected for Semantic Kernel; Pydantic AI is adopted here specifically because
its niche (typed, validated output) is one LangChain's scope in this project
doesn't cover.

### `notebooks/03_retrieval_evaluation.ipynb` — LLM-as-judge

```python
from pydantic import BaseModel, Field
from pydantic_ai import Agent

class EvaluationResult(BaseModel):
    faithfulness: float = Field(ge=0.0, le=1.0)
    answer_relevance: float = Field(ge=0.0, le=1.0)
    context_recall: float = Field(ge=0.0, le=1.0)
    reasoning: str

judge = Agent("google-gla:gemini-1.5-flash", output_type=EvaluationResult)

result = await judge.run(
    f"Question: {question}\nContext: {context}\nAnswer: {answer}\n"
    "Score faithfulness, answer_relevance, and context_recall from 0 to 1."
)
```

The judge's output is a validated `EvaluationResult`, not text to regex out of
a response — directly usable in the evaluation notebook's scoring tables.

### `ingestion/library_manager.py` — metadata extraction fallback

Only invoked when OPF metadata is missing or unusable (not merely a failed
ISBN checksum, which Tier 1 already handles without an LLM call):

```python
class ExtractedMetadata(BaseModel):
    title: str | None
    author: str | None
    language: str | None  # ISO 639-1

metadata_extractor = Agent("google-gla:gemini-1.5-flash", output_type=ExtractedMetadata)

async def fallback_extract_metadata(front_matter_text: str) -> ExtractedMetadata:
    result = await metadata_extractor.run(
        f"Extract the book title, author, and language from this front matter:\n{front_matter_text}"
    )
    return result.output
```

The result feeds the same `normalized_title`/`normalized_author`/`language`
fields ADR-006 already defined on `BookRecord` — this is a new metadata
*source*, not a new schema.

### Explicitly out of scope

- **`chat/streamer.py`** — stays LangChain (ADR-007). The chat flow needs
  streamed prose, not a validated object; Pydantic AI's advantage doesn't
  apply there.
- **`ingestion/embedder.py`** — not an LLM call at all, stays LangChain
  (ADR-007).
- **Tier 0-2 of ADR-006** (file hash, ISBN, content hash) — unaffected,
  deterministic, no LLM involved. The metadata fallback only fires when those
  signals are already absent.

## Alternatives Considered

### Free-text prompting + manual parsing
The status quo for both gaps. **Rejected** — regex/string parsing of LLM
output is exactly the fragility Pydantic AI exists to remove, and
`shared/models.py` already committed this project to schema-validated
boundaries everywhere else.

### Extend LangChain's structured output support instead
LangChain does have `with_structured_output()`. **Rejected** — it would mean
`ingestion/embedder.py`/`chat/streamer.py`'s dependency doing double duty for
an unrelated concern (structured extraction vs. provider-agnostic streaming),
diluting the scoped, deliberate-use story ADR-007 established. Pydantic AI's
tighter integration with the Pydantic models this project already standardizes
on (`shared/models.py`) is a better fit for this specific job.

## Consequences

### Positive
- Evaluation notebook gets typed, directly-scorable judge output instead of
  free-text parsing
- Closes a real gap in ADR-006: books with missing/unusable OPF metadata no
  longer silently fall through dedup with no signal at all
- Consistent with the project's existing schema-at-the-boundary philosophy
  (`shared/models.py`) rather than introducing a new pattern

### Negative
- A third LLM-related dependency in the project (alongside the two
  LangChain packages from ADR-007) — mitigated by non-overlapping scope, so a
  breaking change in one doesn't touch the other
- The metadata fallback adds a paid LLM call to the ingestion path for the
  subset of epubs with unusable metadata — acceptable since it only fires
  when Tier 0-2 dedup and OPF extraction have already failed to produce a
  usable book identity, not on every upload
