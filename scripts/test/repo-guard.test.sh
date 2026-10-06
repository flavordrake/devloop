#!/usr/bin/env bash
# Tests for scripts/lib/repo-guard.sh: the project resolves from the caller's
# cwd (main checkout, linked worktree, symlinked caller from another repo,
# outside any repo), and safe_rm_worktree only deletes agent worktrees.
# Usage: scripts/test/repo-guard.test.sh   (exit 0 = all pass)
set -euo pipefail

DEVLOOP="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$DEVLOOP/scripts/lib/repo-guard.sh"
T="$(cd "$(mktemp -d -t devloop-test.XXXXXX)" && pwd -P)"
trap 'rm -rf "$T"' EXIT

FAILS=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: expected '$3' got '$2'"; fi; }

g() { git -c user.name=test -c user.email=test@example.com "$@"; }

# probe DIR EXPR — source the guard with cwd DIR and print EXPR's value.
probe() { (cd "$1" && source "$GUARD" && eval "echo \"$2\""); }

mkdir -p "$T/proj/sub"
g -C "$T/proj" init -q
g -C "$T/proj" commit -q --allow-empty -m init
g -C "$T/proj" worktree add -q "$T/proj/.claude/worktrees/wt" -b wt

# 1. main checkout, from a subdirectory
check "main-root" "$(probe "$T/proj/sub" '$REPO_ROOT')" "$T/proj"
check "main-worktree-root" "$(probe "$T/proj/sub" '$WORKTREE_ROOT')" "$T/proj"

# 2. linked worktree: REPO_ROOT is still the main checkout
check "worktree-repo-root" "$(probe "$T/proj/.claude/worktrees/wt" '$REPO_ROOT')" "$T/proj"
check "worktree-worktree-root" "$(probe "$T/proj/.claude/worktrees/wt" '$WORKTREE_ROOT')" "$T/proj/.claude/worktrees/wt"

# 3. caller symlinks devloop's gh-ops.sh from another repo: it must act on that
# repo (version prints the caller repo's HEAD, not devloop's)
mkdir -p "$T/consumer/scripts"
g -C "$T/consumer" init -q
g -C "$T/consumer" commit -q --allow-empty -m consumer
ln -s "$DEVLOOP/scripts/gh-ops.sh" "$T/consumer/scripts/gh-ops.sh"
want="Code: $(git -C "$T/consumer" rev-parse --short HEAD)"
got="$(cd "$T/consumer" && GH_OPS_APP_PORT='' scripts/gh-ops.sh version)"
check "symlinked-caller-repo" "$got" "$want"

# 4. outside any repo: sourcing does not exit; ensure_repo_root exits 99
mkdir -p "$T/norepo"
check "norepo-root-empty" "$(probe "$T/norepo" '$REPO_ROOT' 2>/dev/null)" ""
rc=0
(cd "$T/norepo" && source "$GUARD" && ensure_repo_root) 2>/dev/null || rc=$?
check "norepo-ensure-exits-99" "$rc" "99"

# 5. is_main_repo
if (cd "$T/proj/.claude/worktrees/wt" && source "$GUARD" && is_main_repo "$T/proj"); then
  pass "is-main-repo-yes"
else
  fail "is-main-repo-yes"
fi
if (cd "$T/proj" && source "$GUARD" && is_main_repo "$T/proj/.claude/worktrees/wt"); then
  fail "is-main-repo-no"
else
  pass "is-main-repo-no"
fi

# 6. safe_rm_worktree: refuses main checkout and outside paths, deletes agent worktree
mkdir -p "$T/outside"
if (cd "$T/proj/.claude/worktrees/wt" && source "$GUARD" && safe_rm_worktree "$T/proj") 2>/dev/null; then
  fail "rm-refuses-main"
else
  pass "rm-refuses-main"
fi
if (cd "$T/proj" && source "$GUARD" && safe_rm_worktree "$T/outside") 2>/dev/null; then
  fail "rm-refuses-outside"
else
  if [ -d "$T/outside" ]; then pass "rm-refuses-outside"; else fail "rm-refuses-outside: deleted"; fi
fi
(cd "$T/proj" && source "$GUARD" && safe_rm_worktree "$T/proj/.claude/worktrees/wt")
if [ -d "$T/proj/.claude/worktrees/wt" ]; then fail "rm-deletes-worktree"; else pass "rm-deletes-worktree"; fi
if [ -d "$T/proj/.git" ]; then pass "rm-keeps-main"; else fail "rm-keeps-main"; fi

if [ "$FAILS" -gt 0 ]; then
  echo "$FAILS repo-guard test(s) failed"
  exit 1
fi
echo "All repo-guard tests passed"
