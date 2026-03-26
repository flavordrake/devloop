#!/usr/bin/env bash
# scripts/trace-check.sh — Check active TRACE freshness and suggest updates
#
# Usage:
#   scripts/trace-check.sh              # auto-detect active trace from CLAUDE.md
#   scripts/trace-check.sh <trace-dir>  # check a specific trace
#
# Reports:
#   - TRACE last modified time
#   - Commits since TRACE was last updated
#   - Recently modified files that may need TRACE documentation
#   - Missing TRACE sections (pivots, knowledge seed, etc.)

set -euo pipefail
cd "$(dirname "$0")/.."

# Find active TRACE
TRACE_DIR="${1:-}"
if [ -z "$TRACE_DIR" ]; then
  if [ -f "CLAUDE.md" ]; then
    TRACE_DIR=$(grep -oP '\.traces/trace-[^\s`/]+/' CLAUDE.md 2>/dev/null | head -1)
  fi
fi

if [ -z "$TRACE_DIR" ] || [ ! -d "$TRACE_DIR" ]; then
  echo "No active TRACE found."
  echo "  Init one: scripts/trace-init.sh <objective-slug>"
  echo "  Reference it in CLAUDE.md: > **Active TRACE**: \`.traces/trace-...\`"
  exit 0
fi

TRACE_MD="$TRACE_DIR/TRACE.md"

# Thresholds for forcing a trace update
STALE_MIN=60        # >60m since last update = stale
COMMIT_WARN=5       # >5 commits since update = falling behind
AGENT_WARN=3        # >3 agent runs since update = significant untraced work

# Gather metrics
TRACE_AGE_MIN=0
COMMIT_COUNT=0
AGENT_COUNT=0
STATUS="unknown"

if [ -f "$TRACE_MD" ]; then
  TRACE_MTIME=$(stat -c %Y "$TRACE_MD" 2>/dev/null || echo 0)
  TRACE_AGE=$(( $(date +%s) - TRACE_MTIME ))
  TRACE_AGE_MIN=$(( TRACE_AGE / 60 ))

  ISO_SINCE=$(date -d "@$TRACE_MTIME" --iso-8601=seconds 2>/dev/null || echo '1 hour ago')
  COMMIT_COUNT=$(git log --oneline --since="$ISO_SINCE" 2>/dev/null | wc -l)

  AGENT_LOG="$TRACE_DIR/logs/agents.log"
  if [ -f "$AGENT_LOG" ]; then
    AGENT_COUNT=$(grep -c "agent-spawn" "$AGENT_LOG" 2>/dev/null || echo 0)
  fi

  if grep -q "<!-- Post-mortem" "$TRACE_MD" 2>/dev/null; then
    STATUS="BOILERPLATE"
  elif grep -qP '^status:\s+(success|failed)' "$TRACE_MD" 2>/dev/null; then
    STATUS="CLOSED"
  elif [ $TRACE_AGE_MIN -gt $STALE_MIN ]; then
    STATUS="STALE"
  else
    STATUS="current"
  fi
else
  STATUS="MISSING"
fi

# One-line summary (always first line of output)
ALERTS=""
if [ "$STATUS" = "STALE" ] || [ "$STATUS" = "BOILERPLATE" ] || [ "$STATUS" = "MISSING" ] || [ "$STATUS" = "CLOSED" ]; then
  ALERTS=" [$STATUS]"
elif [ "$COMMIT_COUNT" -gt "$COMMIT_WARN" ]; then
  ALERTS=" [${COMMIT_COUNT} commits behind]"
elif [ "$AGENT_COUNT" -gt "$AGENT_WARN" ]; then
  ALERTS=" [${AGENT_COUNT} agents untraced]"
fi
echo "TRACE: ${COMMIT_COUNT} commits, ${AGENT_COUNT} agents since last update ${TRACE_AGE_MIN}m ago${ALERTS}"

# Detailed output below
echo ""
echo "Active TRACE: $TRACE_DIR"

if [ "$STATUS" = "MISSING" ]; then
  echo "  WARNING: TRACE.md does not exist!"
elif [ "$STATUS" = "STALE" ]; then
  echo "  WARNING: TRACE is stale (>${STALE_MIN}m). Update now."
elif [ "$STATUS" = "BOILERPLATE" ]; then
  echo "  WARNING: TRACE.md was never populated."
elif [ "$STATUS" = "CLOSED" ]; then
  echo "  WARNING: TRACE is closed. Init a new one if starting new work."
fi

echo ""
echo "Commits since TRACE update:"
echo "  $COMMIT_COUNT commit(s) since last TRACE update"
git log --oneline -5 2>/dev/null | sed 's/^/  /'

# Recently modified source files
echo ""
echo "Recently modified files (last 30 min):"
find . -name "*.ts" -o -name "*.js" -o -name "*.css" -o -name "*.html" -o -name "*.sh" 2>/dev/null \
  | grep -v node_modules | grep -v ".traces/" | grep -v public/modules/ \
  | while read -r f; do
    MTIME=$(stat -c %Y "$f" 2>/dev/null || echo 0)
    AGE=$(( $(date +%s) - MTIME ))
    if [ $AGE -lt 1800 ]; then
      echo "  $f ($(( AGE / 60 ))m ago)"
    fi
  done

# Check TRACE completeness
echo ""
echo "TRACE completeness:"
if [ -f "$TRACE_MD" ]; then
  check_section() {
    if grep -q "$1" "$TRACE_MD" 2>/dev/null; then
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

# Check for pivots
echo ""
PIVOT_COUNT=$(ls "$TRACE_DIR/strategy/pivot_"*.md 2>/dev/null | wc -l)
echo "Pivots recorded: $PIVOT_COUNT"
if [ $PIVOT_COUNT -eq 0 ]; then
  echo "  (none — if strategy changed, record a pivot)"
fi

# Memory updates since TRACE
echo ""
echo "Memory updates (check if harvested into TRACE):"
find /home/dev/.claude/projects/ -name "*.md" -newer "$TRACE_MD" 2>/dev/null | head -5 | sed 's/^/  /'
