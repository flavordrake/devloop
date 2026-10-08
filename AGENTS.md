# devloop

devloop follows its own contract (`rules/gates.md`).

## Project
- Default branch: main
- Version file: .claude-plugin/plugin.json
- Issue tracker: github

## Gates
- fast: scripts/fast-gate.sh
  - class: offline
- ship: skills/doc-parity/scripts/doc-parity.sh --block
  - class: offline

## Doc surfaces
- code: *.sh
- ignore: .claude/doc-parity-ignore.txt
