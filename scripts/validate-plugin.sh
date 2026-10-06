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

# 3. Verify all hook and script entry points are executable (lib/ is sourced, not run)
NONEXEC=0
for script in "$PLUGIN_ROOT"/hooks/*.sh "$PLUGIN_ROOT"/scripts/*.sh "$PLUGIN_ROOT"/scripts/test/*.sh; do
  if [ ! -x "$script" ]; then
    echo "FAIL: not executable: $script"
    NONEXEC=1
  fi
done

if [ "$NONEXEC" -eq 1 ]; then
  echo "Some scripts are not executable"
  exit 1
fi

# 4. Every hooks.json command must quote the plugin root ("${CLAUDE_PLUGIN_ROOT}/..."),
#    or a path with spaces breaks; and every referenced file must exist.
BAD_HOOKS=0
while IFS= read -r cmd; do
  case "$cmd" in
    *CLAUDE_PLUGIN_ROOT*) ;;
    *) continue ;;
  esac
  if [[ "$cmd" != \"\$\{CLAUDE_PLUGIN_ROOT\}/*\"* ]]; then
    echo "FAIL: hooks.json command does not quote \${CLAUDE_PLUGIN_ROOT}: $cmd"
    BAD_HOOKS=1
    continue
  fi
  ref=${cmd#\"\$\{CLAUDE_PLUGIN_ROOT\}/}
  ref=${ref%%\"*}
  if [ ! -f "$PLUGIN_ROOT/$ref" ]; then
    echo "FAIL: hooks.json references missing file: $ref"
    BAD_HOOKS=1
  fi
done < <(jq -r '.. | objects | .command? // empty' "$PLUGIN_ROOT/hooks.json")

if [ "$BAD_HOOKS" -eq 1 ]; then
  echo "Some hooks.json commands are broken"
  exit 1
fi

echo "All checks passed"
