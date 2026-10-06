#!/usr/bin/env bash
# scripts/gh-ops.sh — Common GitHub issue operations
#
# Wraps gh issue/pr commands so Claude Code can approve a single
# `scripts/gh-ops.sh` call instead of per-command approval for
# compound label/comment operations.
#
# Subcommands:
#   comment ISSUE --body-file FILE        Add comment from file
#   comment ISSUE --body "TEXT"           Add comment from string
#   comments ISSUE                        Print an issue's comments
#   labels  ISSUE [--add L ...] [--rm L ...]  Edit labels
#   label-create NAME [--color HEX] [--description TEXT]  Create a repo label
#   close   ISSUE [--comment "TEXT"]      Close with optional comment
#   close   ISSUE [--body-file FILE]      Close with comment from file
#   reopen  ISSUE [--comment "TEXT"]      Reopen with optional comment
#   search  QUERY [LIMIT]                 Search open issues, JSON output
#   version                               Print code hash (+ app version if GH_OPS_APP_PORT)
#   pr-create --head BRANCH --title T --body-file F [--label L ...]  Create PR
#   pr-edit   PR_NUM [--title T] [--body-file F] [--body TEXT]  Edit an open PR
#   pr-view   PR_NUM [gh pr view flags]   Read-only PR state
#   pr-merge  PR_NUM [--squash|--merge|--rebase]  Merge and delete branch
#   pr-close  PR_NUM [--comment "TEXT"]   Close PR with optional comment
#   integrate PR_NUM ISSUE_NUM [--merge|--squash|--rebase]  Merge PR, close issue, update local base
#   delegate  ISSUE_NUM [--label L ...]   Label bot, audit comment, prune stale refs
#   fetch-issues N1,N2,N3 [--out FILE]   Print issue bodies (stdout, or FILE)
#   release TAG --title T [--notes-file F] [--target SHA] [ASSET ...]  Create a GitHub release (+ tag) with optional assets
#
# Acts on the repo of the caller's cwd, also when symlinked into a project or
# run from the plugin cache. All progress goes to stderr, actionable output to
# stdout.

set -euo pipefail

# Resolve this script's real directory even when invoked via a symlink
# (projects symlink devloop's copy), so sourced libs/helpers are found.
SELF_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

# Load repo guard for safe worktree operations
source "$SELF_DIR/lib/repo-guard.sh"

usage() {
  echo "Usage: gh-ops.sh <command> [args]" >&2
  echo "Commands: comment, comments, labels, label-create, close, reopen, search, version, pr-create, pr-edit, pr-view, pr-merge, pr-close, integrate, delegate, fetch-issues, release" >&2
  exit 1
}

