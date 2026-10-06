#!/usr/bin/env bash
# scripts/devloop-path.sh: print the root of the newest installed devloop plugin,
# so shell callers outside a skill (no ${CLAUDE_PLUGIN_ROOT}) need no
# version-pinned path and no repo-local shim.
# Usage: "$(devloop-path.sh)/scripts/gh-ops.sh" ...
# Order: $DEVLOOP_ROOT, else the highest version under
# ${CLAUDE_CONFIG_DIR:-~/.claude}/plugins/cache/flavordrake/devloop/, else the
# checkout this script lives in (e.g. the marketplace clone).
# Portable: numeric field sort, not GNU-only `sort -V` (macOS hosts).
set -euo pipefail

if [[ -n "${DEVLOOP_ROOT:-}" ]]; then
  echo "$DEVLOOP_ROOT"
  exit 0
fi
cache="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/flavordrake/devloop"
newest=""
if [[ -d "$cache" ]]; then
  newest="$(cd "$cache" && for v in */; do
      case "$v" in [0-9]*.[0-9]*.[0-9]*/) printf '%s\n' "${v%/}" ;; esac
    done | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)"
fi
if [[ -n "$newest" ]]; then
  echo "$cache/$newest"
else
  cd "$(dirname "$0")/.." && pwd
fi
