# Development Environment — AI-Assisted Tooling

Recommended MCP server setup for working on this repo with Claude Code. This is
guidance, not an architectural decision about the running system — it doesn't
warrant an ADR, but it's worth keeping documented and current since it directly
affects how efficiently (and how cheaply, in context terms) this repo gets
worked on.

## Principle: only add a server if it gives capability Claude Code doesn't already have

Claude Code already has direct Bash access (so `gcloud ...`, `terraform
plan/apply`, `gh pr ...` all work without an MCP server), plus native
Read/Write/Edit/Glob/Grep for the filesystem. An MCP server that duplicates one
of these just adds tool-schema weight to every session's context for zero new
capability. Reference servers for filesystem, GitHub, gcloud, and Cloud Run
were evaluated and skipped for exactly this reason — Bash and the built-in
file tools already cover them, better.

## Recommended servers

| Server | Scope | Why | Install |
|---|---|---|---|
| **Firebase MCP** | `project` | Only way to inspect live Firestore/Auth/Storage data (`books`, `chunks`, `user_library`) without scripting it by hand. Alexandria-specific — not useful outside this repo. Heaviest of the three (30+ tools) — worth enabling only for sessions actually touching catalog/library data, not leaving on by default if that ever becomes a concern. | `claude mcp add --scope project firebase -- npx -y firebase-tools@latest experimental:mcp` |
| **Terraform MCP** | `project` | Live Terraform Registry lookups (provider schemas, module docs) for `infra/*.tf` — more precise than a generic web search for provider syntax. Requires Docker running (already a project dependency). | `claude mcp add --scope project terraform -- docker run -i --rm hashicorp/terraform-mcp-server:latest` |
| **Context7** | `user` | Version-pinned documentation for any library, fetched live instead of relying on training data — most valuable for the fast-moving dependencies this project adopted recently (LangChain, Pydantic AI, uv, MCP SDK). Small tool surface (2 tools), cheap to keep always on. Not project-specific, hence user scope. | `claude mcp add --scope user context7 -- npx -y @upstash/context7-mcp` (optional `--api-key` from context7.com/dashboard for higher rate limits) |

**Explicitly skipped** (redundant with Claude Code's built-in tools): Filesystem
and GitHub reference servers (Bash + `gh` already cover this), gcloud MCP and
Cloud Run MCP (Bash already runs `gcloud`/`gcloud run deploy` directly),
Sequential Thinking (redundant with the model's own reasoning). The Firestore
remote MCP server (Google's native alternative to Firebase MCP) was also
skipped — same capability as Firebase MCP but narrower (no Auth/Storage), so
there's no reason to run both.

## Where the config lives

- `firebase` and `terraform` are `--scope project`, written to `.mcp.json` at
  the repo root — committed to git, so anyone opening this repo with Claude
  Code gets the same two servers automatically.
- `context7` is `--scope user`, written to `~/.claude/settings.json` — not
  part of this repo, available in every project on this machine.

Verify what's active with `claude mcp list`.
