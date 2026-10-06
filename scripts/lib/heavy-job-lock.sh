#!/usr/bin/env bash
# scripts/lib/heavy-job-lock.sh — Serialize heavy jobs (gates, builds, emulator
# suites) host-wide, across projects. Canonical copy of opsurface/mobiharness
# scripts/lib/heavy-job-lock.sh.
#
# Why: concurrent fast-gate + emulator suite + release build + agents' test runs
# saturated host CPU (load 15-27) and starved tailscaled. Fix at the boundary
# where the load is born: every script that runs a heavy job takes this
# host-wide flock first, so at most one runs at a time (agents included).
#
# Linux only: needs util-linux flock, /proc, `tail --pid`, procps `ps --sort`.
# acquire_heavy_lock fails loudly without flock instead of running unserialized.
#
# Usage: source "$(dirname "$0")/lib/heavy-job-lock.sh"
#        acquire_heavy_lock "fast-gate"
#        ...
#        release_heavy_lock   # optional early release; EXIT trap covers the rest
#
# Re-entrant across a process tree: a gate that holds the lock and runs another
# lock-taking script as a child would otherwise flock() the same inode from a
# second open file description and block on its own ancestor forever.
# acquire_heavy_lock exports HEAVY_JOB_LOCK_HELD=1 once it holds the lock; a
# nested acquire in the same tree sees that and proceeds without re-flocking.
#
# Not inheritable: `exec {FD}>lock; flock $FD` handed the descriptor to every
# child, so an orphaned test process kept the flock 46 minutes after its gate
# died. Bash cannot set FD_CLOEXEC, so the calling shell never opens the lock:
# a `flock --close` process holds it and runs only a `tail --pid` watcher of
# the acquiring shell. The holder exits within ~1s of the acquiring shell dying
# by any means, SIGKILL included, and no workload child ever sees the fd.
# Rejected: re-exec'ing the caller under flock (the lib cannot see its argv).
#
# The holder file is "label<TAB>pid<TAB>start" so wait and timeout lines name
# the holder. A holder whose recorded pid is dead (seen on two probes a poll
# apart, so a fresh acquirer is never broken underneath) has its lock broken.
#
# Env: HEAVY_LOCK_DIR (/tmp/heavy-job-lock; host-wide by design, so projects
#      serialize against each other), HEAVY_LOCK_MAX_WAIT_SECS (2700 = 45m),
#      HEAVY_LOCK_MIN_AVAIL_GB (3), HEAVY_LOCK_MEMINFO (/proc/meminfo),
#      HEAVY_LOCK_CGROUP_DIR (/sys/fs/cgroup) — the last three are the memory
#      floor; tests point them at fixtures.
#
# The 3 GB floor default was measured on an LXC host with memory.max 10 GB: a
# Flutter fast-gate added 2.2 GB peak (rounded to 2.5) + 0.5 GB margin.
# Re-measure (sample memory.current each second over a gate run) for heavier
# jobs and set HEAVY_LOCK_MIN_AVAIL_GB rather than guessing.

HEAVY_LOCK_DIR="${HEAVY_LOCK_DIR:-/tmp/heavy-job-lock}"
HEAVY_LOCK_MIN_AVAIL_GB="${HEAVY_LOCK_MIN_AVAIL_GB:-3}"
HEAVY_LOCK_MEMINFO="${HEAVY_LOCK_MEMINFO:-/proc/meminfo}"
HEAVY_LOCK_CGROUP_DIR="${HEAVY_LOCK_CGROUP_DIR:-/sys/fs/cgroup}"
HEAVY_LOCK_FILE="${HEAVY_LOCK_DIR}/heavy-job.lock"
HEAVY_LOCK_HOLDER_FILE="${HEAVY_LOCK_DIR}/heavy-job.holder"
HEAVY_LOCK_MAX_WAIT_SECS="${HEAVY_LOCK_MAX_WAIT_SECS:-2700}"
HEAVY_LOCK_ACQUIRED=0
HEAVY_LOCK_HOLDER_PID=""

