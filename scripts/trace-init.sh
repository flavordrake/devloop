#!/usr/bin/env bash
# scripts/trace-init.sh — Start a TRACE for the current project (opt-in).
#
# Usage (from anywhere inside the project):
#   scripts/trace-init.sh [--force] <objective-slug>
#
# Creates <project>/.traces/trace-<slug>-<timestamp>/ with the agent-trace
# skill's layout, and records it as the "Active TRACE" line in the project's
# CLAUDE.md, which is what scripts/lib/trace-locate.sh reads. An existing
# Active TRACE line is kept and the init refused (a consumer may hand-maintain
# a multi-arc line); --force replaces it.

set -euo pipefail

FORCE=0
SLUG=""
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    *) SLUG="$arg" ;;
  esac
done
if [ -z "$SLUG" ]; then
  echo "Usage: scripts/trace-init.sh [--force] <objective-slug>" >&2
  exit 1
fi

source "$(dirname "$0")/lib/trace-locate.sh"

CLAUDE_MD=$(find_claude_md)
if [ -z "$CLAUDE_MD" ]; then
  CLAUDE_MD="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/CLAUDE.md"
fi
REPO_ROOT=$(dirname "$CLAUDE_MD")

if [ "$FORCE" -ne 1 ] && has_active_trace_line "$CLAUDE_MD"; then
  echo "Refusing: $CLAUDE_MD already has an Active TRACE line ($(first_trace_ref "$CLAUDE_MD")). Close it or rerun with --force." >&2
  exit 1
fi

TRACE_REL=".traces/trace-${SLUG}-$(date +%Y%m%dT%H%M%S)/"
TRACE_DIR="$REPO_ROOT/$TRACE_REL"
mkdir -p "$TRACE_DIR"/{specs,strategy,logs,telemetry,artifacts}

BRANCH=$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || echo unknown)
GIT_HASH=$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)

cat > "$TRACE_DIR/TRACE.md" <<EOF
---
id: trace-${SLUG}
objective: "${SLUG}"
status: in-progress
skills-used: []
branch: ${BRANCH}
git-hash: ${GIT_HASH}
created: $(date +%Y-%m-%dT%H:%M:%S%z)
resources:
  tokens: 0
  compute_footprint:
    cpu_time: "00m:00s"
    gpu_time: "00m:00s"
metrics:
  target: ""
  achieved: ""
---

# TRACE: ${SLUG}

## The "Why"
<!-- Post-mortem: why did the final strategy succeed or fail? -->

## The "Ambiguity Gap"
<!-- How were specs clarified during execution? What was assumed vs stated? -->

## The "Knowledge Seed"
<!-- One-sentence heuristic for future agents -->

## Performance Delta
<!-- One-line: before/after impact. Reference telemetry/ -->

## Security Summary
<!-- One-line: static analysis findings on changed files -->

## Outcome Classification
<!-- success | success-with-caveats | partial | failure-informative | failure -->
EOF

cat > "$TRACE_DIR/strategy/initial_plan.md" <<EOF
# Initial Strategy

Objective: ${SLUG}
Approach: as described in the issue

## Assumptions that might be wrong
<!-- List only non-obvious assumptions -->
EOF

# Record in CLAUDE.md: drop any previous Active TRACE line (--force), append the new one.
# Temp file + mv instead of `sed -i`, whose syntax differs between GNU and BSD.
ACTIVE_LINE="> **Active TRACE**: \`${TRACE_REL}\`"
if [ -f "$CLAUDE_MD" ]; then
  TMP=$(mktemp)
  grep -v '^> \*\*Active TRACE\*\*' "$CLAUDE_MD" > "$TMP" || true  # grep -v exits 1 when every line is dropped
  echo "$ACTIVE_LINE" >> "$TMP"
  mv "$TMP" "$CLAUDE_MD"
else
  echo "$ACTIVE_LINE" > "$CLAUDE_MD"
fi

echo "TRACE initialized: $TRACE_REL"
echo "Recorded in $CLAUDE_MD. Edit strategy/initial_plan.md before starting work."
