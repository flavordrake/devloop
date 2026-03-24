#!/usr/bin/env bash
# install.sh — Install devloop into a workspace or project
#
# Usage:
#   ./install.sh /path/to/workspace    # install into workspace/.claude/
#   ./install.sh                        # install into current directory/.claude/
#
# Strategy:
#   - Skills, agents, hooks: symlinked as subdirectories inside devloop/
#     (e.g., .claude/skills/devloop -> devloop/skills). Project keeps its own
#     skills alongside devloop's — no clobbering.
#   - Rules: same pattern — .claude/rules/devloop -> devloop/rules
#   - Settings: merges devloop permissions and hooks into existing settings.json
#     using jq. Creates settings.json if it doesn't exist.
#
# This means a project with existing .claude/skills/my-skill/ keeps it.
# devloop skills appear as .claude/skills/devloop/cycle/SKILL.md etc.
# Claude Code discovers skills recursively in .claude/skills/.

set -euo pipefail

DEVLOOP_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="${1:-.}"
CLAUDE_DIR="$TARGET/.claude"

echo "Installing devloop into $CLAUDE_DIR"
echo "  Source: $DEVLOOP_DIR"

mkdir -p "$CLAUDE_DIR/skills" "$CLAUDE_DIR/agents" "$CLAUDE_DIR/hooks" "$CLAUDE_DIR/rules"

# Symlink devloop content as a subdirectory — doesn't clobber existing project content
for dir in skills agents rules; do
  LINK="$CLAUDE_DIR/$dir/devloop"
  if [ -L "$LINK" ]; then
    rm "$LINK"
  fi
  ln -s "$DEVLOOP_DIR/$dir" "$LINK"
  echo "  $dir/devloop: linked"
done

# Hooks: symlink individual files (hooks aren't discovered recursively)
for hook in "$DEVLOOP_DIR"/hooks/*.sh; do
  name=$(basename "$hook")
  LINK="$CLAUDE_DIR/hooks/$name"
  if [ -L "$LINK" ]; then
    rm "$LINK"
  elif [ -f "$LINK" ]; then
    echo "  hooks/$name: skipped (project has its own)"
    continue
  fi
  ln -s "$hook" "$LINK"
  echo "  hooks/$name: linked"
done

# Settings: merge devloop permissions and hooks into existing settings.json
SETTINGS="$CLAUDE_DIR/settings.json"
DEVLOOP_SETTINGS="$DEVLOOP_DIR/settings.json"

if [ ! -f "$SETTINGS" ]; then
  # No existing settings — copy devloop's as starting point
  cp "$DEVLOOP_SETTINGS" "$SETTINGS"
  echo "  settings.json: created from devloop"
elif command -v jq >/dev/null 2>&1; then
  # Merge: add devloop permissions to existing allow list, add hooks
  MERGED=$(jq -s '
    .[0] as $existing | .[1] as $devloop |
    ($existing.permissions.allow // []) + ($devloop.permissions.allow // []) | unique as $merged_allow |
    $existing * {
      permissions: ($existing.permissions // {} | . + { allow: $merged_allow }),
      hooks: (($existing.hooks // {}) * ($devloop.hooks // {}))
    }
  ' "$SETTINGS" "$DEVLOOP_SETTINGS")
  echo "$MERGED" > "$SETTINGS"
  echo "  settings.json: merged (permissions + hooks)"
else
  echo "  settings.json: jq not found, skipped merge (install jq for auto-merge)"
fi

echo ""
echo "Done. Devloop installed."
echo "  Project skills:  $CLAUDE_DIR/skills/  (your skills alongside devloop/)"
echo "  Project rules:   $CLAUDE_DIR/rules/   (your rules alongside devloop/)"
echo "  Project agents:  $CLAUDE_DIR/agents/  (your agents alongside devloop/)"
echo "  To update: git pull in $DEVLOOP_DIR, symlinks follow automatically"
