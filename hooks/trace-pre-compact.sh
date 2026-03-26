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
CLAUDE_MD=""
for candidate in "./CLAUDE.md" "../CLAUDE.md" ./*/CLAUDE.md; do
  if [ -f "$candidate" ]; then
    CLAUDE_MD="$candidate"
    break
  fi
done

if [ -n "$CLAUDE_MD" ]; then
  REPO_ROOT=$(cd "$(dirname "$CLAUDE_MD")" && pwd)
  TRACE_REL=$(grep -oP '\.traces/trace-[^\s`/]+/' "$CLAUDE_MD" 2>/dev/null | head -1)
  if [ -n "$TRACE_REL" ] && [ -d "$REPO_ROOT/$TRACE_REL" ]; then
    LOG_DIR="$REPO_ROOT/${TRACE_REL}logs"
    mkdir -p "$LOG_DIR"
    TIMESTAMP=$(date +%Y%m%dT%H%M%S%z)
    {
      echo "# Pre-Compact Snapshot $TIMESTAMP"
      echo ""
      git -C "$REPO_ROOT" log --oneline -5 2>/dev/null
      echo ""
      git -C "$REPO_ROOT" status --porcelain 2>/dev/null | head -20
    } > "$LOG_DIR/compact-${TIMESTAMP}.md"
  fi
fi

jq -n --arg ctx "$CTX" '{
  hookSpecificOutput: {
    hookEventName: "PreCompact",
    additionalContext: $ctx
  }
}'
