#!/bin/bash
# PostToolUse hook: detect writes to decision-signal paths and check TRACE freshness.
# Fires on Write and Edit. Does NOT block — returns additionalContext only.
#
# Decision-signal paths:
#   - memory/              (memory updates = captured learning)
#   - .claude/settings*    (permission/config changes = process decisions)
#   - .claude/rules/       (rule updates = policy decisions)
#   - CLAUDE.md            (project context changes)

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -z "$FILE_PATH" ] && exit 0

# Check if file matches a decision-signal path
SIGNAL=""

case "$FILE_PATH" in
  */memory/*|*/.claude/projects/*/memory/*)
    SIGNAL="MEMORY_UPDATE" ;;
  */.claude/settings*.json)
    SIGNAL="SETTINGS_UPDATE" ;;
  */.claude/rules/*)
    SIGNAL="RULE_UPDATE" ;;
  */CLAUDE.md)
    SIGNAL="CONTEXT_UPDATE" ;;
  */.traces/*)
    # Don't signal on TRACE writes themselves — that's the response, not the trigger
    exit 0 ;;
esac

[ -z "$SIGNAL" ] && exit 0

# Find active TRACE from CLAUDE.md — check file's project root, then CWD
TRACE_DIR=""
TRACE_STATUS=""
PROJECT_ROOT=""

# Derive project root from the file being written (walk up to find CLAUDE.md)
DIR=$(dirname "$FILE_PATH")
while [ "$DIR" != "/" ] && [ "$DIR" != "." ]; do
  if [ -f "$DIR/CLAUDE.md" ]; then
    PROJECT_ROOT="$DIR"
    break
  fi
  DIR=$(dirname "$DIR")
done

# Fallback to CWD
if [ -z "$PROJECT_ROOT" ] && [ -f "CLAUDE.md" ]; then
  PROJECT_ROOT="."
fi

if [ -n "$PROJECT_ROOT" ]; then
  TRACE_DIR=$(grep -oP '\.traces/trace-[^\s`/]+/' "$PROJECT_ROOT/CLAUDE.md" 2>/dev/null | head -1)
  if [ -n "$TRACE_DIR" ]; then
    TRACE_DIR="$PROJECT_ROOT/$TRACE_DIR"
  fi
fi

if [ -n "$TRACE_DIR" ] && [ -f "$TRACE_DIR/TRACE.md" ]; then
  # Check freshness
  TRACE_MTIME=$(stat -c %Y "$TRACE_DIR/TRACE.md" 2>/dev/null || echo 0)
  TRACE_AGE=$(( $(date +%s) - TRACE_MTIME ))
  TRACE_AGE_MIN=$(( TRACE_AGE / 60 ))

  # Check if still boilerplate
  if grep -q "<!-- Post-mortem" "$TRACE_DIR/TRACE.md" 2>/dev/null; then
    TRACE_STATUS="BOILERPLATE (never populated)"
  elif [ $TRACE_AGE_MIN -gt 60 ]; then
    TRACE_STATUS="STALE (${TRACE_AGE_MIN}m since last update)"
  else
    TRACE_STATUS="current (${TRACE_AGE_MIN}m ago)"
  fi

  # Count commits since update
  COMMIT_COUNT=$(git log --oneline --after="$(date -d @$TRACE_MTIME --iso-8601=seconds 2>/dev/null || echo '1 hour ago')" 2>/dev/null | wc -l || echo "?")

  CONTEXT="TRACE signal (${SIGNAL}): ${FILE_PATH##*/}. Active TRACE: ${TRACE_DIR} — ${TRACE_STATUS}, ${COMMIT_COUNT} commits since. Run scripts/trace-check.sh for details."
else
  CONTEXT="TRACE signal (${SIGNAL}): ${FILE_PATH##*/}. No active TRACE found. Init with scripts/trace-init.sh if this is part of a development arc."
fi

jq -n --arg ctx "$CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $ctx
  }
}'
