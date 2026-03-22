# Command Hygiene

## Intent-based scripts over compound commands

- **One script per Bash call.** No `&&` chains, no `;` sequences, no compound commands. Chained commands cause false positive failures (e.g., local branch delete fails but remote merge succeeded, exit 1 blocks downstream steps).
- **No shell redirects.** Scripts handle their own output. No `> /tmp/foo`, no `2>/dev/null`.
- **No heredocs in Bash.** Use the Write tool to create files, then pass `--body-file`.
- **Prefer existing scripts over raw commands.** Check `ls scripts/` before writing inline commands. If a compound pattern repeats, capture it as an intent-named script.
- **Never prefix script calls with `bash`.** All scripts have shebangs and execute permissions. Call `scripts/foo.sh` not `bash scripts/foo.sh`.
- **Never use raw CLI tool commands when wrapper scripts exist.** Raw calls bypass error handling, audit logging, and hook notifications. If a wrapper doesn't have a subcommand for what you need, add one — don't work around it.

## Error handling

- Never use `|| true` to swallow errors. Use `if ! cmd; then log "failed (reason)"; fi`.
- **Exception: grep in pipelines.** Under `set -euo pipefail`, `grep` exits non-zero on zero matches, killing the pipeline. Wrap in a function: `extract() { grep -oP 'pattern' || true; }`. This is the only valid use of `|| true`.

## Script conventions

- **Timestamps in filenames use compact ISO-8601 with tz offset:** `date +%Y%m%dT%H%M%S%z` → `20260303T150827-0500`. Never use bare `%Y%m%d-%H%M%S`.
- **Temp and log directories:** Every script defines project-namespaced env vars near the top (after `set -euo pipefail`) and creates the directories before use. Do NOT use `TMPDIR` as the variable name — it conflicts with the system `TMPDIR` used by `mktemp`.
- Scripts log via `exec > >(tee -a "$LOGFILE") 2>&1`.

## Safe operations

- **Never use raw `rm -rf` on worktree paths.** Use safe cleanup scripts or functions that check `is_main_repo` before deletion.
- **Never use raw `git checkout`, `git branch -D`, or `git worktree remove` after agent operations.** Use intent-driven scripts instead.
- **Verify CWD before any destructive operation.** CWD can drift into worktree directories after agent operations.

## Output style

- Don't use multiline text separators in logs, scripts, summaries, and reports (no `====`, no `----`). It's noise and wastes tokens.
