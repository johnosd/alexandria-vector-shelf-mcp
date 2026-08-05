# ADR-008: Dependency Management with uv Workspaces

## Status
Accepted

## Date
2026-08

## Context

`shared/` is imported by `ingestion/`, `chat/`, and `mcp/` — three independently
deployed services (README, ADR-002). The repository structure originally
planned a `requirements.txt` per service. With no shared lockfile, nothing
guarantees the three services pin the same version of `firebase-admin`,
`google-cloud-firestore`, or `pydantic` that `shared/` is built against — a
version drift between, say, the ingestion service's Firestore client and the
chat service's would be a silent, hard-to-diagnose bug, since `shared/models.py`
and `shared/db.py` are exactly the contract every service is supposed to agree
on.

This is worth fixing now, before any service's `requirements.txt` is written
and the drift risk becomes real, rather than after.

## Decision

Manage the repository as a **uv workspace**. `shared/` becomes a real
installable local package; each service depends on it as a workspace member
instead of relying on relative imports and independently-pinned duplicate
requirements.

```
alexandria-vector-shelf-mcp/
├── pyproject.toml        ← workspace root: [tool.uv.workspace] members
├── uv.lock                ← single lockfile, pins every dependency across
│                             every member at one consistent version
├── shared/
│   └── pyproject.toml     ← real package: name="shared", its dependencies
├── ingestion/
│   └── pyproject.toml     ← depends on shared via workspace path reference
├── chat/
│   └── pyproject.toml
└── mcp/
    └── pyproject.toml
```

`shared/pyproject.toml` exists now, since `shared/` already has real code:

```toml
[project]
name = "shared"
version = "0.1.0"
description = "Schemas, Firestore client, and the stable retriever interface."
requires-python = ">=3.11"
dependencies = [
    "pydantic>=2.7",
    "firebase-admin>=6.5",
    "google-cloud-firestore>=2.16",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"
```

`ingestion/`, `chat/`, and `mcp/` are added as workspace members when each
service's code actually lands — each gets its own `pyproject.toml` with
`shared = { workspace = true }` in its dependencies, plus whatever is specific
to that service (FastAPI for ingestion/chat, the `mcp` SDK for `mcp/`,
`rapidfuzz` for ingestion per ADR-006, `langchain-*` for `ingestion/embedder.py`
and `chat/streamer.py` per ADR-007). Declaring them as members before they
have a `pyproject.toml` would make `uv sync` fail against an empty directory,
so the root workspace only lists `shared` for now.

**Docker builds:** each service's `Dockerfile` runs `uv sync --package
ingestion` (or `chat`, `mcp`) against the committed `uv.lock` — every image
gets exactly the locked versions, and a change to `shared/`'s pinned version is
a single line in one lockfile, not three `requirements.txt` edits that can
drift out of sync with each other.

**Local dev:** `make setup` becomes `uv sync` (installs the whole workspace
into one `.venv`); `make lint`/`make test` run through `uv run ruff`/`uv run
pytest` so they use the locked environment rather than whatever's on `PATH`.

## Alternatives Considered

### Keep `requirements.txt` per service, no lockfile
The status quo. **Rejected** — this is the drift risk described in Context; a
plain `requirements.txt` doesn't pin transitive dependencies either, so even
within one service the environment isn't fully reproducible.

### Poetry
Mature, widely used, has workspace-like support via path dependencies.
**Rejected in favor of uv** — uv resolves and installs an order of magnitude
faster (relevant for Cloud Run image builds, not just local dev), and its
workspace model maps directly onto "one lockfile, several deployable
sub-packages" without extra plugins.

### pip-tools (`pip-compile`)
Lighter than Poetry, generates locked `requirements.txt` per input file.
**Rejected** — still one lockfile per service rather than one for the whole
workspace, so it doesn't close the cross-service version-drift gap that
motivated this ADR in the first place.

## Consequences

### Positive
- One `uv.lock` guarantees `shared/`'s dependency versions are identical
  across ingestion, chat, and mcp — the drift risk this ADR exists to close
- Faster installs in CI and Docker builds
- `shared/` becomes a real, testable, independently versioned package instead
  of something reached via relative imports and `PYTHONPATH` assumptions

### Negative
- One more tool to know, for a solo project — mitigated by uv's `pip`-compatible
  CLI surface (`uv pip install` still works) and by how small the actual
  learning curve is for a single-workspace setup like this one
- Docker build steps change slightly (`uv sync --package X` instead of `pip
  install -r requirements.txt`) — a one-time adjustment when each service's
  `Dockerfile` is actually written
