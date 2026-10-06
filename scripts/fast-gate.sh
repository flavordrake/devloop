#!/usr/bin/env bash
# scripts/fast-gate.sh: devloop's own fast gate (plugin validation, script tests,
# doc parity as a warning).
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/validate-plugin.sh
for t in scripts/test/*.test.sh; do
  echo "> $t"
  "$t"
done
skills/doc-parity/scripts/doc-parity.sh --warn
