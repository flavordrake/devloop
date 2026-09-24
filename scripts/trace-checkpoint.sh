#!/usr/bin/env bash
# scripts/trace-checkpoint.sh — Emit TRACE one-line status and prompt update
#
# General-purpose trace checkpoint. Call from:
#   - Hooks (PostToolUse, PreCompact, SessionStart)
#   - Agent prompts (before/after key decisions)
#   - Manual invocation (scripts/trace-checkpoint.sh [trigger-label])
#
# Usage:
#   scripts/trace-checkpoint.sh                  # auto-detect from CWD
#   scripts/trace-checkpoint.sh commit           # label the checkpoint
#   scripts/trace-checkpoint.sh deploy           # label the checkpoint
#   scripts/trace-checkpoint.sh "design decision" # any label
#
# Output: one-line TRACE status to stdout. If TRACE is stale or behind,
# the message is phrased as a prompt to update.

set -euo pipefail

TRIGGER="${1:-checkpoint}"

# grep -c prints 0 AND exits 1 on no match, so `|| echo 0` doubled the output ("0\n0").
# Grep exception from rules/command-hygiene.md.
count_matches() { grep -c -- "$1" "$2" 2>/dev/null || true; }
first_trace_ref() { grep -m1 -oP '\.traces/trace-[^\s`/]+/' "$1" 2>/dev/null || true; }

# Find CLAUDE.md: $CLAUDE_PROJECT_DIR, else nearest ancestor of cwd.
# Never glob into child/sibling dirs — that reported unrelated repos' traces.
find_claude_md() {
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$CLAUDE_PROJECT_DIR/CLAUDE.md" ]; then
    echo "$CLAUDE_PROJECT_DIR/CLAUDE.md"
    return
  fi
  local dir
  dir=$(pwd)
  while [ ! -f "$dir/CLAUDE.md" ]; do
    if [ "$dir" = "/" ]; then
      return
    fi
    dir=$(dirname "$dir")
  done
  echo "$dir/CLAUDE.md"
}

CLAUDE_MD=$(find_claude_md)

if [ -z "$CLAUDE_MD" ]; then
  echo "TRACE: no CLAUDE.md found — no active trace"
  exit 0
fi

REPO_ROOT=$(dirname "$CLAUDE_MD")
TRACE_REL=$(first_trace_ref "$CLAUDE_MD")

if [ -z "$TRACE_REL" ]; then
  echo "TRACE: no active trace in CLAUDE.md — init with scripts/trace-init.sh"
  exit 0
fi

TRACE_PATH="$REPO_ROOT/$TRACE_REL"

if [ ! -d "$TRACE_PATH" ]; then
  echo "TRACE: directory $TRACE_REL not found — init with scripts/trace-init.sh"
  exit 0
fi

# Gather metrics
TRACE_MD="$TRACE_PATH/TRACE.md"
TRACE_AGE_MIN=0
COMMIT_COUNT=0
AGENT_COUNT=0
STATUS="unknown"

if [ -f "$TRACE_MD" ]; then
  TRACE_MTIME=$(stat -c %Y "$TRACE_MD" 2>/dev/null || echo 0)
  TRACE_AGE=$(( $(date +%s) - TRACE_MTIME ))
  TRACE_AGE_MIN=$(( TRACE_AGE / 60 ))

  ISO_SINCE=$(date -d "@$TRACE_MTIME" --iso-8601=seconds 2>/dev/null || echo '1 hour ago')
  # Process substitution: a non-repo git failure must not trip pipefail/set -e.
  COMMIT_COUNT=$(count_matches . <(git -C "$REPO_ROOT" log --oneline --since="$ISO_SINCE" 2>/dev/null))

  if grep -q "<!-- Post-mortem" "$TRACE_MD" 2>/dev/null; then
    STATUS="BOILERPLATE"
  elif grep -qP '^status:\s+(success|failed)' "$TRACE_MD" 2>/dev/null; then
    STATUS="CLOSED"
  elif [ "$TRACE_AGE_MIN" -gt 60 ]; then
    STATUS="STALE"
  else
    STATUS="current"
  fi
else
  STATUS="MISSING"
fi

AGENT_LOG="$TRACE_PATH/logs/agents.log"
if [ -f "$AGENT_LOG" ]; then
  AGENT_COUNT=$(count_matches "agent-spawn" "$AGENT_LOG")
fi

# Count decisions: pivots + gh-ops entries
DECISION_COUNT=0
# nullglob array instead of `ls | wc -l`, which had the same doubled-0 shape with no pivots.
shopt -s nullglob
PIVOTS=("$TRACE_PATH"/strategy/pivot_*.md)
shopt -u nullglob
PIVOT_COUNT=${#PIVOTS[@]}
GH_OPS_LOG="$TRACE_PATH/logs/gh-ops.log"
GH_OPS_COUNT=0
if [ -f "$GH_OPS_LOG" ]; then
  GH_OPS_COUNT=$(count_matches "^\[" "$GH_OPS_LOG")
fi
DECISION_COUNT=$((PIVOT_COUNT + GH_OPS_COUNT + COMMIT_COUNT))

# Build one-liner with escalating severity
# Level 0: quiet status (no action needed)
# Level 1: drift warning (update soon)
# Level 2: stale (must update before proceeding)
LEVEL=0
if [ "$STATUS" = "STALE" ] || [ "$STATUS" = "BOILERPLATE" ] || [ "$STATUS" = "CLOSED" ] || [ "$STATUS" = "MISSING" ]; then
  LEVEL=2
elif [ "$COMMIT_COUNT" -gt 5 ]; then
  LEVEL=2
elif [ "$COMMIT_COUNT" -gt 2 ] && [ "$TRACE_AGE_MIN" -gt 30 ]; then
  LEVEL=1
fi

case "$LEVEL" in
  0)
    echo "TRACE ($TRIGGER): ${DECISION_COUNT} decisions, ${COMMIT_COUNT} commits, ${AGENT_COUNT} agents since last update ${TRACE_AGE_MIN}m ago"
    ;;
  1)
    echo "TRACE ($TRIGGER): ${DECISION_COUNT} decisions, ${COMMIT_COUNT} commits since last update ${TRACE_AGE_MIN}m ago — update TRACE before next commit"
    ;;
  2)
    echo "TRACE ($TRIGGER): ${DECISION_COUNT} decisions, ${COMMIT_COUNT} commits since last update ${TRACE_AGE_MIN}m ago [$STATUS] — STOP and update TRACE.md now."
    ;;
esac
