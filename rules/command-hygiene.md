# Workflow and Command Hygiene

- Fix the process, not the symptom: when an agent or script fails, fix the guard/script; don't hand-do the task.
- Call out inferred constraints that affect architecture, language, or testability ("Assuming X, affects Y. Confirm?"); mark them [INFERRED] in rules.
- `bug: <text>` from the user = file an issue (`/issue`), don't fix inline.
- Prefer existing scripts (repo `scripts/`, then devloop's) over raw CLI calls; capture repeated compound patterns as intent-named scripts.
- Call scripts directly (`scripts/<name>.sh`), never `bash scripts/<name>.sh`; scripts have shebangs and exec bits.
- Never `|| true`; use `if ! cmd; then log "failed (reason)"; fi`. Sole exception: grep under `set -euo pipefail`, wrapped in a function: `extract() { grep -o 'pat' || true; }`.
- Timestamps in filenames: `date +%Y%m%dT%H%M%S%z` (`20260303T150827-0500`).
- Don't name a script variable `TMPDIR` (clashes with mktemp).
- Worktree safety: never raw `rm -rf`, `git branch -D`, or `git worktree remove` on agent worktrees; don't clean worktrees while agents run (`git worktree prune` is always safe); check CWD before destructive operations.
