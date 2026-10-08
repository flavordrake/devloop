#!/usr/bin/env bash
# scripts/with-fleet-emulator.sh — run a command while holding an EXCLUSIVE lease
# on the shared fleet Android emulator, then hand the leased device's adb
# endpoint to the command (EMU_ADB, EMU_ADBD_ENDPOINT).
#
# The device is on demand: idle-stopped until a lease boots it (~135s cold), so
# a bare `adb connect` is refused. The lease is `ssh + flock` against the
# emulator host; its ssh key is forced to a shim that only grants the lease with
# a hub-signed capability token, minted here via `hub acquire`. Exclusivity is
# the point (installs, global-settings writes and reboots would collide between
# projects): do not bypass it.
#
# Canonical copy of the per-repo wrappers (mobissh self-contained version,
# opsurface/mobiharness/onetap thin wrappers over ~/with-emulator.sh).
#
# Usage: with-fleet-emulator.sh -- <command...>
#
# Env (lease side):
#   EMU_HOST           ssh target holding the lease (default emu@android-emulator.<tailnet>);
#                      alias EMU_LEASE_HOST (mobissh's name)
#   EMU_TAILNET        MagicDNS suffix (default: from `tailscale status`); empty = short names
#   EMU_ADB            adb endpoint exported to the child (default android-emulator.<tailnet>:5556);
#                      alias EMU_ADB_ENDPOINT (mobissh's name)
#   EMU_CAPTOKEN       pre-minted capability token (default: hub acquire)
#   EMU_LEASE_WAIT     seconds to wait for a busy lease (default 900)
#   EMU_LEASE_MAXHOLD  seconds before the lease auto-releases (default 7200; the
#                      lease is released as soon as the command exits)
#   EMU_REPO           repo path on the emulator host (default /opt/android-emulator)
#   EMU_LEASE          lease file on the emulator host
#   EMU_LOG_DIR        where the remote ensure/boot output goes
#
# Consumer knobs, passed through only when set:
#   EMU_CONTAINER, EMU_ENSURE   to the remote `emu-ctl.sh ensure` env and the child
#   ADB_MODE, EMU_ADBD_ENDPOINT to the child
#
# Exported to the child command: EMU_ADB, EMU_ADBD_ENDPOINT (defaults to EMU_ADB
# when the consumer did not set it), plus any of the knobs above that are set.
set -euo pipefail

# Full tailnet names: known_hosts pins the FQDN, not the MagicDNS short name.
# The suffix is read from tailscale at runtime so this public repo names no tailnet.
tailnet_suffix() {
  if command -v tailscale >/dev/null && command -v jq >/dev/null; then
    tailscale status --json | jq -r '.MagicDNSSuffix // empty'
  fi
}
EMU_TAILNET="${EMU_TAILNET-$(tailnet_suffix)}" # set-but-empty means short names
EMU_FQDN="android-emulator${EMU_TAILNET:+.$EMU_TAILNET}"
EMU_HOST="${EMU_HOST:-${EMU_LEASE_HOST:-emu@$EMU_FQDN}}"
EMU_ADB="${EMU_ADB:-${EMU_ADB_ENDPOINT:-$EMU_FQDN:5556}}"
EMU_LEASE_WAIT="${EMU_LEASE_WAIT:-900}"
EMU_LEASE_MAXHOLD="${EMU_LEASE_MAXHOLD:-7200}"
EMU_REPO="${EMU_REPO:-/opt/android-emulator}"
LEASE="${EMU_LEASE:-/var/lib/android-emulator/lease}"
EMU_LOG_DIR="${EMU_LOG_DIR:-${TMPDIR:-/tmp}/fleet-emulator}"
mkdir -p "$EMU_LOG_DIR"

