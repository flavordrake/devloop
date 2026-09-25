#!/bin/bash
# SubagentStart hook — log agent spawn and emit TRACE checkpoint.

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')
cd "$CWD" 2>/dev/null || true

SCRIPT_DIR="$(dirname "$0")/../scripts"

# Log to TRACE
source "$SCRIPT_DIR/lib/trace-locate.sh"
CLAUDE_MD=$(find_claude_md)

if [ -n "$CLAUDE_MD" ]; then
  REPO_ROOT=$(dirname "$CLAUDE_MD")
  TRACE_REL=$(first_trace_ref "$CLAUDE_MD")
  if [ -n "$TRACE_REL" ] && [ -d "$REPO_ROOT/$TRACE_REL" ]; then
    LOG_DIR="$REPO_ROOT/${TRACE_REL}logs"
    mkdir -p "$LOG_DIR"
    TIMESTAMP=$(date +%Y%m%dT%H%M%S%z)
    echo "[$TIMESTAMP] agent-spawn" >> "$LOG_DIR/agents.log"
  fi
fi

CTX=$("$SCRIPT_DIR/trace-checkpoint.sh" "agent-spawn" 2>/dev/null || echo "TRACE (agent-spawn): status unavailable")

jq -n --arg ctx "$CTX" '{
  hookSpecificOutput: {
    hookEventName: "SubagentStart",
    additionalContext: $ctx
  }
}'
