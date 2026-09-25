#!/bin/bash
# PreCompact hook — capture TRACE checkpoint before context compression.
# Calls the general-purpose trace-checkpoint script, then saves a snapshot
# of git state to the TRACE logs directory.

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')
cd "$CWD" 2>/dev/null || true

SCRIPT_DIR="$(dirname "$0")/../scripts"
CTX=$("$SCRIPT_DIR/trace-checkpoint.sh" "pre-compact" 2>/dev/null || echo "TRACE (pre-compact): status unavailable")

# Also save a snapshot to the TRACE logs
source "$SCRIPT_DIR/lib/trace-locate.sh"
CLAUDE_MD=$(find_claude_md)

if [ -n "$CLAUDE_MD" ]; then
  REPO_ROOT=$(dirname "$CLAUDE_MD")
  TRACE_REL=$(first_trace_ref "$CLAUDE_MD")
  if [ -n "$TRACE_REL" ] && [ -d "$REPO_ROOT/$TRACE_REL" ]; then
    LOG_DIR="$REPO_ROOT/${TRACE_REL}logs"
    mkdir -p "$LOG_DIR"
    TIMESTAMP=$(date +%Y%m%dT%H%M%S%z)
    {
      echo "# Pre-Compact Snapshot $TIMESTAMP"
      echo ""
      echo "$CTX"
      echo ""
      git -C "$REPO_ROOT" log --oneline -5 2>/dev/null
      echo ""
      git -C "$REPO_ROOT" status --porcelain 2>/dev/null | head -20
    } > "$LOG_DIR/compact-${TIMESTAMP}.md"
  fi
fi

# PreCompact honors only decision/reason (to block) and has no additionalContext
# channel; hookSpecificOutput fails validation. So emit no JSON: the status line
# goes into the snapshot above and to stderr, which on exit 0 lands in the debug log.
echo "$CTX" >&2
