#!/bin/bash
# PostToolUse:Bash hook — thin wrapper around scripts/trace-checkpoint.sh
# Detects decision-point commands and emits TRACE status as additionalContext.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Classify the command — exit early for non-decision commands
TRIGGER=""
case "$COMMAND" in
  *"git commit"*) TRIGGER="commit" ;;
  *"git push"*) TRIGGER="push" ;;
  *container-ctl.sh*restart*|*container-ctl.sh*ensure*) TRIGGER="deploy" ;;
  *gh-ops.sh*integrate*) TRIGGER="integrate" ;;
  *gh-ops.sh*pr-create*|*gh-ops.sh*pr-merge*) TRIGGER="pr" ;;
  *gh-file-issue.sh*) TRIGGER="issue-filed" ;;
  *gh-ops.sh*comment*) TRIGGER="comment" ;;
  *gh-ops.sh*labels*) TRIGGER="labels" ;;
  *trace-init.sh*|*trace-check.sh*) TRIGGER="trace-mgmt" ;;
  *) exit 0 ;;
esac

# Run the general-purpose checkpoint script
SCRIPT_DIR="$(dirname "$0")/../scripts"
CTX=$("$SCRIPT_DIR/trace-checkpoint.sh" "$TRIGGER" 2>/dev/null || echo "TRACE ($TRIGGER): status unavailable")

jq -n --arg ctx "$CTX" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $ctx
  }
}'