# _heavy_lock_try — one non-blocking attempt. On success HEAVY_LOCK_HOLDER_PID
# is the flock process holding the lock for this shell.
_heavy_lock_try() {
  # $BASHPID read here, not inside <(...), which would expand to the subshell.
  local ready="" fd owner="$BASHPID"
  exec {fd}< <(flock --close -n "$HEAVY_LOCK_FILE" \
    bash -c 'echo locked; exec tail --pid="$1" -f /dev/null >/dev/null' _ "$owner" \
    2>/dev/null </dev/null)
  HEAVY_LOCK_HOLDER_PID=$!
  read -r -t 10 ready <&"$fd" || true
  exec {fd}<&-
  [[ "$ready" == "locked" ]]
}

# _heavy_lock_describe <holder-line> — "label (pid N, started T)".
_heavy_lock_describe() {
  local label pid started
  IFS=$'\t' read -r label pid started <<< "$1"
  echo "${label:-unknown} (pid ${pid:-unknown}, started ${started:-unknown})"
}

# acquire_heavy_lock <label> — block (up to HEAVY_LOCK_MAX_WAIT_SECS) until the
# host-wide heavy-job lock is free, then hold it. Registers an EXIT trap that
# releases it, so a script that never calls release_heavy_lock still frees it
# on any exit path (success, failure, or signal).
acquire_heavy_lock() {
  local label="${1:?acquire_heavy_lock requires a label}"

  if [[ "${HEAVY_JOB_LOCK_HELD:-0}" -eq 1 ]]; then
    echo "> heavy job lock already held by this process tree; ${label} proceeds without re-acquiring"
    return 0
  fi

  if ! command -v flock >/dev/null 2>&1; then
    echo "! heavy job lock: flock not found (Linux util-linux); refusing to run ${label} unserialized" >&2
    exit 1
  fi
  mkdir -p "$HEAVY_LOCK_DIR"

  local deadline=$(( $(date +%s) + HEAVY_LOCK_MAX_WAIT_SECS ))
  local holder="" last_dead="" pid="" waited=0
  until _heavy_lock_try; do
    holder="$(cat "$HEAVY_LOCK_HOLDER_FILE" 2>/dev/null || true)"
    IFS=$'\t' read -r _ pid _ <<< "$holder"
    if [[ "$pid" =~ ^[0-9]+$ && ! -d "/proc/${pid}" ]]; then
      if [[ "$holder" == "$last_dead" ]]; then
        echo "> heavy job lock holder $(_heavy_lock_describe "$holder") is dead; breaking the lock"
        rm -f "$HEAVY_LOCK_FILE" "$HEAVY_LOCK_HOLDER_FILE"
        continue
      fi
      last_dead="$holder"
    fi
    if [[ "$waited" -eq 0 ]]; then
      echo "> waiting for heavy job lock held by $(_heavy_lock_describe "$holder")…"
      waited=1
    fi
    if [[ "$(date +%s)" -ge "$deadline" ]]; then
      echo "! heavy job lock: ${label} timed out after ${HEAVY_LOCK_MAX_WAIT_SECS}s waiting on $(_heavy_lock_describe "$holder")" >&2
      exit 1
    fi
    sleep 1
  done

  printf '%s\t%s\t%s\n' "$label" "$BASHPID" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$HEAVY_LOCK_HOLDER_FILE"
  HEAVY_LOCK_ACQUIRED=1
  trap release_heavy_lock EXIT

  # Memory floor: the lock stays held while waiting so no other heavy
  # job starts in the gap and takes the memory this one is waiting for.
  # awk, not $(( )): the measured default is fractional GB.
  local min_kb avail_kb bound
  min_kb="$(awk -v gb="$HEAVY_LOCK_MIN_AVAIL_GB" 'BEGIN { printf "%d", gb * 1048576 }')"
  IFS=$'\t' read -r avail_kb bound <<< "$(_heavy_lock_avail_kb)"
  if [[ "$avail_kb" -lt "$min_kb" ]]; then
    echo "> waiting for memory floor: $(_heavy_lock_gb "$avail_kb") GB available (${bound}), ${HEAVY_LOCK_MIN_AVAIL_GB} GB required; largest: $(_heavy_lock_top_rss)"
  fi
  while [[ "$avail_kb" -lt "$min_kb" ]]; do
    if [[ "$(date +%s)" -ge "$deadline" ]]; then
      echo "! heavy job lock: ${label} timed out after ${HEAVY_LOCK_MAX_WAIT_SECS}s waiting for memory floor: $(_heavy_lock_gb "$avail_kb") GB available (${bound}), ${HEAVY_LOCK_MIN_AVAIL_GB} GB required (HEAVY_LOCK_MIN_AVAIL_GB); largest: $(_heavy_lock_top_rss)" >&2
      exit 1
    fi
    sleep 1
    IFS=$'\t' read -r avail_kb bound <<< "$(_heavy_lock_avail_kb)"
  done

  export HEAVY_JOB_LOCK_HELD=1
  echo "> heavy job lock acquired (${label})"
}

