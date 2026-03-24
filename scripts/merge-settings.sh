#!/usr/bin/env bash
# scripts/merge-settings.sh — Merge devloop recommended permissions into project settings
#
# Usage:
#   scripts/merge-settings.sh /path/to/project/.claude/settings.json
#   scripts/merge-settings.sh                    # uses ./.claude/settings.json
#
# Adds devloop's recommended permissions to the project's allow list.
# Requires jq. Non-destructive — only adds, never removes.

set -euo pipefail

DEVLOOP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-.claude/settings.json}"

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required. Install it with: apt install jq / brew install jq"
  exit 1
fi

# Recommended permissions for devloop skills and agents
RECOMMENDED='[
  "Edit", "Write", "WebSearch", "WebFetch",
  "Bash(git *)", "Bash(npm *)", "Bash(npx *)", "Bash(node *)",
  "Bash(scripts/*)", "Bash(ls *)", "Bash(cat *)", "Bash(head *)",
  "Bash(tail *)", "Bash(diff *)", "Bash(wc *)", "Bash(which *)",
  "Bash(date *)", "Bash(mkdir *)", "Bash(cp *)", "Bash(mv *)",
  "Bash(chmod *)", "Bash(echo *)", "Bash(ps *)", "Bash(tree *)"
]'

if [ ! -f "$TARGET" ]; then
  echo "No settings found at $TARGET — creating with recommended permissions."
  echo "{\"permissions\":{\"allow\":$RECOMMENDED}}" | jq . > "$TARGET"
  echo "Created $TARGET"
  exit 0
fi

echo "Merging devloop permissions into $TARGET"

# Read existing, merge, deduplicate
MERGED=$(jq --argjson rec "$RECOMMENDED" '
  .permissions.allow = ((.permissions.allow // []) + $rec | unique)
' "$TARGET")

echo "$MERGED" > "$TARGET"

BEFORE=$(jq '.permissions.allow | length' "$TARGET" 2>/dev/null || echo 0)
echo "Done. Allow list: $BEFORE entries."
