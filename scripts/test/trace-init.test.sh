#!/usr/bin/env bash
# Regression tests for scripts/trace-init.sh: records the Active TRACE line, refuses
# to overwrite an existing one unless --force (a consumer may hand-maintain a
# multi-arc line, see trace-locate.sh).
# Usage: scripts/test/trace-init.test.sh   (exit 0 = all pass)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/trace-init.sh"
T="$(mktemp -d -t devloop-test.XXXXXX)"
trap 'rm -rf "$T"' EXIT
unset CLAUDE_PROJECT_DIR

FAILS=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }

mkdir -p "$T/repo"
git -C "$T/repo" init -q
echo "@AGENTS.md" > "$T/repo/CLAUDE.md"

# 1. Fresh project: trace created and recorded.
rc=0; out=$(cd "$T/repo" && "$SCRIPT" first 2>&1) || rc=$?
if [ "$rc" -eq 0 ] && grep -q '^> \*\*Active TRACE\*\*: `.traces/trace-first-' "$T/repo/CLAUDE.md"; then pass "init records Active TRACE"; else fail "init ($rc): $out"; fi
first_line=$(grep '^> \*\*Active TRACE\*\*' "$T/repo/CLAUDE.md")

# 2. Existing line: refused, untouched, no new trace dir.
rc=0; out=$(cd "$T/repo" && "$SCRIPT" second 2>&1) || rc=$?
if [ "$rc" -ne 0 ] && [[ "$out" == *"Refusing"* ]]; then pass "second init refused"; else fail "second init ($rc): $out"; fi
if [ "$(grep '^> \*\*Active TRACE\*\*' "$T/repo/CLAUDE.md")" = "$first_line" ]; then pass "existing line kept"; else fail "existing line changed"; fi
if [ -z "$(find "$T/repo/.traces" -maxdepth 1 -name 'trace-second-*')" ]; then pass "no trace dir on refusal"; else fail "trace dir created on refusal"; fi

# 3. A narrative multi-arc line counts as existing.
echo "> **Active TRACE**: arc 2, .traces/trace-first-x (arc 1 .traces/trace-zero/ closed)" > "$T/repo/CLAUDE.md"
rc=0; (cd "$T/repo" && "$SCRIPT" third >/dev/null 2>&1) || rc=$?
if [ "$rc" -ne 0 ]; then pass "narrative line refused"; else fail "narrative line overwritten"; fi

# 4. --force replaces it, in either argument position.
rc=0; out=$(cd "$T/repo" && "$SCRIPT" fourth --force 2>&1) || rc=$?
if [ "$rc" -eq 0 ] && [ "$(grep -c '^> \*\*Active TRACE\*\*' "$T/repo/CLAUDE.md")" = 1 ] && grep -q 'trace-fourth-' "$T/repo/CLAUDE.md"; then pass "--force replaces"; else fail "--force ($rc): $out $(cat "$T/repo/CLAUDE.md")"; fi

# 5. Usage error without a slug.
rc=0; (cd "$T/repo" && "$SCRIPT" --force >/dev/null 2>&1) || rc=$?
if [ "$rc" -ne 0 ]; then pass "no slug is an error"; else fail "no slug accepted"; fi

if [ "$FAILS" -ne 0 ]; then
  echo "$FAILS case(s) failed"
  exit 1
fi
echo "All trace-init tests passed"
