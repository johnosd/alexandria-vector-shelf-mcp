#!/bin/bash
# Hook: warns when code changed but docs didn't keep up.
# Runs on Claude Code's Stop event.
#
# CURRENT MODE: warn only (does not block). Flip BLOCK=0 to BLOCK=1 once the
# doc-driven workflow (docs/plans/) is actually in use for day-to-day work.
BLOCK=0

# `git diff` alone misses untracked (newly created) files, so `git ls-files
# --others` is added to cover those too.
CHANGED=$(
  {
    git diff --name-only HEAD
    git ls-files --others --exclude-standard
  } 2>/dev/null | sort -u
)

CODE_RE='(^|/)(ingestion|chat|mcp|shared)/[^/]+\.py$|(^|/)infra/.*\.tf$'

# No code changed -> nothing to check.
if ! echo "$CHANGED" | grep -qE "$CODE_RE"; then
  exit 0
fi

MISSING=""

if ! echo "$CHANGED" | grep -qE 'docs/plans/.*-plan\.md$'; then
  MISSING="$MISSING\n- No docs/plans/<slug>-plan.md was updated. Check off completed steps and the phase register."
fi

# CHANGELOG check only for broad changes (3+ code files) — early-stage repo,
# small single-file changes don't need a changelog entry yet.
CHANGED_COUNT=$(echo "$CHANGED" | grep -cE "$CODE_RE")
if [ "$CHANGED_COUNT" -gt 2 ]; then
  if ! echo "$CHANGED" | grep -q 'docs/CHANGELOG.md'; then
    MISSING="$MISSING\n- docs/CHANGELOG.md not updated. Add an entry under [Unreleased]."
  fi
fi

if [ -n "$MISSING" ]; then
  echo -e "Code changed but docs fell behind:$MISSING" >&2
  if [ "$BLOCK" = "1" ]; then
    exit 2
  fi
fi

exit 0