# _heavy_lock_avail_kb — "kB<TAB>which figure bound": the lesser of
# MemAvailable and, when memory.max is a number, memory.max - memory.current
# (+ memory.stat inactive_file when present).
# In an LXC container /proc/meminfo reports the HOST's memory, but the cgroup
# is what OOM-kills the job, so its headroom must bind too. MemAvailable is 0
# if unreadable, so a missing meminfo fails at the deadline loudly instead of
# starting blind; "max" or absent cgroup files mean meminfo alone.
_heavy_lock_avail_kb() {
  local kb=0 cg_max cg_cur cg_inactive=0 cg_kb
  if [[ -r "$HEAVY_LOCK_MEMINFO" ]]; then
    kb="$(awk '/^MemAvailable:/ { kb = $2 } END { print kb + 0 }' "$HEAVY_LOCK_MEMINFO")"
  fi
  cg_max="$(cat "${HEAVY_LOCK_CGROUP_DIR}/memory.max" 2>/dev/null || true)"
  cg_cur="$(cat "${HEAVY_LOCK_CGROUP_DIR}/memory.current" 2>/dev/null || true)"
  # inactive_file is page cache the kernel reclaims before a cgroup OOM kill;
  # memory.current counts it (1.4 GB of file pages measured on an LXC host), so
  # leaving it out under-reports headroom. Same "working set" kubelet evicts on.
  if [[ -r "${HEAVY_LOCK_CGROUP_DIR}/memory.stat" ]]; then
    cg_inactive="$(awk '$1 == "inactive_file" { b = $2 } END { print b + 0 }' "${HEAVY_LOCK_CGROUP_DIR}/memory.stat")"
  fi
  if [[ "$cg_max" =~ ^[0-9]+$ && "$cg_cur" =~ ^[0-9]+$ ]]; then
    cg_kb=$(( (cg_max - cg_cur + cg_inactive) / 1024 ))
    if [[ "$cg_kb" -lt "$kb" ]]; then
      printf '%s\tcgroup memory.max - memory.current + inactive_file\n' "$cg_kb"
      return
    fi
  fi
  printf '%s\tMemAvailable\n' "$kb"
}

_heavy_lock_gb() { awk -v kb="$1" 'BEGIN { printf "%.1f", kb / 1048576 }'; }

# _heavy_lock_top_rss — the three largest processes by RSS as
# "name N MB (cwd)", measured from ps and /proc/<pid>/cwd; the cwd is what
# names a sibling project's build.
_heavy_lock_top_rss() {
  local pid rss comm cwd out=""
  while read -r pid rss comm; do
    cwd="$(readlink "/proc/${pid}/cwd" 2>/dev/null || echo "cwd unreadable")"
    out+="${out:+, }${comm} $(( rss / 1024 )) MB (${cwd})"
  done < <(ps -eo pid=,rss=,comm= --sort=-rss | head -3)
  echo "$out"
}

# release_heavy_lock — free the lock early (e.g. hold it only around a build,
# not a following upload). Safe to call twice: the EXIT trap
# calls it again on script exit and finds nothing left to release. A no-op in
# a process that only saw the lock as already-held (re-entrant case above) —
# it never took the flock, so it must not release its ancestor's.
release_heavy_lock() {
  if [[ "$HEAVY_LOCK_ACQUIRED" -eq 1 ]]; then
    echo "> heavy job lock released"
    rm -f "$HEAVY_LOCK_HOLDER_FILE"
    # Ending the tail watcher ends flock, which is what drops the lock.
    pkill -P "$HEAVY_LOCK_HOLDER_PID" 2>/dev/null || true
    kill "$HEAVY_LOCK_HOLDER_PID" 2>/dev/null || true
    wait "$HEAVY_LOCK_HOLDER_PID" 2>/dev/null || true
    HEAVY_LOCK_ACQUIRED=0
    unset HEAVY_JOB_LOCK_HELD
  fi
}