[[ "${1:-}" == "--" ]] && shift
if [[ $# -eq 0 ]]; then
  echo "Usage: with-fleet-emulator.sh -- <command...>" >&2
  exit 2
fi

log() { echo "> [fleet-emulator] $*" >&2; }
err() { echo "! [fleet-emulator] $*" >&2; }

captoken="${EMU_CAPTOKEN:-}"
if [[ -z "$captoken" ]]; then
  if ! command -v hub >/dev/null 2>&1; then
    err "hub CLI not found and no EMU_CAPTOKEN; the lease shim requires a capability token"
    exit 2
  fi
  log "acquiring capability token (hub acquire host@android-emulator emulator)"
  captoken="$(hub acquire host@android-emulator emulator --ttl "$EMU_LEASE_MAXHOLD")" || {
    err "hub acquire failed; without a capability token the shim denies the lease"
    exit 1
  }
fi

# A backgrounded pty ssh holds the flock and boots the device, then prints
# READY. The remote `flock -w` blocks until any current holder releases; the
# pty makes the remote side get SIGHUP (and release) when we disconnect.
sentinel="$(mktemp -u "${TMPDIR:-/tmp}/fleet-emulator.XXXXXX")"
mkfifo "$sentinel"
# Consumer knobs the remote ensure honors ride along as env on the flock command.
# ${!v} indirection, not an associative array: macOS bash 3.2.
remote_env="RELAYGENT_CAPTOKEN=${captoken}"
for v in EMU_CONTAINER EMU_ENSURE; do
  if [[ -n "${!v:-}" ]]; then remote_env="${remote_env} ${v}=${!v}"; fi
done
remote_cmd="${remote_env} flock -w ${EMU_LEASE_WAIT} -x ${LEASE} bash -c '
  ${EMU_REPO}/scripts/emu-ctl.sh ensure 2>&1 || { echo ENSURE_FAILED; exit 1; }
  echo READY
  sleep ${EMU_LEASE_MAXHOLD}'"

# ssh's own stderr goes to the lease log rather than the terminal: it is pty
# noise ("Connection closed") on every normal release.
lease_log="${EMU_LOG_DIR}/lease.log"
: > "$lease_log"
ssh -tt -o BatchMode=yes "$EMU_HOST" "$remote_cmd" > "$sentinel" 2>> "$lease_log" &
ssh_pid=$!

cleanup() {
  if kill -0 "$ssh_pid" 2>/dev/null; then
    kill "$ssh_pid"
  fi
  rm -f "$sentinel"
}
trap cleanup EXIT INT TERM

wait_start=$(date +%s)
log "acquiring lease on ${EMU_HOST} for: $* (queue <= ${EMU_LEASE_WAIT}s, cold boot ~135s, hold <= ${EMU_LEASE_MAXHOLD}s)"
state=""
phase="queued"
granted_at=""
# fd 3, not {fd}: named fds need bash 4.1 and macOS ships 3.2.
exec 3< "$sentinel"
while true; do
  if IFS= read -r -t 30 -u 3 line; then
    line="${line//$'\r'/}"
    if [[ "$phase" == "queued" ]]; then
      phase="booting"; granted_at=$(date +%s)
      log "lease granted after $((granted_at - wait_start))s queued; remote ensure/boot running (progress: ${lease_log})"
    fi
    case "$line" in
      READY)         state="ready"; break ;;
      ENSURE_FAILED) state="ensure_failed"; break ;;
      *)             printf '%s\n' "$line" >> "$lease_log" ;;
    esac
  else
    # read failed: EOF if the ssh holder exited (flock timeout, DENY, ssh
    # failure), else a 30s timeout. Checking the pid is portable; read's
    # timeout exit code differs between bash 3.2 and 4+.
    kill -0 "$ssh_pid" 2>/dev/null || break
    now=$(date +%s)
    if [[ "$phase" == "queued" ]]; then
      log "still queued for the lease on ${EMU_HOST}: $((now - wait_start))s of ${EMU_LEASE_WAIT}s max"
    else
      log "device ensure/boot running for $((now - granted_at))s (tail ${lease_log})"
    fi
  fi
done
exec 3<&-

if [[ "$state" != "ready" ]]; then
  err "lease NOT acquired: ${state:-timeout or ssh failure} (remote output: ${lease_log})"
  err "check: ssh ${EMU_HOST} ${EMU_REPO}/scripts/emu-ctl.sh status"
  exit 1
fi

log "lease held + device booted after $(( $(date +%s) - wait_start ))s; adb endpoint ${EMU_ADB}"
export EMU_ADB
export EMU_ADBD_ENDPOINT="${EMU_ADBD_ENDPOINT:-$EMU_ADB}"
for v in EMU_CONTAINER EMU_ENSURE ADB_MODE; do
  if [[ -n "${!v:-}" ]]; then export "$v"; fi
done

hold_start=$(date +%s)
set +e
"$@"
rc=$?
set -e
held=$(( $(date +%s) - hold_start ))
# When the remote `sleep MAXHOLD` ends, the flock drops and the device
# idle-stops under a still-running command: later failures are device loss.
if (( held >= EMU_LEASE_MAXHOLD )); then
  err "LEASE EXPIRED MID-RUN: ran ${held}s >= EMU_LEASE_MAXHOLD=${EMU_LEASE_MAXHOLD}s; failures after expiry are device loss, rerun with a longer EMU_LEASE_MAXHOLD"
fi
log "command exited rc=${rc} after ${held}s; releasing lease"
exit "$rc"
