# Git Integration

## Branches
- Develop agent branches: `bot/issue-{N}`. One branch per issue; a retry continues
  the same branch with new commits (never force-push).

## Merge from the default branch often
Drift is the main cause of integration pain. Merge before starting, before running
tests, after each cycle, and before pushing:
```bash
git fetch origin main
git merge origin/main --no-edit
```
Never rebase; merge commits are fine.

Conflicts: `git diff --name-only --diff-filter=U`. Resolve conflicts in your files,
keeping both sides' intent. Conflicts in files you did not touch mean a scope
problem; report it. Stuck: `git merge --abort`, read `git show origin/main:<file>`,
retry.

## Commits
- `fix:` / `feat:` / `chore:` prefix, issue reference `(#N)`, first line under 72 chars.
- One commit per cycle is fine; PRs squash or merge per repo convention.

## PRs
- Body from a temp file, created via `${CLAUDE_PLUGIN_ROOT}/scripts/gh-ops.sh pr-create`.
- `Closes #N`, gate results included, one issue per PR.

## Keep diffs small
Size thresholds live in `${CLAUDE_PLUGIN_ROOT}/rules/decomposition.md`.
Change the minimum that satisfies the acceptance criteria. Don't refactor adjacent
code, annotate unchanged code, or handle impossible cases. Inline a helper unless
it is used 3+ times.

## Pre-push
1. Merge from the default branch.
2. Run the `fast` gate.
3. Review `git diff --stat origin/main`; over the decomposition thresholds, reconsider scope.

## Passes locally, fails in CI
Compare toolchain versions, generated or compiled artifacts, and services the tests
assume are running. CI's environment is defined by the repo's workflow files.
