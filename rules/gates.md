# Gate Contract

devloop skills and agents never name a stack's tools (compilers, linters, test
runners). They run a gate tier the consuming repo declares and read its exit code
and output.

## Tiers

Declared in `AGENTS.md` at the git toplevel under `## Gates` (the cross-harness
file codex, opencode and pi read). Claude Code reads `CLAUDE.md`, not
`AGENTS.md`, so the repo's `CLAUDE.md` should contain the line `@AGENTS.md`.
Each tier is one line: a command, ideally a repo script, or a short `&&`
sequence. It may call devloop scripts as
`${plugin}/...` (`${CLAUDE_PLUGIN_ROOT}` in a skill, `devloop-path.sh` output
from a shell).

- `fast`: pre-push, seconds to minutes
- `full`: pre-merge; also the per-branch gate the integrate-gater runs on a
  candidate branch. A repo may add `integrate:` when that run should differ.
- `device`: emulator, hardware, or GPU; may be absent
- `ship`: release validation

Optional plain-text annotations, indented under a tier, for the agent running it
(no parser reads them; agents read and obey):

- `class:` one or more of `offline` (no network, no shared infra, safe
  anywhere), `live` (needs shared infrastructure: emulator lease, build-runner,
  tailnet services, real devices), `destructive` (mutates shared state,
  restores backups, touches hardware; runs only with explicit scoped
  coordination). Absent: `fast` is `offline`, `device` is `live`, others
  unspecified. Agents never fold `live` or `destructive` into a routine fast
  gate and never run `destructive` unprompted.
- `requires:` tools or env the tier needs: adb, flutter, `DEVLOOP_ROOT`, a captoken
- `cwd:` where to run it; default repo root
- `when:` a condition the agent evaluates, e.g. "full adds the e2e suite when
  native/** changed"
- `needs:` prerequisites, e.g. artifacts a `fast` or `full` run produced, or a
  remote build-runner wrote into an artifacts dir
- `args:` arguments the caller supplies, e.g. `<prev> <new> <tag>`

Cross-harness: Codex, opencode and pi read `AGENTS.md` natively; every tier is
a plain command, so any harness or shell runs it directly. Nothing in the
contract requires Claude Code.

## Resolution order

1. `AGENTS.md` `## Gates`
2. else legacy `.claude/process.md` `## Gates` (deprecated, still read)
3. else `scripts/fast-gate.sh`
4. else `scripts/gate.sh`
5. else report "no gate declared" and stop; do not invent one

## Project metadata: `AGENTS.md` `## Project`

Legacy `.claude/process.md` is read when `AGENTS.md` has no `## Project`.

- Default branch, version file
- Issue tracker: `github` or `local:<path>`
- Domain labels, workflow labels
- Infra needs: emulator lease (`scripts/with-fleet-emulator.sh`), Modal GPU
  (`scripts/with-modal.sh`), mac-build, docker fixtures, CI-as-gate
- Deploy or post-release verification steps
- `post-integrate:` a script `gh-ops.sh` runs after a successful integrate
- `commit-trailers:` trailer lines the develop agent appends to every commit

## Optional repo-provided scripts

Skills call these in the consuming repo when present and fall back (devloop's
`scripts/gh-ops.sh`, or the gate fallback above) when absent. devloop does not
ship them for consumers (its own `scripts/fast-gate.sh` gates devloop only); its
doc-parity ignore file waives them.

- Gates: `scripts/fast-gate.sh`, `scripts/gate.sh`, `scripts/e2e.sh`, `scripts/with-modal.sh`
- Setup: `scripts/link-devloop-rules.sh`
- Delegate: `scripts/delegate-discover.sh`, `scripts/delegate-classify.sh`,
  `scripts/delegate-failure-analysis.sh`, `scripts/delegate-fetch-bodies.sh`
- Develop: `scripts/develop-propose.sh`
- Integrate: `scripts/integrate-discover.sh`, `scripts/integrate-cleanup.sh`

## Example `AGENTS.md`

```markdown
## Project
- Default branch: main
- Version file: pubspec.yaml
- Issue tracker: github
- commit-trailers: Signed-off-by: Release Bot <bot@example.org>

## Gates
- fast: scripts/fast-gate.sh
  - class: offline
- full: scripts/gate.sh
  - when: adds the e2e suite when native/** changed
- device: scripts/with-fleet-emulator.sh scripts/e2e.sh
  - class: live
  - requires: adb, EMU_CAPTOKEN
  - needs: debug APK from `full` in build/artifacts/
- ship: scripts/release-gate.sh && ${plugin}/skills/doc-parity/scripts/doc-parity.sh --block
  - class: offline
  - args: <prev> <new> <tag>
```

With `CLAUDE.md`:

```markdown
@AGENTS.md
```
