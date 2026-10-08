#!/usr/bin/env bash
# scripts/lib/trace-locate.sh — locate the session's CLAUDE.md and its active trace.
#
# Source it relative to the caller, so it resolves from the plugin cache too:
#   source "$(dirname "$0")/lib/trace-locate.sh"             # from scripts/
#   source "$(dirname "$0")/../scripts/lib/trace-locate.sh"  # from hooks/
#
# Portable grep/stat only: these also run on the Mac build host (no grep -P, stat -c, date -d).

# first_trace_ref CLAUDE_MD — the first trace dir token in the file, with a
# trailing slash. The Active TRACE line may be prose naming several arcs (mobissh
# writes one); extra words and a missing trailing slash are fine, the first
# path-like token wins. Grep exception from rules/command-hygiene.md: no match
# is a normal empty result.
first_trace_ref() {
  local ref
  ref=$(grep -m1 -oE '\.traces/trace-[A-Za-z0-9._-]+/?' "$1" 2>/dev/null | head -n1 || true)
  if [ -n "$ref" ]; then echo "${ref%/}/"; fi
}

# has_active_trace_line CLAUDE_MD — an Active TRACE line is present (any content).
has_active_trace_line() { grep -q '^> \*\*Active TRACE\*\*' "$1" 2>/dev/null; }

# grep -c prints 0 AND exits 1 on no match; `|| true` keeps the single "0".
count_matches() { grep -c -- "$1" "$2" 2>/dev/null || true; }

# file_mtime FILE — epoch seconds; GNU stat, else BSD stat.
file_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }

# trace_closed TRACE_MD — frontmatter status is terminal.
trace_closed() { grep -qE '^status:[[:space:]]+(success|failed|failure)' "$1"; }

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
