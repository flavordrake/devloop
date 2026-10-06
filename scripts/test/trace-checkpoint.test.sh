#!/usr/bin/env bash
# Regression tests for scripts/trace-checkpoint.sh and hooks/trace-checkpoint.sh.
# Usage: scripts/test/trace-checkpoint.test.sh   (exit 0 = all pass)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/trace-checkpoint.sh"
HOOK="$ROOT/hooks/trace-checkpoint.sh"
DEVLOOP_TEST_TMP="$(mktemp -d -t devloop-test.XXXXXX)"
trap 'rm -rf "$DEVLOOP_TEST_TMP"' EXIT
# The caller's session exports this; tests control discovery explicitly.
unset CLAUDE_PROJECT_DIR

FAILS=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }

# run_case NAME EXPECTED_PREFIX DIR [ENV...] — runs the script in DIR, asserts exit 0 and output prefix.
# An empty EXPECTED_PREFIX asserts empty output.
run_case() {
  local name="$1" expected="$2" dir="$3"
  shift 3
  local out rc=0
  out=$(cd "$dir" && env "$@" "$SCRIPT" test 2>&1) || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "$name (exit $rc): $out"
  elif [ -z "$expected" ] && [ -n "$out" ]; then
    fail "$name expected silence, got: $out"
  elif [[ "$out" != "$expected"* ]]; then
    fail "$name: $out"
  else
    pass "$name: $out"
  fi
}

# make_repo DIR — a git project whose CLAUDE.md points at an open trace with no pivots.
make_repo() {
  local root="$1"
  mkdir -p "$root/.traces/trace-fixture/logs" "$root/.traces/trace-fixture/strategy"
  echo 'Active trace: `.traces/trace-fixture/`' > "$root/CLAUDE.md"
  echo "status: in-progress" > "$root/.traces/trace-fixture/TRACE.md"
  git -C "$root" init -q
}

# 1. Open trace, no commits: status line.
make_repo "$DEVLOOP_TEST_TMP/zero"
run_case zero "TRACE (test): 0 pivots, 0 commits" "$DEVLOOP_TEST_TMP/zero"

# 2. Commits are counted once (no doubled "decisions" total).
git -C "$DEVLOOP_TEST_TMP/zero" -c user.name=t -c user.email=t@t commit -q --allow-empty -m one
run_case one-commit "TRACE (test): 0 pivots, 1 commits" "$DEVLOOP_TEST_TMP/zero"

# 3. Unrelated child repo must not be picked up: no CLAUDE.md means silence.
mkdir -p "$DEVLOOP_TEST_TMP/scratch"
make_repo "$DEVLOOP_TEST_TMP/scratch/child"
run_case no-claude-md "" "$DEVLOOP_TEST_TMP/scratch"

# 4. Walk up from a subdirectory to the nearest CLAUDE.md.
mkdir -p "$DEVLOOP_TEST_TMP/zero/src/deep"
run_case walk-up "TRACE (test):" "$DEVLOOP_TEST_TMP/zero/src/deep"

# 5. CLAUDE_PROJECT_DIR wins over cwd.
run_case project-dir "TRACE (test):" "$DEVLOOP_TEST_TMP/scratch" "CLAUDE_PROJECT_DIR=$DEVLOOP_TEST_TMP/zero"

# 6. CLAUDE.md without a trace reference: silence.
mkdir -p "$DEVLOOP_TEST_TMP/notrace"
echo "no trace here" > "$DEVLOOP_TEST_TMP/notrace/CLAUDE.md"
run_case no-trace-ref "" "$DEVLOOP_TEST_TMP/notrace"

# 7. Closed trace: silence, no STOP.
make_repo "$DEVLOOP_TEST_TMP/closed"
echo "status: success" > "$DEVLOOP_TEST_TMP/closed/.traces/trace-fixture/TRACE.md"
run_case closed "" "$DEVLOOP_TEST_TMP/closed"

# 8. Missing TRACE.md: silence, no STOP.
make_repo "$DEVLOOP_TEST_TMP/missing"
rm "$DEVLOOP_TEST_TMP/missing/.traces/trace-fixture/TRACE.md"
run_case missing "" "$DEVLOOP_TEST_TMP/missing"

# Hook: fires only on a parsed `git commit`.
# hook_case NAME COMMAND EXPECT(fire|silent)
hook_case() {
  local out
  out=$(jq -n --arg c "$2" --arg cwd "$DEVLOOP_TEST_TMP/zero" '{tool_input: {command: $c}, cwd: $cwd}' | "$HOOK")
  if [ "$3" = fire ] && jq -e '.hookSpecificOutput.additionalContext | startswith("TRACE (commit)")' <<<"$out" >/dev/null; then
    pass "hook $1"
  elif [ "$3" = silent ] && [ -z "$out" ]; then
    pass "hook $1"
  else
    fail "hook $1 (want $3): $out"
  fi
}
hook_case commit 'git commit -m x' fire
hook_case commit-C 'git -C /tmp/x commit -m x' fire
hook_case chained 'git add . && git commit -m x' fire
hook_case env-prefix 'GIT_AUTHOR_NAME=a git commit -m x' fire
hook_case cat-gh-ops 'cat scripts/gh-ops.sh' silent
hook_case echo-commit 'echo "git commit"' silent
hook_case git-log 'git log --grep commit' silent
hook_case push 'git push' silent

if [ "$FAILS" -ne 0 ]; then
  echo "$FAILS case(s) failed"
  exit 1
fi
echo "All trace-checkpoint tests passed"
