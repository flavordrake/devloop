#!/usr/bin/env bash
# Tests for scripts/gh-ops.sh argument parsing and integrate's flow, with gh
# stubbed on PATH (no network), plus scripts/lib/pr-closes.sh.
# Usage: scripts/test/gh-ops.test.sh   (exit 0 = all pass)
set -euo pipefail

DEVLOOP="$(cd "$(dirname "$0")/../.." && pwd)"
GH_OPS="$DEVLOOP/scripts/gh-ops.sh"
T="$(cd "$(mktemp -d -t devloop-test.XXXXXX)" && pwd -P)"
trap 'rm -rf "$T"' EXIT

FAILS=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }
g() { git -c user.name=test -c user.email=test@example.com "$@"; }

# Stub gh: log each call's argv on one line, answer the reads integrate makes.
mkdir -p "$T/bin"
cat > "$T/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
case "$*" in
  "pr view"*"--json baseRefName"*) echo main ;;
  "pr view"*"--json headRefOid"*) echo abc123 ;;
  "pr view"*"--json headRefName"*) echo feature ;;
  "pr view"*"--json mergeStateStatus"*) echo CLEAN ;;
  "pr view"*"--json body"*) echo "${GH_PR_BODY:-}" ;;
  "api repos/{owner}/{repo}/compare/"*) echo "${GH_BEHIND:-0}" ;;
  "issue view"*"--json labels --jq"*) echo "${GH_HAS_LABEL:-false}" ;;
  "issue view"*"--json title,body,labels"*) printf '**title %s**\n\nbody\n' "$3" ;;
esac
STUB
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH"
export GH_LOG="$T/gh.log"

# Caller repo with an origin, so fetch/prune in integrate run for real.
g init -q --bare -b main "$T/origin.git"
g clone -q "$T/origin.git" "$T/repo" 2>/dev/null
g -C "$T/repo" commit -q --allow-empty -m init
g -C "$T/repo" push -q origin main

# run ARGS... — run gh-ops in the caller repo; sets RC, OUT (stdout), and resets the log.
run() {
  : > "$GH_LOG"
  RC=0
  OUT="$(cd "$T/repo" && "$GH_OPS" "$@" 2>"$T/err")" || RC=$?
}
expect_call() {
  if grep -qxF -- "$2" "$GH_LOG"; then pass "$1"; else fail "$1: no gh call '$2' in: $(tr '\n' '|' < "$GH_LOG")"; fi
}
expect_no_call() {
  if grep -qF -- "$2" "$GH_LOG"; then fail "$1: unexpected gh call matching '$2'"; else pass "$1"; fi
}
expect_rc() { if [ "$RC" = "$2" ]; then pass "$1"; else fail "$1: rc=$RC want $2 ($(cat "$T/err"))"; fi; }

run
expect_rc "no-args-usage" 1
run bogus
expect_rc "unknown-command" 1

run labels 5 --add a --rm b
expect_rc "labels-rc" 0
expect_call "labels-args" "issue edit 5 --add-label a --remove-label b"
run labels 5
expect_rc "labels-none-errors" 1
expect_no_call "labels-none-no-gh" "issue edit"

run comment 5 --body "hello there"
expect_call "comment-args" "issue comment 5 --body hello there"

run label-create needs-spec --color ff0000 --description "Needs a spec"
expect_call "label-create-args" "label create needs-spec --color ff0000 --description Needs a spec"

run pr-edit 3 --title T --body B
expect_call "pr-edit-args" "pr edit 3 --body B --title T"
run pr-edit 3
expect_rc "pr-edit-empty-errors" 1

run pr-view 3 --json state
expect_call "pr-view-passthrough" "pr view 3 --json state"

run release v1.0.0 --title "One" a.zip
expect_call "release-args" "release create v1.0.0 --title One --generate-notes a.zip"

run fetch-issues 1,2
case "$OUT" in
  *"## Issue #1"*"## Issue #2"*) pass "fetch-issues-stdout" ;;
  *) fail "fetch-issues-stdout: $OUT" ;;
esac
case "$OUT" in *"---"*) fail "fetch-issues-no-separator" ;; *) pass "fetch-issues-no-separator" ;; esac
run fetch-issues 7 --out "$T/issues.md"
if grep -q "## Issue #7" "$T/issues.md" && [ -z "$OUT" ]; then pass "fetch-issues-out"; else fail "fetch-issues-out"; fi

run integrate 9
expect_rc "integrate-needs-two-args" 1

# integrate from a feature checkout: up to date, PR closes the issue.
g -C "$T/repo" checkout -q -b mywork
GH_PR_BODY="Closes #7" GH_BEHIND=0 run integrate 9 7
expect_rc "integrate-rc" 0
expect_no_call "integrate-no-update-when-current" "pr update-branch"
expect_call "integrate-merges" "pr merge 9 --merge --delete-branch"
expect_call "integrate-closes-issue" "issue close 7 --comment Fixed in PR #9"
branch="$(git -C "$T/repo" rev-parse --abbrev-ref HEAD)"
if [ "$branch" = "mywork" ]; then pass "integrate-keeps-checkout"; else fail "integrate-keeps-checkout: on $branch"; fi

# behind base: updated server-side; Refs-only body leaves the issue open.
GH_PR_BODY="Refs #7" GH_BEHIND=2 run integrate 9 7 --squash
expect_call "integrate-updates-branch" "pr update-branch 9"
expect_call "integrate-squash" "pr merge 9 --squash --delete-branch"
expect_no_call "integrate-refs-keeps-open" "issue close"

# pr-merge: free local branch is deleted and gh deletes the remote one.
g -C "$T/repo" branch feature
run pr-merge 4
expect_call "pr-merge-delete-branch" "pr merge 4 --squash --delete-branch"
if git -C "$T/repo" show-ref --verify --quiet refs/heads/feature; then fail "pr-merge-deletes-local"; else pass "pr-merge-deletes-local"; fi

# pr-merge with a worktree outside .claude/worktrees holding the branch (#125):
# no --delete-branch (it would fail after merging), remote deleted via API.
g -C "$T/repo" worktree add -q "$T/held" -b feature
run pr-merge 4
expect_rc "pr-merge-held-rc" 0
expect_call "pr-merge-held-no-delete" "pr merge 4 --squash"
expect_call "pr-merge-held-remote-delete" "api -X DELETE repos/{owner}/{repo}/git/refs/heads/feature"
if [ -d "$T/held" ]; then pass "pr-merge-held-keeps-worktree"; else fail "pr-merge-held-keeps-worktree"; fi

# pr-closes keyword matching
source "$DEVLOOP/scripts/lib/pr-closes.sh"
for body in "Closes #7" "fixes: #7" "Resolved #7." "text
Fix #7"; do
  if pr_closes_issue "$body" 7; then pass "closes: $body"; else fail "closes: $body"; fi
done
for body in "Refs #7" "Closes #70" "prefix#7" "unfixes #7"; do
  if pr_closes_issue "$body" 7; then fail "not-closes: $body"; else pass "not-closes: $body"; fi
done
if pr_closes_issue "Closes #0" 0; then fail "issue-0-never"; else pass "issue-0-never"; fi

if [ "$FAILS" -gt 0 ]; then
  echo "$FAILS gh-ops test(s) failed"
  exit 1
fi
echo "All gh-ops tests passed"
