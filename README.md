# devloop

General-purpose Claude Code development loop toolchain. Skills, agents, hooks, and rules for TDD-driven SDLC automation.

## Install

```bash
git clone https://github.com/flavordrake/devloop.git
./devloop/install.sh /path/to/workspace
```

Or as a Claude Code plugin:
```
/plugin marketplace add flavordrake/devloop
/plugin install devloop
```

Project-specific config goes in `project/.claude/` and merges via Claude Code's upward-traversal.

## Structure

```
hooks/                  Shell hooks (PreToolUse, PostToolUse)
rules/                  Core rules (stack-agnostic)
  command-hygiene.md      One script per call, no chains, no heredocs
  workflow.md             Fix process not symptom, inferred constraints
  security.md             No plaintext secrets, block don't fallback
  agents.md               Spawning, permissions, worktree safety
  tdd.md                  Two-phase TDD (write-tests → develop)
  decomposition.md        Sequential A→B→C for coupled refactors
  state-management.md     Explicit state machines, server↔client contracts
  hooks-and-cwd.md        Absolute paths, CWD drift resilience
  platform/               Stack/platform-specific rules (opt-in)
    mobile-touch.md         Mobile browser touch constraints
skills/                 SDLC skills (stack-agnostic)
agents/                 Agent prompt templates
settings.json           Shared permissions and hook wiring
install.sh              Symlink installer for workspaces
.claude-plugin/         Claude Code plugin manifest
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

## Core Rules

| Rule | Key insight |
|------|-------------|
| command-hygiene | One script per Bash call — chains cause false positive failures |
| tdd | Two agents: test writer (red) then developer (green) — tests define the spec |
| decomposition | Sequential A→B→C for coupled refactors — each part bot-sized and mergeable |
| state-management | Don't infer state from boolean combos — use explicit lifecycle enums |
| hooks-and-cwd | Absolute paths for hooks, CWD drifts when worktrees are deleted |
| agents | Permissions flow via settings.json allow-list, not agent frontmatter |

## Design Principles

- **Stack-agnostic core**: Rules and skills work for any language/framework
- **Platform specializations**: `rules/platform/` for mobile, embedded, etc. (opt-in)
- **Portable**: No project-specific references
- **Composable**: Projects override/extend via their own `.claude/`
- **No magic sync**: `git pull` in devloop dir updates all symlinked projects
- **Convention-based**: Skills expect `scripts/test-gate.sh` etc. by convention
