# Hooks and CWD Resilience

## Hook paths must be absolute

Relative paths (`./.claude/hooks/foo.sh`) fail when:
- Session starts from a parent directory
- CWD drifts into a worktree directory
- Agent worktree is deleted while process CWD is inside it

Use absolute paths in `settings.json` hook commands. If hooks are symlinked from
a shared project (like devloop), the symlink target must also use absolute paths
or resolve its own location via `$(dirname "$0")`.

## Process CWD vs shell CWD

The Claude Code process has its own CWD that persists across Bash tool calls.
`cd /path` in a Bash call only changes the shell's CWD for that call — the next
Bash call resets to the process CWD.

When a worktree agent runs and the worktree is later deleted, the process CWD
becomes invalid. This breaks:
- `isolation: "worktree"` on future Agent calls ("not in a git repository")
- Any Bash call that assumes CWD is the repo root

**Workaround:** Create a `scripts/run-in-repo.sh` that resolves the repo root
via `$(dirname "$0")/..` and `cd`s before executing:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
exec "$@"
```

**Prevention:** Run `scripts/worktree-cleanup.sh` BEFORE worktrees are deleted.
Don't delete worktree directories while the process might have CWD inside them.

## Decision-signal hooks

PostToolUse hooks on Write/Edit can detect writes to "decision paths" (memory,
settings, rules, CLAUDE.md) and remind to update the active TRACE. These are
reliable proxies for "something significant just happened."

The hook must exclude `.traces/` writes to avoid loops.
