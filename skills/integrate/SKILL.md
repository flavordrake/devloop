---
name: integrate
description: Use when the user says "integrate", "review bot PRs", "merge bot fixes", "check bot work", "triage PRs", or explicitly "/integrate". Reviews bot PRs, validates them through the repo's declared gates, and merges or rejects.
---

# Integrate

Review, gate, and merge or reject PRs on `bot/issue-{N}` branches. Labels and
workflow states come from `.claude/process.md`; gate tiers from
`${CLAUDE_PLUGIN_ROOT}/rules/gates.md`.

Run in the foreground: the user sees triage and approves merges. Report per PR what
was checked, what passed, and the decision.

## 1. Discover and triage

Use `scripts/integrate-discover.sh` if the repo has it; otherwise list open PRs and
`bot/issue-*` branches with `${CLAUDE_PLUGIN_ROOT}/scripts/gh-ops.sh search`. Score each:
- `reject`: more than 2 attempts (`${CLAUDE_PLUGIN_ROOT}/rules/know-when-to-quit.md`)
- `low`: single file, under 50 lines
- `medium`: one module, or under 100 lines across 3 or fewer files
- `high`: core or security-sensitive code, or over the size thresholds in `${CLAUDE_PLUGIN_ROOT}/rules/decomposition.md`
- `skip`: no commits ahead of the default branch

Show issue, title, attempts, risk, and diff size; ask how to proceed.

## 2. Clean up rejects

Delete reject branches (`scripts/integrate-cleanup.sh` if present), comment on each
issue that the bot did not converge and it needs human re-scoping, then
`${CLAUDE_PLUGIN_ROOT}/scripts/gh-ops.sh labels N --rm bot --add divergence`.

## 3. Fast gate (parallel)

In risk order, spawn one `devloop:integrate-gater` per branch, up to 4 at a time:
```
Agent(subagent_type="devloop:integrate-gater", isolation="worktree", description="Gate: bot/issue-N", prompt="Branch: bot/issue-N. Tier: fast.")
```

## 4. Review

Merge requires all of:
- `fast` gate passed
- Source changes come with test changes; the PR body lists tests that went fail to pass. Missing coverage: reject asking for tests.
- Diff review: in scope, no plaintext secrets, no forced interactions or inflated timeouts in tests, no inline styles, no `--no-verify`

Reject on any of: gate failures that are bugs, wrong or unrelated scope, more than 2
prior attempts, a security anti-pattern.

Outdated is not flaky: if the approach is approved but tests fail only because the
behavior intentionally changed, keep the `bot` label and send the branch back through
`/develop N` with the failing assertions named, rather than rejecting the feature.

## 5. Full and device gates, then merge

One PR at a time, low risk first:
1. Run the `full` tier on the branch.
2. If the issue has the `device` label, run the repo's declared `device` tier (emulator
   repos wrap it in `scripts/with-fleet-emulator.sh`). No `device` tier, or no lease
   available: report the PR as needing device validation and do not merge it.
3. Merge: `${CLAUDE_PLUGIN_ROOT}/scripts/gh-ops.sh integrate <PR> <issue>` (merges, closes
   the issue, removes `bot`, pulls, prunes). For an orphaned branch, `pr-create` first.
4. On the updated default branch, run the `fast` tier. If it breaks, revert that merge,
   report which PR caused it, and stop.

Reject: `${CLAUDE_PLUGIN_ROOT}/scripts/gh-ops.sh pr-close <N> --comment "<specific failure>"`,
then set labels `--rm bot --add divergence`.

## 6. Final acceptance

After all merges, run the `device` tier once if the repo declares one and any merged
PR touched device-relevant behavior. If it cannot run, list which PRs still need
device validation; do not omit this silently. If the repo declares a post-merge
deploy step in process.md, run it so the user is not testing a stale build.

## TRACE

For batch integrations or non-obvious decisions, record in the active TRACE:
candidates and risk, planned order, pivots (unexpected gate failure, revert, judgment
rejects), and outcome with a knowledge seed.

## Edge cases

- No bot branches: report "No bot PRs to integrate".
- PR conflicts with the default branch: send back through `/develop N` to merge main.
- Stale worktrees block branch deletion: `git worktree prune` before merging.
