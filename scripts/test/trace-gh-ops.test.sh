#!/usr/bin/env bash
# Regression tests for hooks/trace-gh-ops.sh: gh-ops.log entries go only to the session's own trace.
# Usage: scripts/test/trace-gh-ops.test.sh   (exit 0 = all pass)
set -euo pipefail

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/hooks/trace-gh-ops.sh"
DEVLOOP_TEST_TMP="$(mktemp -d -t devloop-test.XXXXXX)"
trap 'rm -rf "$DEVLOOP_TEST_TMP"' EXIT
# The caller's session exports this; tests control discovery explicitly.
unset CLAUDE_PROJECT_DIR

FAILS=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }
# Grep exception from rules/command-hygiene.md.
count_ops() { grep -c -- "\] pr-create$" "$1" 2>/dev/null || true; }

make_repo() {
  mkdir -p "$1/.traces/trace-fixture/logs"
  echo 'Active trace: `.traces/trace-fixture/`' > "$1/CLAUDE.md"
  echo "status: in-progress" > "$1/.traces/trace-fixture/TRACE.md"
}

# run_hook DIR — PostToolUse:Bash payload for a gh-ops.sh pr-create call with cwd DIR.
run_hook() {
  jq -n --arg cwd "$1" '{
    hook_event_name: "PostToolUse", tool_name: "Bash", cwd: $cwd,
    tool_input: {command: "scripts/gh-ops.sh pr-create --title fixture"},
    tool_response: {stdout: "https://github.com/example/repo/pull/1"}
  }' | "$HOOK"
}

# 1. From a parent dir, an unrelated child repo's gh-ops.log must stay untouched.
mkdir -p "$DEVLOOP_TEST_TMP/scratch"
make_repo "$DEVLOOP_TEST_TMP/scratch/child"
run_hook "$DEVLOOP_TEST_TMP/scratch"
if [ ! -e "$DEVLOOP_TEST_TMP/scratch/child/.traces/trace-fixture/logs/gh-ops.log" ]; then
  pass no-child-write
else
  fail "no-child-write: gh-ops.log written into child repo trace"
fi

# 2. From inside a repo with a trace, one pr-create entry is appended there.
make_repo "$DEVLOOP_TEST_TMP/own"
run_hook "$DEVLOOP_TEST_TMP/own"
if [ "$(count_ops "$DEVLOOP_TEST_TMP/own/.traces/trace-fixture/logs/gh-ops.log")" = "1" ]; then
  pass own-trace-write
else
  fail "own-trace-write: no pr-create entry in own trace"
fi

if [ "$FAILS" -ne 0 ]; then
  echo "$FAILS case(s) failed"
  exit 1
fi
echo "All trace-gh-ops tests passed"
