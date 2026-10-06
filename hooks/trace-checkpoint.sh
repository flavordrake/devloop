#!/bin/bash
# PostToolUse:Bash hook — TRACE status after a `git commit`. Silent for any
# other command, and silent when no trace is active.

INPUT=$(cat)
COMMAND=$(jq -r '.tool_input.command // empty' <<<"$INPUT")
CWD=$(jq -r '.cwd // "."' <<<"$INPUT")

# is_git_commit — true if any simple command in $COMMAND is `git [opts] commit`.
# Parsed by command word, not substring: `cat scripts/gh-ops.sh` or
# `echo "git commit"` must not fire.
is_git_commit() {
  local cmds="$COMMAND" seg
  cmds=${cmds//&&/$'\n'}
  cmds=${cmds//||/$'\n'}
  cmds=${cmds//;/$'\n'}
  cmds=${cmds//|/$'\n'}
  while IFS= read -r seg; do
    set -f
    # shellcheck disable=SC2086 # split the segment into words on purpose
    set -- $seg
    set +f
    while [ $# -gt 0 ] && [[ "$1" == *=* ]]; do shift; done
    [ "${1:-}" = git ] || continue
    shift
    while [ $# -gt 0 ]; do
      case "$1" in
        commit) return 0 ;;
        -C|-c|--git-dir|--work-tree) shift; [ $# -gt 0 ] && shift ;;
        -*) shift ;;
        *) break ;;
      esac
    done
  done <<<"$cmds"
  return 1
}

is_git_commit || exit 0
cd "$CWD" || exit 0

CTX=$("$(dirname "$0")/../scripts/trace-checkpoint.sh" commit)
[ -n "$CTX" ] || exit 0

jq -n --arg ctx "$CTX" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $ctx
  }
}'
