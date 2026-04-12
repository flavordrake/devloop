#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$SCRIPT_DIR/.."

echo "Validating devloop plugin at $PLUGIN_ROOT"

# 1. CLI validator
claude plugin validate "$PLUGIN_ROOT"

# 2. Verify all skills have frontmatter
MISSING_FRONTMATTER=0
for skill_dir in "$PLUGIN_ROOT"/skills/*/; do
  skill_file="$skill_dir/SKILL.md"
  if [ ! -f "$skill_file" ]; then
    echo "WARN: no SKILL.md in $skill_dir"
    continue
  fi
  if ! head -1 "$skill_file" | grep -q '^---$'; then
    echo "FAIL: missing frontmatter in $skill_file"
    MISSING_FRONTMATTER=1
  fi
done

if [ "$MISSING_FRONTMATTER" -eq 1 ]; then
  echo "Some skills are missing frontmatter"
  exit 1
fi

# 3. Verify all hook scripts are executable
NONEXEC=0
for hook in "$PLUGIN_ROOT"/hooks/*.sh; do
  if [ ! -x "$hook" ]; then
    echo "FAIL: not executable: $hook"
    NONEXEC=1
  fi
done

if [ "$NONEXEC" -eq 1 ]; then
  echo "Some hook scripts are not executable"
  exit 1
fi

# 4. Verify hooks.json references exist
MISSING_HOOKS=0
for ref in $(grep -oP '\$\{CLAUDE_PLUGIN_ROOT\}/\K[^"]+' "$PLUGIN_ROOT/hooks.json"); do
  if [ ! -f "$PLUGIN_ROOT/$ref" ]; then
    echo "FAIL: hooks.json references missing file: $ref"
    MISSING_HOOKS=1
  fi
done

if [ "$MISSING_HOOKS" -eq 1 ]; then
  echo "Some hook script references are broken"
  exit 1
fi

echo "All checks passed"
