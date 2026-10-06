#!/bin/bash
# PreToolUse:Bash hook: nudge raw `gh` calls toward the repo's gh wrapper scripts.
# Emits additionalContext only. Never a permissionDecision: "allow" there would
# skip permission prompts and the auto-mode classifier for the command.
# Pipe/redirect/chain/heredoc nudges were removed: noise that contradicts harness guidance.

INPUT=$(cat)
COMMAND=$(jq -r '.tool_input.command // empty' <<<"$INPUT")

if [[ "$COMMAND" =~ ^[[:space:]]*gh[[:space:]] ]]; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      additionalContext: "Command hygiene: raw gh call. Prefer scripts/gh-ops.sh or scripts/gh-file-issue.sh when they cover this operation."
    }
  }'
fi
exit 0
