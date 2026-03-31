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

# Find CLAUDE.md — check CWD, parent, subdirectories
CLAUDE_MD=""
for candidate in "./CLAUDE.md" "../CLAUDE.md" ./*/CLAUDE.md; do
  if [ -f "$candidate" ]; then
    CLAUDE_MD="$candidate"
    break
  fi
done

if [ -z "$CLAUDE_MD" ]; then
  echo "TRACE: no CLAUDE.md found — no active trace"
  exit 0
fi

REPO_ROOT=$(cd "$(dirname "$CLAUDE_MD")" && pwd)
TRACE_REL=$(grep -oP '\.traces/trace-[^\s`/]+/' "$CLAUDE_MD" 2>/dev/null | head -1)

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
  COMMIT_COUNT=$(git -C "$REPO_ROOT" log --oneline --since="$ISO_SINCE" 2>/dev/null | wc -l || echo 0)

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
  AGENT_COUNT=$(grep -c "agent-spawn" "$AGENT_LOG" 2>/dev/null || echo 0)
fi

# Count decisions: pivots + gh-ops entries
DECISION_COUNT=0
PIVOT_COUNT=$(ls "$TRACE_PATH/strategy/pivot_"*.md 2>/dev/null | wc -l || echo 0)
GH_OPS_LOG="$TRACE_PATH/logs/gh-ops.log"
GH_OPS_COUNT=0
if [ -f "$GH_OPS_LOG" ]; then
  GH_OPS_COUNT=$(grep -c "^\[" "$GH_OPS_LOG" 2>/dev/null || echo 0)
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
