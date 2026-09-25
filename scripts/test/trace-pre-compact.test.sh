#!/usr/bin/env bash
# Regression tests for hooks/trace-pre-compact.sh: the snapshot goes only to the session's own trace.
# Usage: scripts/test/trace-pre-compact.test.sh   (exit 0 = all pass)
set -euo pipefail

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/hooks/trace-pre-compact.sh"
DEVLOOP_TEST_TMP="$(mktemp -d -t devloop-test.XXXXXX)"
trap 'rm -rf "$DEVLOOP_TEST_TMP"' EXIT
# The caller's session exports this; tests control discovery explicitly.
unset CLAUDE_PROJECT_DIR

FAILS=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }

make_repo() {
  mkdir -p "$1/.traces/trace-fixture/logs"
  echo 'Active trace: `.traces/trace-fixture/`' > "$1/CLAUDE.md"
  echo "status: in-progress" > "$1/.traces/trace-fixture/TRACE.md"
}

# run_hook DIR — PreCompact payload with cwd DIR.
run_hook() {
  jq -n --arg cwd "$1" '{hook_event_name: "PreCompact", trigger: "auto", cwd: $cwd}' | "$HOOK" 2>/dev/null
}

# snapshot_count DIR — compact snapshots in DIR's fixture trace.
snapshot_count() {
  local snaps
  shopt -s nullglob
  snaps=("$1"/.traces/trace-fixture/logs/compact-*.md)
  shopt -u nullglob
  echo "${#snaps[@]}"
}

# 1. From a parent dir, an unrelated child repo's trace must not receive a snapshot.
mkdir -p "$DEVLOOP_TEST_TMP/scratch"
make_repo "$DEVLOOP_TEST_TMP/scratch/child"
run_hook "$DEVLOOP_TEST_TMP/scratch"
if [ "$(snapshot_count "$DEVLOOP_TEST_TMP/scratch/child")" -eq 0 ]; then
  pass no-child-write
else
  fail "no-child-write: snapshot written into child repo trace"
fi

# 2. From inside a repo with a trace, the snapshot is written there.
make_repo "$DEVLOOP_TEST_TMP/own"
run_hook "$DEVLOOP_TEST_TMP/own"
if [ "$(snapshot_count "$DEVLOOP_TEST_TMP/own")" -eq 1 ]; then
  pass own-trace-write
else
  fail "own-trace-write: no snapshot in own trace"
fi

if [ "$FAILS" -ne 0 ]; then
  echo "$FAILS case(s) failed"
  exit 1
fi
echo "All trace-pre-compact tests passed"
