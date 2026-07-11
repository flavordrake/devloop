# Agents and Delegation

## Agent type reality (updated 2026-07-11; original finding 2026-03-22)

Agent types are discovered at SESSION START. Plugin agents (e.g. `devloop:develop`,
`devloop:spec-writer`) register under their namespaced names and work as `subagent_type`.
Project-local `.claude/agents/*.md` files created mid-session do NOT register until the
next session start — spawning them mid-session errors (verified 2026-07-11 with
scrapdaw's `visual-designer`). Built-ins are always available: `general-purpose`,
`Explore`, `Plan`, `claude-code-guide`, `statusline-setup`.

**Rules:**
- **Verify with a cheap spawn before assuming a custom type resolves**; when in doubt or mid-session, use `general-purpose` with the agent file's content as the prompt. Scope restriction goes in the prompt, not the agent type.
- Either way, lead the `description` parameter with the role ("Visual designer: revise IA") so the status line scans by role even under a generic type.
- Agent `.md` files in `.claude/agents/` are **prompt templates only** — read them for the prompt content, but don't rely on frontmatter for execution behavior.
- Control `run_in_background` and `isolation` via the Agent tool call parameters.
- For read-only agents (scout, gater): include "Do NOT modify files" in the prompt.
- For write agents (develop, issue-manager): use `isolation: "worktree"`.

## Permission enforcement

- Agent frontmatter (`permissionMode`, `model`, `tools`) is **ignored** — agents inherit the parent session's permissions.
- **All tools agents need must be in `settings.json` allow-list.** This is the only way to grant permissions to background agents.
- **`deny` rules in `settings.json` survive `bypassPermissions`** — this is the only reliable enforcement.
- For fine-grained control (e.g., read-only Bash), use `PreToolUse` hooks — they fire even in bypass mode.
- **Do NOT accumulate one-off approvals in `settings.local.json`.** If an agent needs a tool pattern, generalize it into `settings.json`.

## TDD two-phase development

The orchestrator (main session) owns the TDD cycle, not the develop agent:

1. **Phase 1: `/write-tests` agent** — writes tests from the issue spec. Tests express expected behavior. Confirms they FAIL (red baseline). Commits tests to bot branch.
2. **Phase 2: `/develop` agent** — implements code until pre-written tests pass (green). Does NOT write new tests.

The test agent writes tests that express what the behavior SHOULD be, independently of how it's implemented. The develop agent CAN update tests if they're wrong, but should not write net-new tests.

## Repo safety

- **Never use raw `rm -rf` on worktree paths.** Use safe cleanup scripts.
- **Worktree cleanup is deferred to release.** Do NOT clean while agents are active — worktrees are cheap (git hardlinks). `git worktree prune` (removes only already-deleted directories) is always safe.
- **CWD drift:** Verify CWD before destructive operations. Workflow scripts should detect and fix CWD drift automatically.
