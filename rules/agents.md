# Agents

- Agent types register at session start. Plugin agents work as `subagent_type: devloop:<name>`; project `.claude/agents/*.md` created mid-session don't register until the next session (fall back to `general-purpose` with the file's body as the prompt).
- Agent frontmatter (`tools`, `model`, `isolation`) is honored. Override per call only when needed.
- Lead the Agent `description` with the role ("Develop: #42 retry backoff") so status lines scan by role.
- Write agents get worktree isolation; read-only agents say "Do NOT modify files" in the prompt.
- Background agents can't answer permission prompts: grant what they need in `settings.json` (or rely on auto mode); `deny` rules and `PreToolUse` hooks still apply in bypass mode.
- Generalize recurring approvals into `settings.json`; don't accumulate one-offs in `settings.local.json`.
- TDD split between test-writer and develop agents: see `tdd.md`.
