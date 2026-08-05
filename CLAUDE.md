# CLAUDE.md

This file provides guidance to Claude Code when working in this repository.

## Project

- Name: alexandria-vector-shelf-mcp
- Stack: Python 3.11, `uv` workspace (ADR-008), FastAPI services, Firebase/Firestore, LangChain
  (scoped — ADR-007), Pydantic AI (scoped — ADR-009)
- Layout: `ingestion/` (epub → chunks → embeddings), `chat/` (streaming RAG chat API), `mcp/`
  (Model Context Protocol server, Phase 5), `shared/` (retriever, embedder, models — used by all
  three), `infra/` (Terraform)
- Full architecture diagram and stage breakdown: [`README.md`](README.md)

## Purpose of this repository

This is a **learning project**. The user is a data engineer with production experience who is
using this repo to build hands-on skill in RAG systems, vector search, and agentic integration —
not to ship as fast as possible with an autonomous agent. When implementing, act as a tutor, not
an autopilot: default to explaining the *why* behind a choice, and check with the user how
hands-on they want to be for a given piece of work (see "Tutor mode" below) instead of assuming.

## Commands

```bash
make setup             # uv sync + copy .env
make dev                # all services via docker-compose
make dev-ingestion      # ingestion service only
make dev-chat           # chat service only
make test               # full pytest suite
make test-unit          # -m "unit" (no external dependencies)
make test-integration   # -m "integration" (requires live Firebase)
make lint                # ruff check ingestion/ chat/ shared/ mcp/ tests/
make format              # ruff format (same paths)
uv run mypy shared/ ingestion/ chat/ mcp/    # type check (not yet wired into Makefile)
make index                # create the Firestore vector composite index (gcloud)
```

No build step beyond `uv sync`. Services run via `docker-compose` (see `make dev`).

## Code Conventions

- Runtime-validated boundaries: `shared/models.py`'s Pydantic models are the schema contract
  between services and Firestore. Don't pass raw dicts across a service boundary — validate
  through a model.
- `ruff` (`select = ["E", "F", "I", "UP"]`) and `mypy` are configured in `pyproject.toml` — run
  both before considering a change done, not just at ship time.
- LangChain is scoped to `ingestion/embedder.py` and `chat/streamer.py` only (ADR-007). Pydantic
  AI is scoped to the evaluation notebook and the metadata-extraction fallback only (ADR-009).
  Don't reach for either outside those scopes without registering the expansion as a decision
  (see ADRs below) — this project deliberately avoids letting one library's surface creep in to
  do a second library's job.
- Tests are marked `unit` (no external deps) or `integration` (needs live Firebase) —
  `pyproject.toml`'s `[tool.pytest.ini_options]` defines the markers. New tests need one of the
  two markers or `make test-unit`/`make test-integration` will silently skip them.

## Documentation System

Documentation is not a separate step — it's how work gets planned, resumed across sessions, and
verified as actually done. This section is the single source of truth for the process; there is
no separate guide file to keep in sync with it.

### Structure

```
alexandria-vector-shelf-mcp/
├── CLAUDE.md                 # this file — constitution + doc-system rules
├── README.md                 # what the project is (public-facing)
├── docs/
│   ├── CHANGELOG.md          # what changed, by version
│   ├── backlog.md            # pending work, ideas, tech debt
│   ├── adr/                  # ADR-NNN-<slug>.md — architectural decisions (write-once)
│   ├── plans/                # <slug>-plan.md — one file per feature, full lifecycle
│   ├── DEVELOPMENT.md        # MCP-server tooling recommendations for this repo
│   ├── schema.md, BIBLIOGRAPHY.md, GCP_vs_AWS.md, training/   # reference material, not lifecycle docs
└── .claude/
    ├── settings.json          # registers the Stop hook
    ├── hooks/check-docs.sh    # warns when code changed but the plan didn't
    └── skills/
        ├── plan-feature/SKILL.md   # idea → plan, phases, or continuing an existing plan
        └── ship-feature/SKILL.md   # verification + closing a feature
```

Two things that differ from a generic template, so nothing gets duplicated by accident:

