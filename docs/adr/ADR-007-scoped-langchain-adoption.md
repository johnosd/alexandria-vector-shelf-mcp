# ADR-007: Scoped LangChain Adoption for Provider Abstraction

## Status
Accepted — partially supersedes ADR-002 ("RAG Framework: None")

## Date
2026-08

## Context

ADR-002 rejected LangChain and LlamaIndex outright: the pipeline is 4 sequential
steps needing no orchestration, direct API calls preserve full control over
chunking (the most critical RAG variable), frameworks obscure the mechanics for
a project whose README explicitly states it should be "readable by someone
learning RAG engineering," and LangChain's API has a real history of breaking
changes between versions.

That reasoning still holds for the modules where control over the mechanism
*is* the point — chunking (ADR-003), retrieval (ADR-001), and prompt
construction (ADR-004). It does not hold equally for two other modules whose
entire job is talking to an external provider and where this project has
already, repeatedly, stated provider-agnosticism as a goal: ADR-002 itself
describes `embedder.py` as abstracting the provider so "switching is a
one-line config change," and lists OpenAI as an explicit fallback to Vertex AI
using "the same interface." Hand-rolling that abstraction duplicates what
LangChain's `Embeddings` and `BaseChatModel` base classes are built for.

The additional motivation is portfolio positioning: demonstrating LangChain
proficiency deliberately and in the right place, rather than layering it over
parts of the system designed to demonstrate RAG fundamentals from first
principles.

## Decision

Adopt LangChain in exactly two leaf modules, chosen because their input/output
contracts are already provider-agnostic and don't ripple into the rest of the
system — nothing downstream needs to know LangChain is involved.

### `ingestion/embedder.py`

Use LangChain's `Embeddings` interface — `langchain-google-vertexai`'s
`VertexAIEmbeddings` as primary, `langchain-openai`'s `OpenAIEmbeddings` as
fallback (same providers ADR-002 already chose). Output stays `list[float]`,
unchanged — `ChunkCreate.embedding` and everything downstream (chunker, store,
retriever) is unaware LangChain is involved.

```python
from langchain_google_vertexai import VertexAIEmbeddings
from langchain_openai import OpenAIEmbeddings

def get_embedder():
    provider = os.environ.get("EMBEDDING_PROVIDER", "vertexai")
    if provider == "vertexai":
        return VertexAIEmbeddings(model_name="text-embedding-004")
    return OpenAIEmbeddings(model="text-embedding-3-small")

async def embed_chunks(texts: list[str]) -> list[list[float]]:
    return await get_embedder().aembed_documents(texts)
```

Batching and retry-on-rate-limit come from the LangChain client instead of
hand-rolled logic — the concrete productivity gain, on top of the
provider-swap goal.

### `chat/streamer.py`

Use LangChain's `BaseChatModel` interface — `langchain-google-genai`'s
`ChatGoogleGenerativeAI` — to call Gemini Flash and stream tokens into the
existing SSE response. `chat/prompt.py`'s `build_prompt()` (ADR-004) is
untouched: it still returns a plain string. LangChain only wraps the call, not
the prompt construction.

```python
from langchain_google_genai import ChatGoogleGenerativeAI

llm = ChatGoogleGenerativeAI(model="gemini-1.5-flash", temperature=0.2)

async def stream_answer(prompt: str):
    async for chunk in llm.astream(prompt):
        yield f"data: {json.dumps({'token': chunk.content})}\n\n"
    yield "data: [DONE]\n\n"
```

Swapping to a different chat provider later (e.g. `langchain-anthropic`, for
an evaluation comparison) becomes a class swap, not a rewrite of the streaming
loop — directly serving the provider-agnostic goal behind this ADR.

### Explicitly out of scope — still framework-free

- **`ingestion/chunker.py`** — chapter-boundary-aware fixed-size chunking
  (ADR-003) has no provider to abstract. LangChain's text splitters don't know
  about epub chapter structure, so adopting one adds a dependency without
  removing custom code.
- **`shared/retriever.py`** — the stable interface (ADR-001). This module
  isn't a provider-abstraction problem — Firestore isn't swapped via a generic
  interface here, the documented migration path is a deliberate rewrite to a
  new file (`retriever_weaviate.py`). LangChain's vector store abstraction
  also doesn't know about the global catalog / `user_library` dedup design
  (ADR-006); adopting it would mean losing the book-scoped, catalog-aware
  query this project actually needs.
- **`chat/prompt.py`** — the grounded prompt builder (ADR-004) is a plain
  function with no external call; there is no provider to abstract.
- **`mcp/`** — uses the official MCP SDK. A different tool for a different
  job (building a server, not consuming one via an agent framework).

## Alternatives Considered

### Full LangChain adoption across all services
Rejected — reopens every objection ADR-002 raised (obscuring RAG fundamentals
in the parts meant to teach them, more surface area exposed to version churn)
for modules where provider-swapping isn't even the concern.

### Keep the hand-rolled provider abstraction from ADR-002, no LangChain
Rejected now — `embedder.py` and `streamer.py` would end up re-implementing a
subset of what `Embeddings`/`BaseChatModel` already provide (retry, batching,
a consistent async streaming interface) for two modules where doing so buys no
architectural benefit over using the maintained library.

## Consequences

### Positive
- Provider swapping for embeddings and chat becomes a class/config change,
  delivering the provider-agnostic goal ADR-001/002 already stated, now backed
  by a maintained abstraction instead of hand-rolled parity
- Batching/retry logic for embeddings is no longer hand-maintained
- Demonstrates LangChain proficiency in the portfolio, scoped deliberately
  rather than applied uniformly
- The parts of the system that teach RAG fundamentals — chunking, retrieval,
  prompt grounding — stay dependency-free and readable, per the project's
  stated pedagogical goal

### Negative
- Two new dependency groups (`langchain-core` plus the provider packages)
  carry the same version-churn risk ADR-002 flagged. Scoping to two leaf
  modules limits the blast radius of a breaking change to those files.
- `shared/models.py` stays the single schema authority — `ChunkResult`,
  `ChatContext`, etc. remain Pydantic-native, not LangChain's `Document`/message
  types. This means a thin conversion happens at the boundary of
  `embedder.py`/`streamer.py` rather than a free pass-through, which is
  intentional.

### Migration path
If the scope needs to grow later — e.g. `chunker.py` adopting a LangChain text
splitter as a base for the semantic-chunking experiment ADR-003 already defers
to Phase 4 — re-open this ADR rather than assuming the two-module boundary
drawn here is permanent.