[ $# -ge 1 ] || usage

CMD="$1"; shift

# _worktree_holding BRANCH — print the path of every worktree that has BRANCH checked out.
_worktree_holding() {
  git worktree list --porcelain \
    | awk -v b="refs/heads/$1" '/^worktree /{p=substr($0, 10)} /^branch /{if($2==b) print p}'
}

# _issue_has_label ISSUE LABEL — jq instead of `| grep -q`, which can SIGPIPE gh under pipefail.
_issue_has_label() {
  [ "$(gh issue view "$1" --json labels --jq "any(.labels[]; .name == \"$2\")")" = "true" ]
}

# _cleanup_pr_worktree PR_NUM — remove agent worktrees holding the PR branch and
# the local branch before merge. Sets PR_HEAD_BRANCH, and WORKTREE_HELD=1 when a
# worktree outside .claude/worktrees/ (or the main checkout) still holds the
# branch, so the caller must not ask `gh pr merge` to --delete-branch: that
# fails the same way and exits 1 although the merge succeeded (#125, upstreamed
# from opsurface/mobiharness). Called plainly, not in `if`, so set -e applies.
WORKTREE_HELD=0
PR_HEAD_BRANCH=""
_cleanup_pr_worktree() {
  local wt
  PR_HEAD_BRANCH=$(gh pr view "$1" --json headRefName --jq '.headRefName')
  while IFS= read -r wt; do
    [ -n "$wt" ] || continue
    # safe_rm_worktree refuses (and says why) for the main checkout or paths
    # outside .claude/worktrees/; that worktree then keeps holding the branch.
    if ! safe_rm_worktree "$wt"; then
      WORKTREE_HELD=1
    fi
  done < <(_worktree_holding "$PR_HEAD_BRANCH")
  git worktree prune
  if [ "$WORKTREE_HELD" -eq 1 ]; then
    echo "Skipping local branch deletion — worktree holds it (cleanup deferred to release)" >&2
  elif git show-ref --verify --quiet "refs/heads/${PR_HEAD_BRANCH}"; then
    git branch -D "$PR_HEAD_BRANCH"
  fi
}

# _update_local_branch BRANCH — fast-forward the local BRANCH to origin without
# switching any checkout: ff-merge inside the worktree that has it checked out,
# else move the ref with a fetch refspec (git rejects non-fast-forward).
_update_local_branch() {
  local branch="$1" holder
  git fetch origin
  holder="$(_worktree_holding "$branch")"
  holder="${holder%%$'\n'*}"
  if [ -n "$holder" ]; then
    if ! git -C "$holder" merge --ff-only "origin/${branch}"; then
      echo "warning: ${branch} in ${holder} did not fast-forward; local ${branch} may be stale" >&2
    fi
  elif git show-ref --verify --quiet "refs/heads/${branch}"; then
    if ! git fetch origin "${branch}:${branch}"; then
      echo "warning: local ${branch} did not fast-forward; it may be stale" >&2
    fi
  fi
}

case "$CMD" in
  comment)
    [ $# -ge 1 ] || { echo "Error: comment requires ISSUE number" >&2; exit 1; }
    ISSUE="$1"; shift
    BODY=""
    BODY_FILE=""
    while [[ $# -gt 0 ]]; do
      case $1 in
        --body) BODY="$2"; shift 2 ;;
        --body-file) BODY_FILE="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
      esac
    done
    if [ -n "$BODY_FILE" ]; then
      BODY=$(cat "$BODY_FILE")
    elif [ -z "$BODY" ] && [ ! -t 0 ]; then
      BODY=$(cat)
    fi
    [ -n "$BODY" ] || { echo "Error: provide --body, --body-file, or pipe stdin" >&2; exit 1; }
    echo "Commenting on #${ISSUE}" >&2
    gh issue comment "$ISSUE" --body "$BODY"
    ;;

  labels)
    [ $# -ge 1 ] || { echo "Error: labels requires ISSUE number" >&2; exit 1; }
    ISSUE="$1"; shift
    ADD_LABELS=()
    RM_LABELS=()
    while [[ $# -gt 0 ]]; do
      case $1 in
        --add) ADD_LABELS+=("$2"); shift 2 ;;
        --rm|--remove) RM_LABELS+=("$2"); shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
      esac
    done
    ARGS=()
    for l in "${ADD_LABELS[@]+"${ADD_LABELS[@]}"}"; do
      ARGS+=(--add-label "$l")
    done
    for l in "${RM_LABELS[@]+"${RM_LABELS[@]}"}"; do
      ARGS+=(--remove-label "$l")
    done
    [ ${#ARGS[@]} -gt 0 ] || { echo "Error: provide --add or --rm labels" >&2; exit 1; }
    echo "Labels #${ISSUE}: +[${ADD_LABELS[*]+"${ADD_LABELS[*]}"}] -[${RM_LABELS[*]+"${RM_LABELS[*]}"}]" >&2
    gh issue edit "$ISSUE" "${ARGS[@]}"
    ;;

  label-create)
    # Upstreamed from exhand.
    [ $# -ge 1 ] || { echo "Error: label-create requires NAME" >&2; exit 1; }
    NAME="$1"; shift
    ARGS=()
    while [[ $# -gt 0 ]]; do
      case $1 in
        --color) ARGS+=(--color "$2"); shift 2 ;;
        --description) ARGS+=(--description "$2"); shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
      esac
    done
    echo "Creating label ${NAME}" >&2
    gh label create "$NAME" "${ARGS[@]+"${ARGS[@]}"}"
    ;;

  close)
    [ $# -ge 1 ] || { echo "Error: close requires ISSUE number" >&2; exit 1; }
    ISSUE="$1"; shift
    BODY=""
    BODY_FILE=""
    while [[ $# -gt 0 ]]; do
      case $1 in
        --comment|--body) BODY="$2"; shift 2 ;;
        --body-file) BODY_FILE="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
      esac
    done
    if [ -n "$BODY_FILE" ]; then
      BODY=$(cat "$BODY_FILE")
    fi
    echo "Closing #${ISSUE}" >&2
    if [ -n "$BODY" ]; then
      gh issue close "$ISSUE" --comment "$BODY"
    else
      gh issue close "$ISSUE"
    fi
    ;;

  reopen)
    [ $# -ge 1 ] || { echo "Error: reopen requires ISSUE number" >&2; exit 1; }
    ISSUE="$1"; shift
    BODY=""
    BODY_FILE=""
    while [[ $# -gt 0 ]]; do
      case $1 in
        --comment|--body) BODY="$2"; shift 2 ;;
        --body-file) BODY_FILE="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
      esac
    done
    if [ -n "$BODY_FILE" ]; then
      BODY=$(cat "$BODY_FILE")
    fi
    echo "Reopening #${ISSUE}" >&2
    if [ -n "$BODY" ]; then
      gh issue reopen "$ISSUE" --comment "$BODY"
    else
      gh issue reopen "$ISSUE"
    fi
    ;;

  search)
    [ $# -ge 1 ] || { echo "Error: search requires QUERY" >&2; exit 1; }
    gh issue list --search "$1" --state open --json number,title --limit "${2:-5}"
    ;;

  comments)
    # Print an issue's comments (author, timestamp, body) — fetch-issues only
    # returns the body, so design comments need this. Read-only.
    [ $# -ge 1 ] || { echo "Error: comments requires ISSUE_NUM" >&2; exit 1; }
    gh issue view "$1" --json comments \
      --jq '.comments[] | "### \(.author.login) @ \(.createdAt)\n\n\(.body)\n"'
    ;;

  version)
    # Outside a checkout there is no hash; "unknown" is the honest answer.
    CODE_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    # Optional app-version probe (project-specific). Set GH_OPS_APP_PORT to enable.
    PORT="${GH_OPS_APP_PORT:-}"
    if [ -n "$PORT" ]; then
      # A down server is a normal answer here, reported as such.
      SERVER_META=$(curl -sf --max-time 3 "http://localhost:${PORT}/" 2>/dev/null \
        | sed -n 's/.*app-version"[[:space:]]*content="\([^"]*\)".*/\1/p') || SERVER_META=""
      echo "Code: ${CODE_HASH} | Server: ${SERVER_META:-server not running}"
    else
      echo "Code: ${CODE_HASH}"
    fi
    ;;

  pr-create)
    HEAD=""
    TITLE=""
    BODY=""
    BODY_FILE=""
    PR_LABELS=()
    while [[ $# -gt 0 ]]; do
      case $1 in
        --head) HEAD="$2"; shift 2 ;;
        --title) TITLE="$2"; shift 2 ;;
        --body) BODY="$2"; shift 2 ;;
        --body-file) BODY_FILE="$2"; shift 2 ;;
        --label) PR_LABELS+=("$2"); shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
      esac
    done
    [ -n "$HEAD" ] || { echo "Error: --head required" >&2; exit 1; }
    [ -n "$TITLE" ] || { echo "Error: --title required" >&2; exit 1; }
    if [ -n "$BODY_FILE" ]; then
      BODY=$(cat "$BODY_FILE")
    elif [ -z "$BODY" ]; then
      BODY="Bot PR for ${HEAD}"
    fi
    ARGS=(--head "$HEAD" --title "$TITLE" --body "$BODY")
    for l in "${PR_LABELS[@]+"${PR_LABELS[@]}"}"; do
      ARGS+=(--label "$l")
    done
    echo "Creating PR: ${TITLE}" >&2
    gh pr create "${ARGS[@]}"
    ;;

  pr-merge)
    [ $# -ge 1 ] || { echo "Error: pr-merge requires PR number" >&2; exit 1; }
    PR_NUM="$1"; shift
    STRATEGY="--squash"
    while [[ $# -gt 0 ]]; do
      case $1 in
        --squash|--merge|--rebase) STRATEGY="$1"; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
      esac
    done
    echo "Merging PR #${PR_NUM} (${STRATEGY#--})" >&2
    _cleanup_pr_worktree "$PR_NUM"
    if [ "$WORKTREE_HELD" -eq 0 ]; then
      gh pr merge "$PR_NUM" "$STRATEGY" --delete-branch
    else
      # A worktree holds the local branch: merge, then delete only the remote
      # branch (gh's --delete-branch would also try the local one and fail).
      gh pr merge "$PR_NUM" "$STRATEGY"
      gh api -X DELETE "repos/{owner}/{repo}/git/refs/heads/${PR_HEAD_BRANCH}"
    fi
    ;;

  pr-edit)
    # Update a PR's title and/or body (--body from opsurface's copy).
    [ $# -ge 1 ] || { echo "Error: pr-edit requires PR number" >&2; exit 1; }
    PR_NUM="$1"; shift
    BODY=""
    BODY_FILE=""
    TITLE=""
    while [[ $# -gt 0 ]]; do
      case $1 in
        --body) BODY="$2"; shift 2 ;;
        --body-file) BODY_FILE="$2"; shift 2 ;;
        --title) TITLE="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
      esac
    done
    ARGS=()
    if [ -n "$BODY_FILE" ]; then ARGS+=(--body-file "$BODY_FILE"); fi
    if [ -n "$BODY" ]; then ARGS+=(--body "$BODY"); fi
    if [ -n "$TITLE" ]; then ARGS+=(--title "$TITLE"); fi
    [ ${#ARGS[@]} -ge 1 ] || { echo "Error: pr-edit needs --title, --body or --body-file" >&2; exit 1; }
    echo "Editing PR #${PR_NUM}" >&2
    gh pr edit "$PR_NUM" "${ARGS[@]}"
    ;;

  pr-view)
    # Read-only PR state (mergeability, checks, refs). Its own command so the
    # no-raw-gh rule does not push callers to `gh pr view` for a plain read.
    [ $# -ge 1 ] || { echo "Error: pr-view requires PR number" >&2; exit 1; }
    PR_NUM="$1"; shift
    gh pr view "$PR_NUM" "$@"
    ;;

  pr-close)
    [ $# -ge 1 ] || { echo "Error: pr-close requires PR number" >&2; exit 1; }
    PR_NUM="$1"; shift
    BODY=""
    while [[ $# -gt 0 ]]; do
      case $1 in
        --comment|--body) BODY="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
      esac
    done
    echo "Closing PR #${PR_NUM}" >&2
    if [ -n "$BODY" ]; then
      gh pr close "$PR_NUM" --comment "$BODY"
    else
      gh pr close "$PR_NUM"
    fi
    ;;

  integrate)
    # Full post-gate workflow: merge PR, close issue, update local base, prune refs.
    # Never switches the caller's checkout.
    [ $# -ge 2 ] || { echo "Error: integrate requires PR_NUM ISSUE_NUM" >&2; exit 1; }
    PR_NUM="$1"; shift
    ISSUE_NUM="$1"; shift
    STRATEGY="--merge"
    INTEGRATION_VERIFIED=0
    while [[ $# -gt 0 ]]; do
      case $1 in
        --squash|--merge|--rebase) STRATEGY="$1"; shift ;;
        --integration-verified) INTEGRATION_VERIFIED=1; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
      esac
    done

    # Step 0a: optional project-specific integration gate. When the PROJECT
    # (not devloop) provides scripts/integration-required.sh and it says the
    # PR's files need the slow integration suite, refuse unless the caller ran
    # it (--integration-verified). Generic projects skip this.
    INTEG_REQ="${WORKTREE_ROOT}/scripts/integration-required.sh"
    if [ "$INTEGRATION_VERIFIED" -ne 1 ] && [ -n "$WORKTREE_ROOT" ] && [ -x "$INTEG_REQ" ]; then
      PR_FILES=$(gh pr view "$PR_NUM" --json files --jq '.files[].path')
      if printf '%s\n' "$PR_FILES" | "$INTEG_REQ" --stdin; then
        echo "BLOCKED: PR #${PR_NUM} changes integration-sensitive code; the fast gate does not cover it." >&2
        echo "  Run the project's integration suite, then re-integrate with the verified flag:" >&2
        echo "    scripts/gh-ops.sh integrate ${PR_NUM} ${ISSUE_NUM} --integration-verified" >&2
        exit 1
      fi
    fi

    # Step 0: bring the PR branch up to date with its base. Server-side
    # (compare API + `gh pr update-branch`), so no local checkout is touched and
    # there is nothing to restore on failure. Rejected: a temp local branch via
    # `git checkout -b`, which switched the caller's live worktree.
    BASE=$(gh pr view "$PR_NUM" --json baseRefName --jq '.baseRefName')
    HEAD_SHA=$(gh pr view "$PR_NUM" --json headRefOid --jq '.headRefOid')
    echo "==> Checking PR #${PR_NUM} is up-to-date with ${BASE}" >&2
    BEHIND=$(gh api "repos/{owner}/{repo}/compare/${BASE}...${HEAD_SHA}" --jq '.behind_by')
    if [ "$BEHIND" -gt 0 ]; then
      echo "==> Branch is ${BEHIND} commit(s) behind ${BASE}; updating it on GitHub" >&2
      if ! gh pr update-branch "$PR_NUM"; then
        echo "Error: updating PR #${PR_NUM} with ${BASE} failed; resolve conflicts first" >&2
        exit 1
      fi
    else
      echo "==> Branch is up-to-date with ${BASE}" >&2
    fi

    # Step 1: Merge PR — worktree cleanup deferred to release (#235).
    # After the branch update above, GitHub asynchronously recomputes
    # mergeability (mergeStateStatus → UNKNOWN); a merge attempt in that window
    # fails "Pull Request is not mergeable". Poll mergeStateStatus and retry
    # with backoff so the transient resolves itself (#598).
    echo "==> Merging PR #${PR_NUM} (${STRATEGY#--})" >&2
    MERGE_OK=0
    MERGE_ERR=""
    for attempt in 1 2 3 4 5 6 7 8; do
      # A failed status read inside this retry loop is treated like UNKNOWN.
      MERGE_STATE=$(gh pr view "$PR_NUM" --json mergeStateStatus \
        --jq '.mergeStateStatus' || echo "UNKNOWN")
      if [ "$MERGE_STATE" = "UNKNOWN" ]; then
        echo "   mergeability still computing (attempt ${attempt}/8) — wait 3s" >&2
        sleep 3
        continue
      fi
      if MERGE_ERR=$(gh pr merge "$PR_NUM" "$STRATEGY" --delete-branch 2>&1); then
        MERGE_OK=1
        break
      fi
      case "$MERGE_ERR" in
        *"used by worktree"*)
          echo "Skipping local branch deletion — worktree holds it (cleanup deferred to release)" >&2
          MERGE_OK=1
          break
          ;;
        *"not mergeable"*|*"not in a mergeable state"*|*"Base branch was modified"*)
          echo "   transient not-mergeable (attempt ${attempt}/8) — wait 3s + retry" >&2
          sleep 3
          ;;
        *)
          echo "$MERGE_ERR" >&2
          exit 1
          ;;
      esac
    done
    if [ "$MERGE_OK" -ne 1 ]; then
      echo "Error: PR #${PR_NUM} did not become mergeable after retries — last: ${MERGE_ERR}" >&2
      exit 1
    fi

    # Step 2: Close issue only when the PR body closes it (Closes/Fixes/
    # Resolves #N); a "Refs #N" PR must not close an umbrella issue (upstreamed
    # from mobissh). gh reports an already-closed issue and exits 0.
    source "$SELF_DIR/lib/pr-closes.sh"
    PR_BODY=$(gh pr view "$PR_NUM" --json body --jq '.body')
    if pr_closes_issue "$PR_BODY" "$ISSUE_NUM"; then
      echo "==> Closing issue #${ISSUE_NUM}" >&2
      gh issue close "$ISSUE_NUM" --comment "Fixed in PR #${PR_NUM}"
    else
      echo "==> Leaving issue #${ISSUE_NUM} open (PR #${PR_NUM} does not say Closes/Fixes #${ISSUE_NUM})" >&2
    fi

    # Step 3: Remove bot label (only if present: issue 0 means no linked issue)
    if [ "$ISSUE_NUM" != "0" ] && _issue_has_label "$ISSUE_NUM" bot; then
      gh issue edit "$ISSUE_NUM" --remove-label bot
    fi

    # Step 4: update the local base branch without switching any checkout, prune
    echo "==> Updating local ${BASE}" >&2
    _update_local_branch "$BASE"
    git remote prune origin

    echo "+ Integrated: PR #${PR_NUM} (issue #${ISSUE_NUM})" >&2
    ;;

  delegate)
    # Pre-develop setup: label bot, add audit comment, prune stale refs
    [ $# -ge 1 ] || { echo "Error: delegate requires ISSUE_NUM" >&2; exit 1; }
    ISSUE_NUM="$1"; shift
    EXTRA_LABELS=()
    while [[ $# -gt 0 ]]; do
      case $1 in
        --label) EXTRA_LABELS+=("$2"); shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
      esac
    done

    # Apply bot label (swap from divergence if present; gh errors on removing
    # a label the repo does not define, so only remove what the issue has)
    echo "==> Labeling issue #${ISSUE_NUM}" >&2
    LABEL_ARGS=(--add-label bot)
    if _issue_has_label "$ISSUE_NUM" divergence; then
      LABEL_ARGS+=(--remove-label divergence)
    fi
    for l in "${EXTRA_LABELS[@]+"${EXTRA_LABELS[@]}"}"; do
      LABEL_ARGS+=(--add-label "$l")
    done
    gh issue edit "$ISSUE_NUM" "${LABEL_ARGS[@]}"

    # Audit trail comment
    echo "==> Adding audit comment" >&2
    gh issue comment "$ISSUE_NUM" --body "Delegated to local develop agent. Branch: bot/issue-${ISSUE_NUM}"

    # Clean stale refs
    git remote prune origin

    echo "+ Delegated: issue #${ISSUE_NUM} (bot label applied)" >&2
    ;;

  fetch-issues)
    # Print issue titles and bodies to stdout, or to --out FILE. No shared
    # default path: concurrent agents clobbered the old fixed /tmp file.
    [ $# -ge 1 ] || { echo "Error: fetch-issues requires comma-separated issue numbers" >&2; exit 1; }
    ISSUE_NUMS="$1"; shift
    OUT=""
    while [[ $# -gt 0 ]]; do
      case $1 in
        --out) OUT="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
      esac
    done
    if [ -n "$OUT" ]; then
      exec > "$OUT"
    fi
    IFS=',' read -ra NUMS <<< "$ISSUE_NUMS"
    for n in "${NUMS[@]}"; do
      n="${n// /}"
      echo "Fetching #${n}" >&2
      echo "## Issue #${n}"
      gh issue view "$n" --json title,body,labels --jq '"**\(.title)**\n\nLabels: \([.labels[].name] | join(", "))\n\n\(.body // "(no body)")"'
      echo
    done
    echo "Fetched ${#NUMS[@]} issue(s)${OUT:+ to ${OUT}}" >&2
    ;;

  release)
    # Create a GitHub release (and its tag) with optional asset uploads.
    [ $# -ge 1 ] || { echo "Error: release requires TAG" >&2; exit 1; }
    TAG="$1"; shift
    TITLE=""
    NOTES_FILE=""
    TARGET=""
    ASSETS=()
    while [[ $# -gt 0 ]]; do
      case $1 in
        --title) TITLE="$2"; shift 2 ;;
        --notes-file) NOTES_FILE="$2"; shift 2 ;;
        --target) TARGET="$2"; shift 2 ;;
        *) ASSETS+=("$1"); shift ;;
      esac
    done
    [ -n "$TITLE" ] || TITLE="$TAG"
    REL_ARGS=("$TAG" --title "$TITLE")
    if [ -n "$NOTES_FILE" ]; then
      [ -f "$NOTES_FILE" ] || { echo "Error: notes file not found: $NOTES_FILE" >&2; exit 1; }
      REL_ARGS+=(--notes-file "$NOTES_FILE")
    else
      REL_ARGS+=(--generate-notes)
    fi
    if [ -n "$TARGET" ]; then REL_ARGS+=(--target "$TARGET"); fi
    echo "Creating release ${TAG} (${TITLE})" >&2
    gh release create "${REL_ARGS[@]}" "${ASSETS[@]+"${ASSETS[@]}"}"
    ;;

  *)
    echo "Unknown command: $CMD" >&2
    usage
    ;;
esac
