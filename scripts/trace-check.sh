#!/usr/bin/env bash
# scripts/trace-check.sh — Check active TRACE freshness and suggest updates
#
# Usage (from anywhere inside the project):
#   scripts/trace-check.sh              # auto-detect active trace from CLAUDE.md
#   scripts/trace-check.sh <trace-dir>  # check a specific trace (relative to cwd)
#
# Reports:
#   - TRACE last modified time
#   - Commits since TRACE was last updated
#   - Recently modified files that may need TRACE documentation
#   - Missing TRACE sections (pivots, knowledge seed, etc.)

set -euo pipefail

# $0-relative so it resolves from the plugin cache; everything else uses the project.
source "$(dirname "$0")/lib/trace-locate.sh"

CLAUDE_MD=$(find_claude_md)
if [ -n "$CLAUDE_MD" ]; then
  REPO_ROOT=$(dirname "$CLAUDE_MD")
else
  # Outside a git repo, fall back to cwd.
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi

TRACE_DIR="${1:-}"
if [ -z "$TRACE_DIR" ] && [ -n "$CLAUDE_MD" ]; then
  TRACE_REL=$(first_trace_ref "$CLAUDE_MD")
  if [ -n "$TRACE_REL" ]; then
    TRACE_DIR="$REPO_ROOT/$TRACE_REL"
  fi
fi

if [ -z "$TRACE_DIR" ] || [ ! -d "$TRACE_DIR" ]; then
  echo "No active TRACE found."
  echo "  Init one: ${CLAUDE_PLUGIN_ROOT:-<devloop>}/scripts/trace-init.sh <objective-slug>"
  exit 0
fi

TRACE_MD="$TRACE_DIR/TRACE.md"

# Thresholds for forcing a trace update
STALE_MIN=60        # >60m since last update = stale
COMMIT_WARN=5       # >5 commits since update = falling behind

TRACE_AGE_MIN=0
COMMIT_COUNT=0
STATUS="unknown"

if [ -f "$TRACE_MD" ]; then
  TRACE_AGE=$(( $(date +%s) - $(file_mtime "$TRACE_MD") ))
  TRACE_AGE_MIN=$(( TRACE_AGE / 60 ))
  # Relative --since avoids GNU-only `date -d`; process substitution keeps a non-repo failure from tripping set -e.
  COMMIT_COUNT=$(count_matches . <(git -C "$REPO_ROOT" log --oneline --since="${TRACE_AGE} seconds ago" 2>/dev/null))

  if trace_closed "$TRACE_MD"; then
    STATUS="CLOSED"
  elif grep -q "<!-- Post-mortem" "$TRACE_MD"; then
    STATUS="BOILERPLATE"
  elif [ "$TRACE_AGE_MIN" -gt "$STALE_MIN" ]; then
    STATUS="STALE"
  else
    STATUS="current"
  fi
else
  STATUS="MISSING"
fi

# One-line summary (always first line of output)
ALERTS=""
if [ "$STATUS" != "current" ]; then
  ALERTS=" [$STATUS]"
elif [ "$COMMIT_COUNT" -gt "$COMMIT_WARN" ]; then
  ALERTS=" [${COMMIT_COUNT} commits behind]"
fi
echo "TRACE: ${COMMIT_COUNT} commits since last update ${TRACE_AGE_MIN}m ago${ALERTS}"

echo ""
echo "Active TRACE: $TRACE_DIR"
case "$STATUS" in
  MISSING) echo "  WARNING: TRACE.md does not exist!" ;;
  STALE) echo "  WARNING: TRACE is stale (>${STALE_MIN}m). Update now." ;;
  BOILERPLATE) echo "  NOTE: TRACE.md summary sections not yet populated." ;;
  CLOSED) echo "  NOTE: TRACE is closed. Init a new one if starting new work." ;;
esac

# Report below is best-effort: `| head` may SIGPIPE find, which pipefail would make fatal.
set +o pipefail

echo ""
echo "Commits since TRACE update: $COMMIT_COUNT"
git -C "$REPO_ROOT" log --oneline -5 | sed 's/^/  /'

echo ""
echo "Recently modified files (last 30 min):"
find "$REPO_ROOT" -type f -mmin -30 \
  -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/.traces/*' \
  | head -20 | sed "s|^$REPO_ROOT/|  |"

echo ""
echo "TRACE completeness:"
if [ -f "$TRACE_MD" ]; then
  check_section() {
    if grep -q "$1" "$TRACE_MD"; then
      if grep -A1 "$1" "$TRACE_MD" | grep -q "<!--"; then
        echo "  EMPTY: $1"
      else
        echo "  OK: $1"
      fi
    else
      echo "  MISSING: $1"
    fi
  }
  check_section "The \"Why\""
  check_section "The \"Ambiguity Gap\""
  check_section "The \"Knowledge Seed\""
  check_section "Performance Delta"
  check_section "Outcome Classification"
fi

echo ""
shopt -s nullglob
PIVOTS=("$TRACE_DIR"/strategy/pivot_*.md)
shopt -u nullglob
echo "Pivots recorded: ${#PIVOTS[@]}"
if [ "${#PIVOTS[@]}" -eq 0 ]; then
  echo "  (none — if strategy changed, record a pivot)"
fi

if [ -f "$TRACE_MD" ] && [ -d "$HOME/.claude/projects" ]; then
  echo ""
  echo "Memory updates (check if harvested into TRACE):"
  find "$HOME/.claude/projects" -name "*.md" -newer "$TRACE_MD" | head -5 | sed 's/^/  /'
fi
