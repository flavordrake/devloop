# devloop

General-purpose Claude Code development loop toolchain. Skills, agents, hooks, and rules for TDD-driven SDLC automation.

## Usage

Symlink into your workspace's `.claude/` directory:

```bash
ln -s /path/to/devloop/hooks   /path/to/workspace/.claude/hooks
ln -s /path/to/devloop/rules   /path/to/workspace/.claude/rules
ln -s /path/to/devloop/skills  /path/to/workspace/.claude/skills
ln -s /path/to/devloop/agents  /path/to/workspace/.claude/agents
ln -s /path/to/devloop/settings.json /path/to/workspace/.claude/settings.json
```

Project-specific config goes in `project/.claude/` and merges via Claude Code's upward-traversal.

## Structure

```
hooks/              Shell hooks (PreToolUse, PostToolUse)
rules/              General rules (command hygiene, workflow, security, agents)
skills/             SDLC skills (cycle, develop, write-tests, integrate, delegate, etc.)
agents/             Agent prompt templates (develop, issue-manager, integrate-gater, etc.)
settings.json       Shared permissions and hook wiring
```

## Skills

| Skill | Purpose |
|-------|---------|
| `/cycle` | One pump of the SDLC loop — discover, classify, develop, gate |
| `/develop` | Implement an issue (Phase 2 of TDD) |
| `/write-tests` | Write tests from spec (Phase 1 of TDD) |
| `/integrate` | Review, gate, merge bot PRs |
| `/delegate` | Classify and dispatch issues to bot agents |
| `/decompose` | Break large issues into bot-sized sub-issues |
| `/issue` | File a GitHub issue from conversation |
| `/release` | Version bump, changelog, tag, publish |
| `/agent-trace` | TRACE protocol for capturing development arcs |

## Design

- **Portable**: No project-specific references in general config
- **Composable**: Projects override/extend via their own `.claude/`
- **No magic sync**: Updating a project's copy is explicit
- **Convention-based**: Skills expect `scripts/test-gate.sh` etc. by convention
