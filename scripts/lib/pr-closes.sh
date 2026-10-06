#!/usr/bin/env bash
# scripts/lib/pr-closes.sh — should merging a PR close a given issue?
#
# `gh-ops.sh integrate PR ISSUE` used to close ISSUE unconditionally, so a PR
# that only said "Refs #N" closed an umbrella issue still in progress (upstreamed
# from mobissh). Close only when the PR body uses a GitHub closing keyword
# (close/closes/closed/fix/fixes/fixed/resolve/resolves/resolved) for exactly
# that issue number. Issue 0 means "no linked issue" and never closes.
# POSIX classes instead of \b so BSD grep (macOS) behaves the same.

# pr_closes_issue BODY ISSUE — exit 0 when BODY closes #ISSUE.
pr_closes_issue() {
  local body="$1" issue="$2"
  [[ "$issue" =~ ^[0-9]+$ ]] || return 1
  [[ "$issue" -gt 0 ]] || return 1
  printf '%s\n' "$body" \
    | grep -qiE "(^|[^[:alnum:]_])(close[sd]?|fix(e[sd])?|resolve[sd]?)[[:space:]:]+#${issue}([^0-9]|$)"
}