- **No `docs/specs/` folder.** Feature definition and implementation planning live in the *same*
  file (`docs/plans/<slug>-plan.md`) — they used to be split into a spec + a plan in an earlier
  version of this process, and the two competed for the same information. `plan-feature` now
  owns the whole lifecycle from a vague idea to a shipped feature.
- **ADRs already existed in this repo** (`docs/adr/ADR-NNN-<slug>.md`) before this process was
  adopted — keep using that folder and numbering, don't introduce a second `decisions/` folder.

### Feature lifecycle

1. **Plan** (`plan-feature`): takes a vague idea, a clear feature name, or an existing plan to
   continue. If the idea is vague, it asks up to 3 clarifying questions first. Creates or updates
   `docs/plans/<slug>-plan.md` — Objective/Scope/Acceptance Criteria section first, phases added
   once the shape of the feature is clear. Status starts at `draft`, moves to `planned` once
   phases exist.
2. **Implement**: phase by phase. Checklist items get checked off as they're done, each phase's
   verification is run (see "Verification philosophy" below) and recorded, the phase register is
   filled in. Status moves to `in-progress` on the first phase started.
3. **Ship** (`ship-feature`): verifies every phase is actually done (code + tests + docs, not
   just code), updates `docs/CHANGELOG.md`, closes out `docs/backlog.md`, promotes any
   cross-feature decision to an ADR, and closes the plan. Status moves to `done`.

Status vocabulary (exact, used by both skills): `draft` → `planned` → `in-progress` → `done`.

### Verification philosophy

This project has a real test suite (`pytest`, unit + integration markers) and static checks
(`ruff`, `mypy`) — unlike a scraping project with no test runner, most claims here should be
backed by an automated check, not a manual walkthrough.

- **Default verification for a phase**: unit tests for new logic, integration tests when a phase
  touches Firestore/Storage/an external API, `ruff check` and `mypy` clean.
- **Manual verification is reserved for what code genuinely can't check**: does an MCP tool call
  behave correctly from an actual MCP client (Claude Desktop/Cursor), does a chat answer read as
  good/relevant, does an ingested epub's chunking look sane on a real book. Don't write a manual
  checklist item for something a unit test could cover instead.
- A phase is not `Concluded` on code changes alone — it needs its verification (automated,
  manual, or both) actually run and recorded, same as before.

### Tutor mode

This isn't a fixed setting — the user's comfort level varies by topic and by phase, not globally.
At the start of implementing a phase (or when it's genuinely ambiguous), ask how hands-on to be:

- **Solo**: the user writes the code; Claude reviews and explains tradeoffs, doesn't edit.
- **Guided**: Claude proposes the approach and writes it, pausing at real decision points to
  explain the *why* before continuing.
- **Pair**: mixed — Claude scaffolds (config, test harness, glue code), the user writes the core
  logic of the phase.

Record which mode was used in the phase's register (one line is enough) — it's useful context for
resuming the plan later, not a process to enforce.

### What keeps docs from going stale (not you)

| Mechanism | What it guarantees |
|---|---|
| `[ ]` checklist per phase | Checked off as work completes, not batched at the end |
| Phase register | Status, what was done, verification results, per phase |
| `ship-feature` | CHANGELOG, backlog, ADR promotion, plan closure — one command |
| `check-docs.sh` (Stop hook, warn mode) | Flags when `ingestion/`, `chat/`, `mcp/`, `shared/`, or `infra/*.tf` changed without a plan update |
| ADRs (write-once) | A decision never goes stale — a changed decision gets a new ADR that supersedes it |
| README/CLAUDE.md updates | An explicit checklist item in a feature's last phase whenever the feature changes user-facing behavior, commands, or architecture — not automatic, because only the phase doing the work has the context to write it accurately |

### Resuming work in a new session

1. Read the active plan in `docs/plans/`.
2. Read its "Continuity for Next Sessions" section.
3. Read the files it points to.
4. Continue from the indicated phase/step. Don't repeat work already checked off.

### Required reading by context

- Before implementing: the plan for the feature (and any ADR it references).
- Before deciding architecture: `docs/adr/` headers, for decisions that already constrain this one.
- Before planning: `docs/backlog.md`, to avoid re-proposing something already tracked.
