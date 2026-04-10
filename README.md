# devloop

TDD-driven SDLC toolchain for Claude Code. Skills, agents, hooks, and rules for development automation.

## Install

**Add the marketplace, then install:**
```
/plugin marketplace add flavordrake/devloop
/plugin install devloop@flavordrake
```

**Or load locally for development:**
```bash
git clone https://github.com/flavordrake/devloop.git
claude --plugin-dir ./devloop
```

Skills are namespaced: `/devloop:cycle`, `/devloop:develop`, etc.

## Marketplace

This repo is both a plugin and a marketplace. The marketplace catalog at `.claude-plugin/marketplace.json` lists all available plugins. Third-party authors can submit plugins by PR — add an entry to the `plugins` array with a `source` pointing to your GitHub repo.

## Skills

| Skill | Purpose |
|-------|---------|
| `/devloop:cycle` | One pump of the SDLC loop — discover, classify, develop, gate |
| `/devloop:develop` | Implement an issue (Phase 2 of TDD) |
| `/devloop:write-tests` | Write tests from spec (Phase 1 of TDD) |
| `/devloop:integrate` | Review, gate, merge bot PRs |
| `/devloop:delegate` | Classify and dispatch issues to bot agents |
| `/devloop:decompose` | Break large issues into bot-sized sub-issues |
| `/devloop:issue` | File a GitHub issue from conversation |
| `/devloop:release` | Version bump, changelog, tag, publish |
| `/devloop:agent-trace` | TRACE protocol for capturing development arcs |
| `/devloop:crystallize` | Extract deterministic ops from skill prose into tested scripts ([design](docs/crystallize.md)) |

## Hooks

Installed automatically with the plugin:

- **enforce-hygiene** (PreToolUse:Bash) — detects compound chains, redirects, heredocs, raw CLI calls
- **trace-signal** (PostToolUse:Write/Edit) — reminds to update TRACE when decision-signal paths change

## Rules

Core rules (stack-agnostic):

| Rule | Key insight |
|------|-------------|
| command-hygiene | One script per Bash call — chains cause false positive failures |
| tdd | Two agents: test writer (red) then developer (green) |
| decomposition | Sequential A→B→C for coupled refactors |
| state-management | Explicit lifecycle enums, not boolean combinations |
| hooks-and-cwd | Absolute paths for hooks, CWD drift resilience |
| agents | Permissions flow via settings.json allow-list |
| workflow | Fix the process not the symptom |
| security | No plaintext secrets, block don't fallback |

Platform-specific (in `rules/platform/`, opt-in):
- **mobile-touch** — textarea swipe constraints, touch-action patterns

## Project Permissions

The plugin provides hooks and skills but **cannot distribute permissions**. Run the merge script to add recommended permissions to your project:

```bash
./devloop/scripts/merge-settings.sh /path/to/project/.claude/settings.json
```

This uses `jq` to merge devloop's recommended permissions into your existing settings — non-destructive, only adds, never removes.

## Structure

```
.claude-plugin/
  plugin.json           Plugin manifest
  hooks.json            Hook wiring (uses ${CLAUDE_PLUGIN_ROOT})
skills/                 SDLC skills
agents/                 Agent prompt templates
hooks/                  Shell hook scripts
rules/                  Core rules (stack-agnostic)
  platform/             Platform-specific rules (opt-in)
```

## Design Principles

- **Stack-agnostic core**: Rules and skills work for any language/framework
- **Platform specializations**: `rules/platform/` for mobile, embedded, etc.
- **Convention-based**: Skills expect `scripts/test-gate.sh` etc. by convention
- **Proper plugin**: Uses Claude Code plugin system, not symlinks
