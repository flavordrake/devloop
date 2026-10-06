#!/usr/bin/env bash
# scripts/lib/repo-guard.sh — Shared repo safety functions
#
# Source this from any script that touches git state:
#   source "$SELF_DIR/lib/repo-guard.sh"
#
# The project is resolved from the CALLER'S cwd, not from this file's location:
# consumers symlink devloop's scripts (or run them from the plugin cache, which
# has no .git), and those must act on the project they were invoked in.
#
# Provides:
#   WORKTREE_ROOT     — top of the worktree the caller's cwd is in
#   REPO_ROOT         — the main checkout of that repo (not a linked worktree)
#   ensure_repo_root  — cd to REPO_ROOT, abort if repo is missing
#   is_main_repo      — test if a path is the main repo (not a worktree)
#   safe_rm_worktree  — rm -rf a worktree path ONLY if it's not the main repo
#   guard_cwd         — detect CWD drift and fix it

# _resolve_repo_root — print the main checkout for the cwd's repo. A linked
# worktree shares --git-common-dir with the main checkout (<main>/.git), so its
# parent is the main checkout in both cases. Rejected: --path-format=absolute,
# which needs git 2.31 (older Apple git lacks it); cd+pwd -P handles relative.
_resolve_repo_root() {
  local common
  common="$(git rev-parse --git-common-dir)" || {
    echo "FATAL: repo-guard: $(pwd) is not inside a git repository" >&2
    return 1
  }
  common="$(cd "$common" && pwd -P)"
  case "$common" in
    */.git) dirname "$common" ;;
    *)
      echo "FATAL: repo-guard: bare or unusual git dir $common (expected <repo>/.git)" >&2
      return 1
      ;;
  esac
}

# Empty on failure; ensure_repo_root then exits 99. Sourcing must not exit, so
# commands that need no checkout (comment, labels, ...) still run. git's stderr
# is dropped on the first call only: _resolve_repo_root reports the same failure.
WORKTREE_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || WORKTREE_ROOT=""
REPO_ROOT="$(_resolve_repo_root)" || REPO_ROOT=""

# Verify the main repo exists and cd to it
ensure_repo_root() {
  if [ -z "$REPO_ROOT" ] || [ ! -d "$REPO_ROOT/.git" ]; then
    echo "FATAL: main repo missing (REPO_ROOT='${REPO_ROOT}') — run from inside the project checkout" >&2
    exit 99
  fi
  cd "$REPO_ROOT"
}

# Test if a path is the main repo root (returns 0=yes, 1=no)
is_main_repo() {
  local abs_path
  abs_path="$(cd "$1" 2>/dev/null && pwd -P)" || return 1
  [ -n "$REPO_ROOT" ] && [ "$abs_path" = "$REPO_ROOT" ]
}

# Safe rm -rf that refuses to delete the main repo or anything outside
# <main>/.claude/worktrees/. Usage: safe_rm_worktree /path/to/worktree
safe_rm_worktree() {
  local target="$1" abs_target

  if [ ! -d "$target" ]; then
    return 0  # already gone
  fi
  if [ -z "$REPO_ROOT" ]; then
    echo "BLOCKED: repo-guard has no REPO_ROOT; refusing to delete $target" >&2
    return 1
  fi

  abs_target="$(cd "$target" && pwd -P)"

  if [ "$abs_target" = "$REPO_ROOT" ]; then
    echo "BLOCKED: refusing to delete main repo at $abs_target" >&2
    return 1
  fi

  case "$abs_target" in
    "$REPO_ROOT/.claude/worktrees/"?*)
      rm -rf "$abs_target"
      ;;
    *)
      echo "BLOCKED: refusing to delete $abs_target (not inside $REPO_ROOT/.claude/worktrees/)" >&2
      return 1
      ;;
  esac
}

# Detect and fix CWD drift (CWD is inside a deleted or stale worktree)
guard_cwd() {
  local cwd
  if ! cwd="$(pwd -P 2>/dev/null)" || [ ! -d "$cwd" ]; then
    echo "CWD drift detected: current directory no longer exists" >&2
    ensure_repo_root
    return 0
  fi

  case "$cwd" in
    "$REPO_ROOT/.claude/worktrees/"*)
      echo "CWD drift detected: inside worktree $cwd" >&2
      ensure_repo_root
      ;;
  esac
}
