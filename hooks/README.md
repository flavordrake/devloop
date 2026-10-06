# devloop hooks

Registered by the plugin via `hooks.json`; no manual `settings.json` install.
The TRACE hooks are silent unless the project has an active trace
(see `skills/agent-trace/SKILL.md`).

## Hook files

| File | Event | Purpose |
|------|-------|---------|
| `trace-session-start.sh` | SessionStart | TRACE status on session begin |
| `trace-pre-compact.sh` | PreCompact | Snapshot git state into the trace before compression |
| `trace-checkpoint.sh` | PostToolUse:Bash | TRACE status after a `git commit` |
| `enforce-hygiene.sh` | PreToolUse:Bash | Context nudge on raw `gh`; never a permission decision |

The TRACE hooks delegate to `scripts/trace-checkpoint.sh` for the one-line status.
Tests: `scripts/test/*.test.sh`.
