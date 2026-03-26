#!/bin/bash
# SessionStart hook — check TRACE status on session start/resume/clear.
# Calls the general-purpose trace-checkpoint script.

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')
cd "$CWD" 2>/dev/null || true

SCRIPT_DIR="$(dirname "$0")/../scripts"
CTX=$("$SCRIPT_DIR/trace-checkpoint.sh" "session-start" 2>/dev/null || echo "TRACE (session-start): status unavailable")

jq -n --arg ctx "$CTX" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'
