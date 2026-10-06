# Gate Contract

devloop skills and agents never name a stack's tools (compilers, linters, test
runners). They run a gate tier the consuming repo declares and read its exit code
and output.

## Tiers

Declared in the repo's `.claude/process.md` under `## Gates`. Each tier is one
command, ideally a repo script.

- `fast`: pre-push, seconds to minutes
- `full`: pre-merge
- `device`: emulator, hardware, or GPU; may be absent
- `ship`: release validation

## Fallback when process.md is absent

1. `scripts/fast-gate.sh`
2. else `scripts/gate.sh`
3. else report "no gate declared" and stop; do not invent one

## Other declarations in process.md

- Default branch, version file
- Issue tracker: `github` or `local:<path>`
- Domain labels
- Infra needs: emulator lease (`scripts/with-fleet-emulator.sh`), Modal GPU
  (`scripts/with-modal.sh`), mac-build, docker fixtures, CI-as-gate

## Example `.claude/process.md`

```markdown
## Gates
- fast: scripts/fast-gate.sh
- full: scripts/gate.sh
- device: scripts/with-fleet-emulator.sh scripts/e2e.sh
- ship: scripts/gate.sh --release
Version file: pubspec.yaml
```
