---
name: ship-feature
description: "Use when a feature implementation is complete or when the user says things like 'terminei', 'ta pronto', 'pode fechar', 'finaliza essa feature', 'ship it'. Verifies completeness (tests, lint, docs) and closes the feature lifecycle: CHANGELOG, backlog, ADR promotion, plan closure. Also invoke when the last phase of a plan-feature plan is marked Concluded."
---

# Ship Feature

## Objective

Close the feature lifecycle by verifying it's actually done and updating every doc that needs to
reflect the change — the enforcement point that keeps docs from drifting from the code.

## Required Input

Accepted forms:

- A feature name.
- A plan file path (`docs/plans/<slug>-plan.md`).
- Context from the current session where a phase was just finished.

If ambiguous, list plans in `docs/plans/` with `Status: in-progress` and ask which one.

## Verification Checklist

Do not skip a check — if something can't be verified, record why instead of skipping silently.

### 1. Plan Completeness

- Read the plan in `docs/plans/`.
- Every phase has Status `Concluded`, or a recorded justification for `Partial`/`Blocked`.
- The Implementation Diary has an entry per completed phase.
- Flag any `Partial`/`Blocked` phase to the user before proceeding — don't ship around it silently.

### 2. Acceptance Criteria

- Walk through each `## Acceptance Criteria` checkbox in the plan.
- Check the ones actually met (backed by a verification already recorded, not just "looks right").
- Leave unmet ones unchecked and tell the user — offer to move them to `docs/backlog.md`.

### 3. Automated Verification

This project has a real test suite and static checks — lean on them, don't re-derive a manual
walkthrough that a command already covers:

```bash
make test        # or make test-unit if no live Firebase available right now
make lint
uv run mypy shared/ ingestion/ chat/ mcp/
```

- Confirm these pass now, not just that they passed once mid-implementation — code can drift
  between phases.
- Cross-check against each phase's recorded verification in the plan; don't just trust "Concluded".
- For anything the plan flagged as manual-only (can't be a test), confirm it was actually run and
  recorded — or ask the user to confirm now.

### 4. Documentation Currency

- If the plan's "Overall Verification" says README.md/CLAUDE.md needed updating, confirm those
  edits are actually in the diff — this skill does not write them (it lacks the feature-specific
  context the implementing phase had); it only verifies they were done. If they're missing, ask
  the user or go back and do it before shipping, don't ship with stale docs.

## Doc Updates (this skill performs these)

After verification passes, in order:

### Update 1: Plan Status

In `docs/plans/<slug>-plan.md`:
- `## Status: in-progress` → `## Status: done`.

### Update 2: docs/CHANGELOG.md

Add an entry under `## [Unreleased]`, Keep a Changelog categories (`Added`/`Changed`/`Fixed`/
`Removed`), 1-3 lines:

```md
### Added
- <one-line description of the feature>.
```

### Update 3: docs/backlog.md

- If the shipped feature was listed under "In Progress" or "Next", move it to "Done" with a
  one-line summary and a link to its plan.
- If implementation surfaced new follow-up work, add it under "Ideas" with enough context to
  resume without re-deriving the reasoning (mirror the existing entries' format).

### Update 4: ADR for Cross-Feature Decisions

Check the plan's `Risks and Decisions` table. For any decision that matters beyond this one
feature (not a local implementation detail):

- Find the next number by checking existing files in `docs/adr/` (currently up to `ADR-009`).
- Create `docs/adr/ADR-NNN-<slug>.md`:

```md
# ADR-NNN: <Decision Title>

## Status
Accepted

## Date
<YYYY-MM>

## Context
- What problem or trade-off motivated this.

## Decision
- What was decided.

## Alternatives Considered
- Option A: description. Rejected because...
- Option B: description. Rejected because...

## Consequences
- What changes in the project because of this.
- Trade-offs accepted.
```

- Skip if nothing in this feature was architecturally significant or cross-cutting — most
  features won't need one. Never create an ADR for a library version bump or a naming choice.

### Update 5: Plan Closure

In the plan file's `Continuity for Next Sessions`:

```md
- Last phase completed: All.
- Status: Feature shipped.
- Completion date: <YYYY-MM-DD>.
```

Add a final row to the Implementation Diary.

## Final Response

```text
Feature "<name>" shipped.

Docs updated:
- docs/plans/<slug>-plan.md → done
- docs/CHANGELOG.md → entry added
- docs/backlog.md → moved to Done
- docs/adr/ADR-NNN-<slug>.md → created (if applicable)

README/CLAUDE.md: <updated in this feature | confirmed no update needed>

Open items: <list, or "none">.
```

## Rules

- Don't skip doc updates — closing the loop is the entire point of this skill.
- Don't create ADRs for trivial decisions.
- If the user says "ship it" but verification fails (tests red, lint dirty, acceptance criteria
  unmet), show exactly what failed and ask how to proceed — don't ship around a failure.
- Never check an acceptance criterion or mark a phase Concluded without an actual verification
  result (test output, explicit manual check, or direct user confirmation) backing it.
