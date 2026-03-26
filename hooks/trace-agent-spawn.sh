#!/bin/bash
# SubagentStart hook — log agent spawn and emit TRACE checkpoint.

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')
cd "$CWD" 2>/dev/null || true

# Log to TRACE
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
    echo "[$TIMESTAMP] agent-spawn" >> "$LOG_DIR/agents.log"
  fi
fi

SCRIPT_DIR="$(dirname "$0")/../scripts"
CTX=$("$SCRIPT_DIR/trace-checkpoint.sh" "agent-spawn" 2>/dev/null || echo "TRACE (agent-spawn): status unavailable")

jq -n --arg ctx "$CTX" '{
  hookSpecificOutput: {
    hookEventName: "SubagentStart",
    additionalContext: $ctx
  }
}'
