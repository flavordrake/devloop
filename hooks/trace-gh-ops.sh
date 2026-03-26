#!/bin/bash
# PostToolUse hook (Bash matcher): log GitHub operations to active TRACE.
# Captures issue filing, PR creation, integration, and delegation decisions.
# Only fires when the Bash command invokes gh-ops.sh or gh-file-issue.sh.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only capture gh operations
case "$COMMAND" in
  *gh-ops.sh*|*gh-file-issue.sh*) ;;
  *) exit 0 ;;
esac

CWD=$(echo "$INPUT" | jq -r '.cwd // "."')
OUTPUT=$(echo "$INPUT" | jq -r '.tool_response.stdout // empty')
TIMESTAMP=$(date +%Y%m%dT%H%M%S%z)

# Find active TRACE
CLAUDE_MD=""
for candidate in "$CWD/CLAUDE.md" "$CWD/../CLAUDE.md" "$CWD"/*/CLAUDE.md; do
  if [ -f "$candidate" ]; then
    CLAUDE_MD="$candidate"
    break
  fi
done

[ -z "$CLAUDE_MD" ] && exit 0

REPO_ROOT=$(dirname "$CLAUDE_MD")
TRACE_DIR=$(grep -oP '\.traces/trace-[^\s`/]+/' "$CLAUDE_MD" 2>/dev/null | head -1)

[ -z "$TRACE_DIR" ] && exit 0
[ ! -d "$REPO_ROOT/$TRACE_DIR" ] && exit 0

LOG_DIR="$REPO_ROOT/$TRACE_DIR/logs"
mkdir -p "$LOG_DIR"

LOG_FILE="$LOG_DIR/gh-ops.log"

# Extract the subcommand for a readable summary
SUBCMD=$(echo "$COMMAND" | grep -oP '(gh-ops\.sh|gh-file-issue\.sh)\s+\K\S+' || echo "unknown")

# Extract issue/PR URL from output if present
URL=$(echo "$OUTPUT" | grep -oP 'https://github\.com/[^\s]+' | head -1)

{
  echo "[$TIMESTAMP] $SUBCMD"
  echo "  cmd: $COMMAND"
  [ -n "$URL" ] && echo "  url: $URL"
  echo ""
} >> "$LOG_FILE"

# No additionalContext needed — this is pure logging
exit 0
