#!/bin/bash
# PreCompact hook — snapshot git state into the active TRACE's logs/ before
# context compression. Silent and writes nothing when no trace is active.

INPUT=$(cat)
CWD=$(jq -r '.cwd // "."' <<<"$INPUT")
cd "$CWD" || exit 0

SCRIPT_DIR="$(dirname "$0")/../scripts"
CTX=$("$SCRIPT_DIR/trace-checkpoint.sh" pre-compact)
[ -n "$CTX" ] || exit 0

source "$SCRIPT_DIR/lib/trace-locate.sh"
CLAUDE_MD=$(find_claude_md)
REPO_ROOT=$(dirname "$CLAUDE_MD")
LOG_DIR="$REPO_ROOT/$(first_trace_ref "$CLAUDE_MD")logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +%Y%m%dT%H%M%S%z)
{
  echo "# Pre-Compact Snapshot $TIMESTAMP"
  echo ""
  echo "$CTX"
  echo ""
  git -C "$REPO_ROOT" log --oneline -5
  echo ""
  git -C "$REPO_ROOT" status --porcelain | head -20
} > "$LOG_DIR/compact-${TIMESTAMP}.md"

# PreCompact honors only decision/reason (to block) and has no additionalContext
# channel; hookSpecificOutput fails validation. So emit no JSON: the status line
# goes into the snapshot above and to stderr, which on exit 0 lands in the debug log.
echo "$CTX" >&2
