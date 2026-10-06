#!/usr/bin/env bash
# Tests for scripts/with-fleet-emulator.sh host defaults (tailscale and ssh are stubbed).
# Usage: scripts/test/with-fleet-emulator.test.sh   (exit 0 = all pass)
set -uo pipefail
S="$(cd "$(dirname "$0")/.." && pwd)/with-fleet-emulator.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
FAILS=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }

mkdir -p "$T/bin"
cat > "$T/bin/tailscale" <<'STUB'
#!/bin/sh
echo '{"MagicDNSSuffix":"example.ts.net"}'
STUB
cat > "$T/bin/ssh" <<'STUB'
#!/bin/sh
# Record the target (arg after the options), grant the lease immediately.
for a in "$@"; do case "$a" in -*|BatchMode=yes) ;; *) echo "$a" > "$SSH_LOG"; break ;; esac; done
echo READY
sleep 5
STUB
chmod +x "$T/bin/tailscale" "$T/bin/ssh"

run() { env PATH="$T/bin:$PATH" SSH_LOG="$T/ssh.log" EMU_CAPTOKEN=t EMU_LOG_DIR="$T/log" "$@" "$S" -- sh -c 'echo "$ANDROID_SERIAL $ADB_SERVER" > "$0"' "$T/child" > "$T/out" 2>&1; }

run env
if grep -qx 'emu@android-emulator.example.ts.net' "$T/ssh.log"; then pass "default host uses the tailnet FQDN"; else fail "default host: $(cat "$T/ssh.log" "$T/out")"; fi

run env EMU_TAILNET=
if grep -qx 'emu@android-emulator' "$T/ssh.log"; then pass "empty EMU_TAILNET keeps the short name"; else fail "empty EMU_TAILNET: $(cat "$T/ssh.log")"; fi

run env EMU_HOST=me@other
if grep -qx 'me@other' "$T/ssh.log"; then pass "EMU_HOST overrides"; else fail "EMU_HOST: $(cat "$T/ssh.log")"; fi

if [ "$FAILS" -ne 0 ]; then echo "$FAILS case(s) failed"; exit 1; fi
echo "all with-fleet-emulator cases passed"
