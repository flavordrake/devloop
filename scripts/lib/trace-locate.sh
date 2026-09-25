#!/usr/bin/env bash
# scripts/lib/trace-locate.sh — locate the session's CLAUDE.md and its active trace.
#
# Source it relative to the caller, so it resolves from the plugin cache too:
#   source "$(dirname "$0")/lib/trace-locate.sh"             # from scripts/
#   source "$(dirname "$0")/../scripts/lib/trace-locate.sh"  # from hooks/

# Grep exception from rules/command-hygiene.md.
first_trace_ref() { grep -m1 -oP '\.traces/trace-[^\s`/]+/' "$1" 2>/dev/null || true; }

# Find CLAUDE.md: $CLAUDE_PROJECT_DIR, else nearest ancestor of cwd.
# Never glob into child/sibling dirs — that reported and wrote unrelated repos' traces.
find_claude_md() {
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$CLAUDE_PROJECT_DIR/CLAUDE.md" ]; then
    echo "$CLAUDE_PROJECT_DIR/CLAUDE.md"
    return
  fi
  local dir
  dir=$(pwd)
  while [ ! -f "$dir/CLAUDE.md" ]; do
    if [ "$dir" = "/" ]; then
      return
    fi
    dir=$(dirname "$dir")
  done
  echo "$dir/CLAUDE.md"
}
