#!/bin/bash
# SessionStart hook — TRACE status on session start/resume/clear.
# Silent when no trace is active.

INPUT=$(cat)
CWD=$(jq -r '.cwd // "."' <<<"$INPUT")
cd "$CWD" || exit 0

CTX=$("$(dirname "$0")/../scripts/trace-checkpoint.sh" session-start)
[ -n "$CTX" ] || exit 0

jq -n --arg ctx "$CTX" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'
