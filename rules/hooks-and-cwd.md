# Hooks and CWD

- Plugin hooks reference scripts as `"${CLAUDE_PLUGIN_ROOT}/hooks/foo.sh"` (quoted). Project hooks use `"$CLAUDE_PROJECT_DIR"/...`, never relative paths: sessions start from parent dirs and CWD drifts into worktrees.
- Scripts that must act on the consumer repo resolve it from CWD (`git rev-parse --show-toplevel`), not from their own location, which is the plugin checkout or cache.
- `cd` in a Bash call doesn't persist; pass absolute paths or `git -C <dir>`.
- Use native worktree isolation (Agent `isolation: "worktree"`, or agent frontmatter) instead of hand-made worktrees. Don't delete a worktree while a session's CWD is inside it; run `git worktree prune` afterwards.
- PostToolUse hooks that react to writes must ignore their own output paths (e.g. `.traces/`) to avoid loops.
