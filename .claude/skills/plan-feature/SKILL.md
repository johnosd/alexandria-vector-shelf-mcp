---
name: plan-feature
description: "Use when the user has an idea, a problem statement, or a feature to build for this RAG/MCP project — vague or already clear — and wants it turned into a documented plan in docs/plans/<slug>-plan.md, broken into phases with checklists. Also use to continue an existing plan: implementing the next phase, or updating phase progress after work was done. Do not use for a tiny one-line fix unless the user explicitly wants it tracked as a phased plan."
---

# Plan Feature

## Objective

Own the full feature lifecycle in a single file: `docs/plans/<slug>-plan.md` goes from a raw idea
to a phased implementation plan to a record of what was actually done, without a separate spec
file. There is no `define-feature`/`plan-feature` split in this project — an earlier version of
this process split them, and the two files competed for the same information (acceptance criteria
vs. scope, both trying to define the feature). One file, one lifecycle.

This project is a **learning project** — see CLAUDE.md's "Purpose of this repository" and "Tutor
mode" sections. Act as a tutor: explain tradeoffs, and check how hands-on the user wants to be for
each phase instead of assuming you should just implement it.

## Required Input

Accepted forms, in order of how much work they save:

- A clear feature name or description: "expose search_book as an MCP tool".
- A problem statement or wish: "quero conseguir perguntar sobre um livro específico via Claude Desktop".
- A reference to an existing plan in `docs/plans/` to continue.
- A backlog item: "aquele item do backlog sobre retry na ingestão".

If the request is completely empty ("planeja uma feature" with nothing else), ask one question:

```text
Qual feature você quer planejar?
```

## First Reads

Before writing or updating anything:

- `CLAUDE.md` — conventions, architecture summary, doc-system rules.
- `docs/backlog.md` — the idea may already be tracked, with context.
- `docs/adr/` headers — past architectural decisions that constrain this one (LangChain/Pydantic
  AI scoping in ADR-007/009, dedup tiers in ADR-006, chunk strategy in ADR-003, etc.).
- Existing plans in `docs/plans/` — avoid a duplicate file for the same feature.
- The source this feature actually touches (`ingestion/`, `chat/`, `mcp/`, `shared/`), preferring
  current code over a stale doc when they disagree.

## Step 1 — Clarify if vague

If the request is a raw idea or problem statement rather than a clear, scoped ask, ask **at most
3** targeted questions before writing anything. Good questions here look like:

- "Isso é ingestão, chat, ou o servidor MCP (ou mais de um)?"
- "Isso muda o schema de algum model em `shared/models.py`, ou só adiciona comportamento?"
- "Precisa de Firebase real pra verificar, ou dá pra testar com unit tests + mocks?"

Skip questions whose answer is obvious from context or from files already read. If the request is
already clear and scoped, skip this step entirely — don't manufacture questions for their own sake.

## Step 2 — Write or update the plan

Save as `docs/plans/<feature-slug>-plan.md`, lowercase-hyphen-case. If a related plan already
exists for this feature, update it — never create a duplicate.

### Required structure

