# Scripts

devloop's shipped scripts. Call them through the plugin (`${CLAUDE_PLUGIN_ROOT}/scripts/...`); they act on the repo of the caller's cwd. Progress goes to stderr, results to stdout. Scripts that consuming repos provide themselves are listed in `rules/gates.md`.

## GitHub

`scripts/gh-ops.sh <command> [args]`: one approvable wrapper for issue and PR operations. `gh-ops.sh --help` prints the full usage.

| command | does |
|---|---|
| `gh-ops.sh comment ISSUE --body-file F` or `--body TEXT` | add a comment |
| `gh-ops.sh comments ISSUE` | print an issue's comments |
| `gh-ops.sh labels ISSUE [--add L] [--rm L]` | edit labels |
| `gh-ops.sh label-create NAME [--color HEX] [--description T]` | create a repo label |
| `gh-ops.sh close ISSUE [--comment T \| --body-file F]` | close |
| `gh-ops.sh reopen ISSUE [--comment T]` | reopen |
| `gh-ops.sh search QUERY [LIMIT]` | open issues as JSON |
| `gh-ops.sh version` | code hash, plus the app version when `GH_OPS_APP_PORT` names a local app port |
| `gh-ops.sh pr-create --head B [--base A] --title T --body-file F [--label L]` | open a PR (`--base` for a stacked PR) |
| `gh-ops.sh pr-edit PR [--title T] [--body-file F] [--body T]` | edit an open PR |
| `gh-ops.sh pr-view PR [gh pr view flags]` | read-only PR state |
| `gh-ops.sh pr-merge PR [--squash\|--merge\|--rebase]` | retarget PRs stacked on it, merge, delete branch (integrate does the same) |
| `gh-ops.sh pr-close PR [--comment T]` | close a PR |
| `gh-ops.sh integrate PR ISSUE [--merge\|--squash\|--rebase]` | merge, close the issue if the PR closes it, update local base, then run the repo's `post-integrate:` command from AGENTS.md `## Project` if declared (exit code logged, never fails the integrate) |
| `gh-ops.sh delegate ISSUE [--label L]` | label `bot`, audit comment, prune refs |
| `gh-ops.sh fetch-issues N1,N2 [--out F]` | print issue bodies |
| `gh-ops.sh release TAG --title T [--notes-file F] [--target SHA] [--prerelease] [ASSET...]` | create a release and tag (`--prerelease` marks it a pre-release) |

`scripts/gh-file-issue.sh --title T --label L [--body-file F] [--dry-run]`: file an issue (body from file or stdin), print its URL.

## TRACE

- `scripts/trace-init.sh [--force] <slug>`: start a TRACE under `.traces/` and record it in the project's CLAUDE.md; refuses to replace an existing Active TRACE line without `--force`.
- `scripts/trace-check.sh [trace-dir]`: report the active TRACE's freshness.
- `scripts/trace-checkpoint.sh [trigger]`: one-line TRACE status; called by the hooks, silent with no active trace.

## Sessions and infra

- `scripts/launch-session.sh [kickoff|--continue]`: open tmux window `<name>` running a Remote Control Claude session for the cwd's repo. `TMUX_SESSION` (default `main`), `SESSION_NAME` (default: repo directory name).
- `scripts/with-fleet-emulator.sh -- <command...>`: run a command holding an exclusive lease on the shared fleet emulator. `EMU_HOST` (alias `EMU_LEASE_HOST`), `EMU_ADB` (alias `EMU_ADB_ENDPOINT`), `EMU_TAILNET`, `EMU_CAPTOKEN`, `EMU_LEASE_WAIT`, `EMU_LEASE_MAXHOLD`, `EMU_REPO`, `EMU_LEASE`, `EMU_LOG_DIR`; defaults in the script header. Consumer knobs passed through when set: `EMU_CONTAINER`, `EMU_ENSURE` (remote ensure env and child), `ADB_MODE`, `EMU_ADBD_ENDPOINT` (child). Exported to the child: `EMU_ADB`, `EMU_ADBD_ENDPOINT` (defaults to `EMU_ADB`), plus the set knobs.

## Plugin

- `scripts/devloop-path.sh`: print the newest installed devloop root for shell callers that have no `${CLAUDE_PLUGIN_ROOT}`. `DEVLOOP_ROOT` overrides; `CLAUDE_CONFIG_DIR` (default `~/.claude`) locates the plugin cache; with no cache it prints its own checkout.
- `.github/actions/setup/action.yml`: for CI with no plugin. `uses: flavordrake/devloop/.github/actions/setup@<tag>` puts devloop at that tag in `$RUNNER_TEMP/devloop` and exports `DEVLOOP_ROOT`; call `"$DEVLOOP_ROOT/scripts/<name>"`. Input `ref` picks another tag, branch or commit. Local shells use `devloop-path.sh`, which honors the same `DEVLOOP_ROOT`. Test harnesses that run scripts under `env -i` or in scratch repos must pass `DEVLOOP_ROOT` (or `HOME`) through, or wrappers can't find devloop.
- `scripts/validate-plugin.sh`: `claude plugin validate` plus skill frontmatter checks.
- `scripts/fast-gate.sh`: devloop's own fast gate (validate-plugin, `scripts/test/`, doc parity warning); `.github/workflows/ci.yml` runs it on push and PR, and runs `gh-ops.sh --help` and doc parity through the setup action.

## Libraries (`scripts/lib/`, sourced)

- `repo-guard.sh`: resolve the caller's repo; safe worktree removal.
- `pr-closes.sh`: does a PR body close a given issue.
- `trace-locate.sh`: find the session's CLAUDE.md and active trace (first `.traces/trace-*` token on the Active TRACE line; prose and extra paths are tolerated).
- `heavy-job-lock.sh`: host-wide lock serializing heavy jobs. `HEAVY_LOCK_DIR` (default `/tmp/heavy-job-lock`), `HEAVY_LOCK_MAX_WAIT_SECS` (2700), `HEAVY_LOCK_MIN_AVAIL_GB` (3), `HEAVY_LOCK_MEMINFO`, `HEAVY_LOCK_CGROUP_DIR` (memory floor inputs; tests point them at fixtures).
