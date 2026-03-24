#!/usr/bin/env bash
# install.sh — Install devloop into a workspace or project
#
# Usage:
#   ./install.sh /path/to/workspace    # symlink into workspace/.claude/
#   ./install.sh                        # symlink into current directory/.claude/
#
# Creates symlinks from target/.claude/{skills,agents,hooks,rules,settings.json}
# to this devloop checkout. Preserves existing settings.local.json.

set -euo pipefail

DEVLOOP_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="${1:-.}"
CLAUDE_DIR="$TARGET/.claude"

echo "Installing devloop into $CLAUDE_DIR"
echo "  Source: $DEVLOOP_DIR"

mkdir -p "$CLAUDE_DIR"

for dir in skills agents hooks rules; do
  if [ -L "$CLAUDE_DIR/$dir" ]; then
    echo "  $dir: updating symlink"
    rm "$CLAUDE_DIR/$dir"
  elif [ -d "$CLAUDE_DIR/$dir" ]; then
    echo "  $dir: backing up existing to $dir.bak"
    mv "$CLAUDE_DIR/$dir" "$CLAUDE_DIR/$dir.bak"
  fi
  ln -s "$DEVLOOP_DIR/$dir" "$CLAUDE_DIR/$dir"
  echo "  $dir: linked"
done

# Settings: symlink only if not already present (don't clobber project settings)
if [ ! -f "$CLAUDE_DIR/settings.json" ] && [ ! -L "$CLAUDE_DIR/settings.json" ]; then
  ln -s "$DEVLOOP_DIR/settings.json" "$CLAUDE_DIR/settings.json"
  echo "  settings.json: linked"
else
  echo "  settings.json: skipped (already exists)"
fi

echo "Done. Devloop installed."
echo ""
echo "Project-specific overrides go in $CLAUDE_DIR/ (merged by Claude Code)."
echo "To update: git pull in $DEVLOOP_DIR"
