#!/usr/bin/env bash
# Regression tests for hooks/enforce-hygiene.sh: context-only nudge, never a permission decision.
# Usage: scripts/test/enforce-hygiene.test.sh   (exit 0 = all pass)
set -euo pipefail

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/hooks/enforce-hygiene.sh"
FAILS=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }

# run_hook COMMAND — PreToolUse:Bash payload; prints hook stdout.
run_hook() {
  jq -n --arg c "$1" '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $c}}' | "$HOOK"
}

# 1. Pipes, redirects, chains, heredocs, /dev/null: no output at all.
for cmd in 'cat x | grep y' 'ls > out.txt' 'make && make test' 'a; b' 'cat <<EOF' 'ls 2>/dev/null'; do
  out=$(run_hook "$cmd")
  if [ -z "$out" ]; then pass "silent: $cmd"; else fail "silent: $cmd produced: $out"; fi
done

# 2. Raw gh: additionalContext only, no permissionDecision anywhere.
out=$(run_hook 'gh pr list')
if jq -e '.hookSpecificOutput.additionalContext | test("gh")' <<<"$out" >/dev/null; then
  pass "raw-gh context"
else
  fail "raw-gh context missing: $out"
fi
if jq -e '[.. | objects | has("permissionDecision")] | any' <<<"$out" >/dev/null; then
  fail "raw-gh emitted permissionDecision: $out"
else
  pass "raw-gh no permissionDecision"
fi

# 3. gh not at command start is not flagged.
out=$(run_hook 'echo gh pr list')
if [ -z "$out" ]; then pass "non-leading gh silent"; else fail "non-leading gh: $out"; fi

if [ "$FAILS" -ne 0 ]; then
  echo "$FAILS case(s) failed"
  exit 1
fi
echo "All enforce-hygiene tests passed"
