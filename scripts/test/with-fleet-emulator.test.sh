#!/usr/bin/env bash
# Tests for scripts/with-fleet-emulator.sh host defaults, env aliases and the
# consumer knobs it passes through (tailscale and ssh are stubbed).
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
# Record the target (arg after the options) and the remote command, grant the lease immediately.
for a in "$@"; do case "$a" in -*|BatchMode=yes) ;; *) echo "$a" > "$SSH_LOG"; break ;; esac; done
printf '%s\n' "$@" > "$SSH_LOG.argv"
echo READY
sleep 5
STUB
chmod +x "$T/bin/tailscale" "$T/bin/ssh"

# run ENV... — the child records what the wrapper exported to it.
run() { env PATH="$T/bin:$PATH" SSH_LOG="$T/ssh.log" EMU_CAPTOKEN=t EMU_LOG_DIR="$T/log" "$@" "$S" -- sh -c 'echo "adb=$EMU_ADB adbd=$EMU_ADBD_ENDPOINT container=${EMU_CONTAINER-unset} ensure=${EMU_ENSURE-unset} mode=${ADB_MODE-unset}" > "$0"' "$T/child" > "$T/out" 2>&1; }

run env
if grep -qx 'emu@android-emulator.example.ts.net' "$T/ssh.log"; then pass "default host uses the tailnet FQDN"; else fail "default host: $(cat "$T/ssh.log" "$T/out")"; fi
if grep -q 'adb=android-emulator.example.ts.net:5556 adbd=android-emulator.example.ts.net:5556' "$T/child"; then pass "child gets EMU_ADB and EMU_ADBD_ENDPOINT"; else fail "child env: $(cat "$T/child")"; fi
if grep -q 'container=unset ensure=unset mode=unset' "$T/child"; then pass "unset knobs stay unset"; else fail "unset knobs: $(cat "$T/child")"; fi
if grep -q 'EMU_CONTAINER=' "$T/ssh.log.argv"; then fail "unset knobs not sent to remote"; else pass "unset knobs not sent to remote"; fi

run env EMU_TAILNET=
if grep -qx 'emu@android-emulator' "$T/ssh.log"; then pass "empty EMU_TAILNET keeps the short name"; else fail "empty EMU_TAILNET: $(cat "$T/ssh.log")"; fi

run env EMU_HOST=me@other
if grep -qx 'me@other' "$T/ssh.log"; then pass "EMU_HOST overrides"; else fail "EMU_HOST: $(cat "$T/ssh.log")"; fi

run env EMU_LEASE_HOST=lease@alias EMU_ADB_ENDPOINT=alias:5555
if grep -qx 'lease@alias' "$T/ssh.log"; then pass "EMU_LEASE_HOST aliases EMU_HOST"; else fail "EMU_LEASE_HOST: $(cat "$T/ssh.log")"; fi
if grep -q 'adb=alias:5555 adbd=alias:5555' "$T/child"; then pass "EMU_ADB_ENDPOINT aliases EMU_ADB"; else fail "EMU_ADB_ENDPOINT: $(cat "$T/child")"; fi

run env EMU_HOST=me@other EMU_LEASE_HOST=lease@alias
if grep -qx 'me@other' "$T/ssh.log"; then pass "EMU_HOST wins over its alias"; else fail "alias precedence: $(cat "$T/ssh.log")"; fi

run env EMU_CONTAINER=emu-a EMU_ENSURE=1 ADB_MODE=tcp EMU_ADBD_ENDPOINT=adbd:5557
if grep -q 'adbd=adbd:5557 container=emu-a ensure=1 mode=tcp' "$T/child"; then pass "knobs reach the child, EMU_ADBD_ENDPOINT kept"; else fail "knob pass-through: $(cat "$T/child")"; fi
if grep -q 'RELAYGENT_CAPTOKEN=t EMU_CONTAINER=emu-a EMU_ENSURE=1 flock' "$T/ssh.log.argv"; then pass "EMU_CONTAINER and EMU_ENSURE reach the remote ensure"; else fail "remote env: $(cat "$T/ssh.log.argv")"; fi
if grep -q 'ADB_MODE' "$T/ssh.log.argv"; then fail "ADB_MODE is child-only"; else pass "ADB_MODE is child-only"; fi

if [ "$FAILS" -ne 0 ]; then echo "$FAILS case(s) failed"; exit 1; fi
echo "all with-fleet-emulator cases passed"
