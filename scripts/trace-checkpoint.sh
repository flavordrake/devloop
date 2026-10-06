#!/usr/bin/env bash
# scripts/trace-checkpoint.sh — Emit a one-line status for the active TRACE.
#
# Called by the SessionStart, PreCompact and post-commit hooks, or manually:
#   scripts/trace-checkpoint.sh [trigger-label]
#
# Prints NOTHING when there is no active trace (no CLAUDE.md, no trace ref,
# missing TRACE.md, or a closed trace): TRACE is opt-in.

set -euo pipefail

TRIGGER="${1:-checkpoint}"

# $0-relative so it resolves from the plugin cache.
source "$(dirname "$0")/lib/trace-locate.sh"

CLAUDE_MD=$(find_claude_md)
[ -n "$CLAUDE_MD" ] || exit 0
REPO_ROOT=$(dirname "$CLAUDE_MD")
TRACE_REL=$(first_trace_ref "$CLAUDE_MD")
[ -n "$TRACE_REL" ] || exit 0
TRACE_PATH="$REPO_ROOT/$TRACE_REL"
TRACE_MD="$TRACE_PATH/TRACE.md"
[ -f "$TRACE_MD" ] || exit 0
if trace_closed "$TRACE_MD"; then
  exit 0
fi

TRACE_AGE=$(( $(date +%s) - $(file_mtime "$TRACE_MD") ))
TRACE_AGE_MIN=$(( TRACE_AGE / 60 ))
# Relative --since avoids GNU-only `date -d`. Process substitution: a non-repo
# git failure must not trip pipefail/set -e.
COMMIT_COUNT=$(count_matches . <(git -C "$REPO_ROOT" log --oneline --since="${TRACE_AGE} seconds ago" 2>/dev/null))

# nullglob array instead of `ls | wc -l`, which doubled the 0 with no pivots.
shopt -s nullglob
PIVOTS=("$TRACE_PATH"/strategy/pivot_*.md)
shopt -u nullglob

# Commits are reported once, not also summed into a "decisions" total.
STATUS_LINE="TRACE ($TRIGGER): ${#PIVOTS[@]} pivots, ${COMMIT_COUNT} commits since last update ${TRACE_AGE_MIN}m ago"

# Escalation: stale (>60m or >5 commits), drift (>2 commits and >30m), quiet.
if [ "$TRACE_AGE_MIN" -gt 60 ] || [ "$COMMIT_COUNT" -gt 5 ]; then
  echo "$STATUS_LINE [STALE] — update TRACE.md now."
elif [ "$COMMIT_COUNT" -gt 2 ] && [ "$TRACE_AGE_MIN" -gt 30 ]; then
  echo "$STATUS_LINE — update TRACE before next commit"
else
  echo "$STATUS_LINE"
fi
