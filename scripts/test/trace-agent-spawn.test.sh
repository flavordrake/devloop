#!/usr/bin/env bash
# Regression tests for hooks/trace-agent-spawn.sh: agents.log entries go only to the session's own trace.
# Usage: scripts/test/trace-agent-spawn.test.sh   (exit 0 = all pass)
set -euo pipefail

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/hooks/trace-agent-spawn.sh"
DEVLOOP_TEST_TMP="$(mktemp -d -t devloop-test.XXXXXX)"
trap 'rm -rf "$DEVLOOP_TEST_TMP"' EXIT
# The caller's session exports this; tests control discovery explicitly.
unset CLAUDE_PROJECT_DIR

FAILS=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }
# Grep exception from rules/command-hygiene.md.
count_spawns() { grep -c -- "agent-spawn" "$1" 2>/dev/null || true; }

make_repo() {
  mkdir -p "$1/.traces/trace-fixture/logs"
  echo 'Active trace: `.traces/trace-fixture/`' > "$1/CLAUDE.md"
  echo "status: in-progress" > "$1/.traces/trace-fixture/TRACE.md"
}

# run_hook DIR — SubagentStart payload with cwd DIR; stdout is the hook's JSON.
run_hook() {
  jq -n --arg cwd "$1" '{hook_event_name: "SubagentStart", agent_type: "general-purpose", cwd: $cwd}' | "$HOOK" >/dev/null
}

# 1. From a parent dir, an unrelated child repo's agents.log must stay untouched.
mkdir -p "$DEVLOOP_TEST_TMP/scratch"
make_repo "$DEVLOOP_TEST_TMP/scratch/child"
run_hook "$DEVLOOP_TEST_TMP/scratch"
if [ ! -e "$DEVLOOP_TEST_TMP/scratch/child/.traces/trace-fixture/logs/agents.log" ]; then
  pass no-child-write
else
  fail "no-child-write: agents.log written into child repo trace"
fi

# 2. From inside a repo with a trace, one agent-spawn line is appended there.
make_repo "$DEVLOOP_TEST_TMP/own"
run_hook "$DEVLOOP_TEST_TMP/own"
if [ "$(count_spawns "$DEVLOOP_TEST_TMP/own/.traces/trace-fixture/logs/agents.log")" = "1" ]; then
  pass own-trace-write
else
  fail "own-trace-write: no agent-spawn line in own trace"
fi

if [ "$FAILS" -ne 0 ]; then
  echo "$FAILS case(s) failed"
  exit 1
fi
echo "All trace-agent-spawn tests passed"
