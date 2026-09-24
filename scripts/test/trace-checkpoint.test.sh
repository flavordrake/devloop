#!/usr/bin/env bash
# Regression tests for scripts/trace-checkpoint.sh.
# Usage: scripts/test/trace-checkpoint.test.sh   (exit 0 = all pass)
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/trace-checkpoint.sh"
DEVLOOP_TEST_TMP="$(mktemp -d -t devloop-test.XXXXXX)"
trap 'rm -rf "$DEVLOOP_TEST_TMP"' EXIT
# The caller's session exports this; tests control discovery explicitly.
unset CLAUDE_PROJECT_DIR

FAILS=0

# run_case NAME EXPECTED_PREFIX DIR [ENV...] — runs the script in DIR, asserts exit 0 and output prefix.
run_case() {
  local name="$1" expected="$2" dir="$3"
  shift 3
  local out rc=0
  out=$(env -C "$dir" "$@" "$SCRIPT" test 2>&1) || rc=$?
  if [ "$rc" -eq 0 ] && [[ "$out" == "$expected"* ]]; then
    echo "PASS $name: $out"
  else
    echo "FAIL $name (exit $rc): $out"
    FAILS=$((FAILS + 1))
  fi
}

# make_repo DIR — a project whose CLAUDE.md points at a trace with zero-match logs and no pivots.
make_repo() {
  local root="$1"
  mkdir -p "$root/.traces/trace-fixture/logs" "$root/.traces/trace-fixture/strategy"
  echo 'Active trace: `.traces/trace-fixture/`' > "$root/CLAUDE.md"
  echo "status: in-progress" > "$root/.traces/trace-fixture/TRACE.md"
  echo "unrelated line" > "$root/.traces/trace-fixture/logs/agents.log"
  echo "unrelated line" > "$root/.traces/trace-fixture/logs/gh-ops.log"
}

# 1. Zero-match counted logs must yield a status line, not "0\n0: syntax error".
make_repo "$DEVLOOP_TEST_TMP/zero"
run_case zero-matches "TRACE (test): 0 decisions, 0 commits, 0 agents" "$DEVLOOP_TEST_TMP/zero"

# 2. Unrelated child repo must not be picked up by a sibling/child glob.
mkdir -p "$DEVLOOP_TEST_TMP/scratch"
make_repo "$DEVLOOP_TEST_TMP/scratch/child"
run_case no-child-glob "TRACE: no CLAUDE.md found" "$DEVLOOP_TEST_TMP/scratch"

# 3. Walk up from a subdirectory to the nearest CLAUDE.md.
mkdir -p "$DEVLOOP_TEST_TMP/zero/src/deep"
run_case walk-up "TRACE (test):" "$DEVLOOP_TEST_TMP/zero/src/deep"

# 4. CLAUDE_PROJECT_DIR wins over cwd.
run_case project-dir "TRACE (test):" "$DEVLOOP_TEST_TMP/scratch" "CLAUDE_PROJECT_DIR=$DEVLOOP_TEST_TMP/zero"

# 5. CLAUDE.md without a trace reference reports that, rather than dying on grep's exit 1.
mkdir -p "$DEVLOOP_TEST_TMP/notrace"
echo "no trace here" > "$DEVLOOP_TEST_TMP/notrace/CLAUDE.md"
run_case no-trace-ref "TRACE: no active trace in CLAUDE.md" "$DEVLOOP_TEST_TMP/notrace"

if [ "$FAILS" -ne 0 ]; then
  echo "$FAILS case(s) failed"
  exit 1
fi
echo "All trace-checkpoint tests passed"
