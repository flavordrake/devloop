# devloop

SDLC toolchain for Claude Code: skills, agents, hooks, and rules for an issue -> spec -> test -> develop -> gate -> integrate -> release loop.

devloop is stack-neutral through a gate contract: each repo declares how to check itself (`fast`, `full`, `device`, `ship` gate tiers) and devloop calls those, never a specific compiler, linter, or test runner. It is used with TypeScript, Flutter, Kotlin/Android, Python, Rust, C/PlatformIO, and shell/docs repos.

## Install

```
/plugin marketplace add flavordrake/devloop
/plugin install devloop@flavordrake
```

For development: `claude --plugin-dir ./devloop`. Marketplace installs namespace skills (`/devloop:cycle`); `--plugin-dir` registers them unprefixed (`/cycle`).

This repo is also the `flavordrake` marketplace (`.claude-plugin/marketplace.json`).

## Skills

| Skill | Purpose |
|-------|---------|
| `cycle` | One pump of the loop: discover, cluster, plan, develop, gate |
| `spec-develop` | Full TDD pipeline for one issue: spec -> red -> green |
| `write-tests` | Write failing tests from the spec (red) |
| `develop` | Implement an issue in a worktree until the gate passes (green) |
| `integrate` | Gate, review, and merge agent PRs |
| `delegate` | Classify open issues, analyze failed attempts, dispatch to develop agents |
| `decompose` | Split a large issue into independently shippable sub-issues |
| `issue` | File an issue from conversation (GitHub or a local backlog) |
| `doc-parity` | Compare code to docs and docs to code before a release |
| `release` | Version bump, changelog, tag, publish |
| `agent-trace` | Opt-in TRACE protocol for recording a development arc |

## Agents

Spawn as `subagent_type: devloop:<name>`. Frontmatter sets tools, model, and isolation.

| Agent | Model | Role |
|-------|-------|------|
| `develop` | inherit | Implements one issue in a worktree, runs the gate, opens a PR |
| `spec-writer` | opus | Turns an issue into a testable spec; stops on open questions |
| `test-writer` | opus | Writes failing tests from the spec; no app code |
| `integrate-gater` | haiku | Runs a gate tier on a candidate branch |
| `issue-manager` | haiku | Files issues, comments, labels |
| `delegate-scout` | sonnet | Gathers issue, branch, and prior-attempt data for `/delegate` |

## Hooks

Installed with the plugin: `enforce-hygiene` (PreToolUse:Bash, points raw `gh` calls at `gh-ops.sh`; never approves or blocks) and TRACE hooks (session start, pre-compact snapshot, commit checkpoint), which stay silent when no trace is active.

## Rules

Plugins can't ship rules, so repos link them (see below). Every session loads the core set; `paths:` frontmatter limits the rest to matching files.

| Rule | Loads | Key point |
|------|-------|-----------|
| command-hygiene | always | Fix the process; scripts over raw commands; worktree safety |
| agents | always | devloop agent types, isolation, permissions |
| hooks-and-cwd | always | `${CLAUDE_PLUGIN_ROOT}`, repo-root resolution, native worktrees |
| tdd | always | Separate test-writer (red) and developer (green) |
| decomposition | always | Size thresholds; sequential A -> B -> C for coupled refactors |
| know-when-to-quit | always | Stop divergent fix cycles early |
| security | always | No plaintext secrets; block, don't fall back |
| gates | always | The gate tier contract |
| state-management | source files | Explicit lifecycle enums, not boolean combinations |
| platform/* | web files | Mobile touch, web test-harness impact |

## Adopting devloop in a repo

1. Write `AGENTS.md` at the repo root with a `## Gates` section mapping `fast`, `full`, `device`, and `ship` to commands or scripts (see the `gates` rule), and optionally a `## Project` section (default branch, version file, issue tracker `github` or `local:<path>`, domain labels, infra needs). Codex, opencode and pi read `AGENTS.md`; Claude Code reads `CLAUDE.md`, so add the line `@AGENTS.md` to it. Without gates, devloop falls back to `scripts/fast-gate.sh`, then `scripts/gate.sh`.
2. Link the rules: an idempotent `scripts/link-devloop-rules.sh` that symlinks each devloop `rules/*.md` into `.claude/rules/devloop/` (devloop path overridable by `DEVLOOP_ROOT`). Re-run it when devloop adds rules.
3. Call devloop scripts through the plugin, never copy or shim them. In skills and hooks: `${CLAUDE_PLUGIN_ROOT}/scripts/gh-ops.sh`. From a shell or repo script, resolve the installed version: `"$("$HOME/.claude/plugins/marketplaces/flavordrake/scripts/devloop-path.sh")/scripts/gh-ops.sh"` (the marketplace clone is the version-free bootstrap; `scripts/devloop-path.sh` returns the newest cached install). Upstream missing subcommands instead of forking.
4. In CI (no plugin installed), pin devloop with the setup action, which exports `DEVLOOP_ROOT`:

   ```yaml
   - uses: flavordrake/devloop/.github/actions/setup@v0.4.4
   - run: '"$DEVLOOP_ROOT/skills/doc-parity/scripts/doc-parity.sh" --block'
   ```

   Then delete the repo's vendored copies of devloop scripts and their tests; devloop tests them.
5. Run `/doc-parity` before every release. Release is blocked while code and docs drift.

## Structure

```
.claude-plugin/   plugin.json (manifest, version), marketplace.json
hooks.json        hook wiring (${CLAUDE_PLUGIN_ROOT})
skills/           one SKILL.md per skill
agents/           subagent definitions
hooks/            hook scripts
scripts/          gh-ops, gh-file-issue, trace utils, validate-plugin
rules/            rules for linking into repos (platform/ is path-scoped)
```

Every script, subcommand and env var: [docs/scripts.md](docs/scripts.md).
