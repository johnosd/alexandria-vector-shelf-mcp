# ADR-010: External Dependency Policy — GCP-First, Not GCP-Only

## Status
Accepted

## Date
2026-08-06

## Context

ADR-002 set a strategic constraint: "everything must run within the Google Cloud /
Firebase ecosystem... No external services." In practice this has never been a
blanket rule — ADR-002 itself lists OpenAI as an accepted embeddings fallback, and
ADR-009 adopted Pydantic AI (not a GCP product) for structured LLM output. Both were
justified case-by-case, but ADR-002's wording still reads as an absolute ban, which
means every real exception has to either violate the letter of the ADR or get
awkwardly justified as if it weren't external at all.

The concrete case that surfaced this gap: book metadata enrichment. ADR-006's Tier 1
dedup relies on ISBN from epub OPF metadata; ADR-009 added an LLM extraction fallback
for when OPF is missing or unusable. Neither uses an actual book catalog to validate
or enrich what's found — a real lookup (Google Books, with Open Library as a
no-key fallback) is more accurate than fuzzy-matching alone and cheaper than an LLM
call, but Open Library is not a Google product, so it would fail a literal reading of
ADR-002.

Rather than stretch ADR-002's wording again, this ADR replaces the blanket rule with
an explicit policy that matches what the project has actually been doing.

## Decision

**GCP-first, not GCP-only.** The default is still to prefer a Google Cloud/Firebase-
native service — that default doesn't change. A non-GCP dependency is acceptable
when it clears three bars:

1. **Real gain, not marginal.** It must close an actual capability or quality gap
   that no GCP-native option covers as well — e.g., a canonical book catalog lookup
   vs. fuzzy title/author matching — not "a bit cheaper" or "slightly nicer API."
2. **Written down at adoption time.** The gain and the alternative considered get
   recorded in an ADR (or an update note on an existing one), the same as any other
   architectural decision — not added silently as a stray `pip install`.
3. **Ordered by cost/reliability when multiple externals compete for the same job.**
   Prefer free/no-key options as a fallback tier rather than a second paid dependency,
   unless the paid option is the one actually needed for the primary path.

This keeps ADR-002's original intent — one deliberate stack, not organic sprawl —
while dropping the fiction that the project has ever been 100% dependency-pure.

### Recorded precedent under this policy

**Google Books API (primary) + Open Library API (fallback)** for book metadata
enrichment in `ingestion/library_manager.py`. Complements, doesn't replace, ADR-006's
Tier 1/3 signals and ADR-009's LLM extraction fallback — same trigger condition
(OPF metadata missing or unusable). Both are free/no-key, so this doesn't add billing
surface, only a new outbound call. Sequencing (query catalog before or after the LLM
fallback, how a match feeds back into `normalized_title`/`normalized_author`) is left
to the implementation plan, not fixed here.

## Alternatives Considered

### Keep ADR-002's rule literal, treat every exception as a special case
Status quo. **Rejected** — already false in practice (OpenAI, Pydantic AI), and
forces future exceptions through the same awkward "is this really external"
argument instead of a clear test.

### Drop the GCP-first default entirely, evaluate every dependency purely on merit
**Rejected** — the single-account/single-bill simplicity ADR-002 optimized for is
still a real, valuable constraint for a single-user portfolio project. This ADR
narrows the rule, it doesn't remove it.

## Consequences

### Positive
- Matches actual project history instead of contradicting it
- Gives a concrete three-part test for the next external-dependency question,
  instead of relitigating "does this violate ADR-002" each time
- Google Books/Open Library metadata enrichment can proceed without stretching
  ADR-002's wording

### Negative
- Slightly weakens the single-vendor simplicity that was ADR-002's original
  selling point — mitigated by the "real gain, written down" bar, which keeps
  additions deliberate rather than incremental drift

### Future evolution
- If external dependencies accumulate to the point where vendor sprawl itself
  becomes a maintenance cost, revisit with a new ADR — this one assumes exceptions
  stay occasional, not the norm.
