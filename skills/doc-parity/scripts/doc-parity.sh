#!/usr/bin/env bash
# skills/doc-parity/scripts/doc-parity.sh: the mechanical layer of the
# doc-parity skill, both directions (docs-to-code.sh, then code-to-docs.sh)
# on the git toplevel of the caller's cwd.
# Usage: doc-parity.sh [--warn|--block] [--kinds k1,k2] [--root DIR] [--config FILE]
#        doc-parity.sh --list docs|research|code|user-text   (inputs for the
#          semantic audit: the doc set, and the user-facing text shipped in code)
#   --block (default) exits 1 when either direction has findings; --warn exits 0.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"
ARGS=("$@")
rc=0; dp_args "$@" || rc=$?
if [[ "$rc" -eq 3 ]]; then sed -n '2,8p' "$0"; exit 0; fi
if [[ "$rc" -ne 0 ]]; then exit "$rc"; fi

if [[ -n "$LIST" ]]; then
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/doc-parity.XXXXXX")"
  trap 'rm -rf "$WORK"' EXIT
  dp_init "$WORK" "$CONFIG"
  case "$LIST" in
    docs|research|code) cat "$WORK/$LIST" ;;
    user-text) awk -v g="$DP_USER_TEXT" "$DP_AWK_GLOB"'anyglob($0, g)' "$WORK/files" ;;
    *) echo "! --list takes docs|research|code|user-text" >&2; exit 2 ;;
  esac
  exit 0
fi

status=0
"$HERE/docs-to-code.sh" ${ARGS[@]+"${ARGS[@]}"} || status=1
"$HERE/code-to-docs.sh" ${ARGS[@]+"${ARGS[@]}"} || status=1
exit "$status"