```md
# <Feature Name>

## Status: draft

## Problem
- What pain or need motivates this.

## Proposal
- What the feature does, 2-3 sentences.

## Acceptance Criteria
- [ ] Verifiable criterion 1.
- [ ] Verifiable criterion 2.

## Out of Scope
- What this explicitly does NOT do.

## Notes
- Constraints, dependencies, loose ideas that came up.

---

## Technical Context
- Components affected: ingestion / chat / mcp / shared (state all that apply — a change to
  `shared/` usually touches more than one).
- Files and functions relevant.
- Impact on `shared/models.py` schemas, Firestore collections, or the exported MCP tool/resource
  surface.
- Dependencies and prior decisions (link `docs/adr/ADR-NNN-*.md`).

## Risks and Decisions
| ID | Risk/Decision | Impact | Mitigation |
| --- | --- | --- | --- |

## Implementation Phases

### Phase 1 - <name>
Objective: <what this phase achieves>.
Mode: <solo / guided / pair — set when the phase starts, see CLAUDE.md "Tutor mode">.

Checklist:
- [ ] Actionable item.

Verification:
- [ ] `uv run pytest tests/ -m unit` covering <what>, or `-m integration` if it needs live Firebase.
- [ ] `make lint` / `mypy` clean.
- [ ] Manual step, only if genuinely not coverable by a test (e.g. "call the MCP tool from Claude
      Desktop and confirm the response shape").

Completion criteria:
- Objective condition for calling this phase done.

Phase register:
- Status: Pending.
- Done:
- Verification run:
- Open issues:

### Phase 2 - <name>
(same structure)

## Overall Verification
- [ ] `make test` passes.
- [ ] `make lint` clean.
- [ ] Affected components manually exercised where a test genuinely can't cover it.
- [ ] README.md / CLAUDE.md updated if this feature changes user-facing behavior, commands, or
      architecture (state explicitly if nothing needed updating, don't just omit the line).

## Implementation Diary
| Date | Phase | What was done | Verification | Open issues |
| --- | --- | --- | --- | --- |

## Continuity for Next Sessions
- Last phase completed:
- Next recommended phase:
- Key files to read:
- How to verify:
- Pending decisions or things to watch:
```

Status vocabulary (exact): `draft` → `planned` → `in-progress` → `done`.

- Writing the **Problem/Proposal/Acceptance Criteria** section alone (no phases yet) is a valid
  stopping point — leave Status at `draft` and tell the user the phases aren't written yet if
  they only wanted the feature defined.
- Once phases exist, set Status to `planned`.
- When implementation of phase 1 actually begins, set Status to `in-progress`.
- Closing (`done`) belongs to `ship-feature`. Never set it here.

## How Verification Works Here

Default to automated checks — this project has a real `pytest` suite (`unit`/`integration`
markers) and `ruff`/`mypy`. Write phase verification as concrete commands, not "test it":

- New pure logic (parsing, chunking, model validation) → unit test, `make test-unit`.
- Anything touching Firestore/Storage/an external API → integration test, `make test-integration`,
  or explicitly note why it's mocked instead.
- Static checks: `make lint`, `uv run mypy ...`.
- Manual verification only for what a test can't meaningfully assert: does an MCP tool behave
  right from an actual client, does a retrieved chunk read as relevant, does chunking on a real
  epub look sane. If you're about to write a manual checklist item, first ask whether a test could
  cover it instead.

## Updating During Implementation

1. Read the plan first, then the current source for that phase.
2. Ask (if not already set for this phase) how hands-on the user wants to be — solo / guided /
   pair. Record it in the phase's `Mode:` line.
3. Set Status to `in-progress` if this is the first phase being implemented.
4. Do the work at the agreed mode.
5. Run the phase's verification commands, or record exactly why one couldn't run.
6. Update the phase register: Status (`Concluded`, `Partial`, `Blocked`), what was done,
   verification results, open issues.
7. Add one row to the Implementation Diary.
8. Update "Continuity for Next Sessions".
9. Leave a checklist item unchecked if it isn't actually done — don't mark ahead of the work.

Work found mid-implementation that wasn't planned: add new `- [ ]` items to the current phase, or
a sub-phase (e.g. "Phase 2.5") if the scope justifies it. Architectural decisions taken while
implementing go in the `Risks and Decisions` table; `ship-feature` promotes cross-feature ones to
an ADR.

Do not mark a phase complete on code changes alone — it needs verification run and recorded, or an
explicit reason it couldn't be.

## Final Response

After creating or updating the plan, summarize:

- Plan path.
- Current status.
- Number of phases and the next recommended one (or note that only the definition was written).
- Any source inspection performed.

Don't paste the full plan in chat unless asked.
