#!/usr/bin/env bash
# Tests for scripts/devloop-path.sh: newest cached version by numeric compare,
# DEVLOOP_ROOT override, fallback to its own checkout.
# Usage: scripts/test/devloop-path.test.sh   (exit 0 = all pass)
set -euo pipefail

DEVLOOP="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d -t devloop-path-test.XXXXXX)"
trap 'rm -rf "$T"' EXIT

FAILS=0
check() { if [[ "$2" == "$3" ]]; then echo "PASS $1"; else echo "FAIL $1: got '$2' want '$3'"; FAILS=$((FAILS + 1)); fi; }

C="$T/cfg/plugins/cache/flavordrake/devloop"
mkdir -p "$C/0.4.9" "$C/0.4.10" "$C/0.10.0" "$C/0.9.12" "$C/tmp"
check "highest version, numeric not lexical" "$(CLAUDE_CONFIG_DIR="$T/cfg" DEVLOOP_ROOT= "$DEVLOOP/scripts/devloop-path.sh")" "$C/0.10.0"
check "DEVLOOP_ROOT wins" "$(CLAUDE_CONFIG_DIR="$T/cfg" DEVLOOP_ROOT=/x "$DEVLOOP/scripts/devloop-path.sh")" "/x"
check "no cache: own checkout" "$(CLAUDE_CONFIG_DIR="$T/none" DEVLOOP_ROOT= "$DEVLOOP/scripts/devloop-path.sh")" "$DEVLOOP"

if [ "$FAILS" -ne 0 ]; then
  echo "$FAILS case(s) failed"
  exit 1
fi
echo "all devloop-path cases passed"
