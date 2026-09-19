#!/usr/bin/env bash
# host-boot.sh — everything fd-dev needs relaunched after a container (re)start.
# fd-dev is a docker container (PID 1 docker-init): no systemd, no cron, so
# nothing below survives a restart on its own. Idempotent; meant to be called
# by the container's entrypoint as `dev` after tailscale is up and before the
# final exec (fleet manager review 2026-09-19: bounded, non-fatal, SSH must
# stay available even if the hub or inference is down). Running it by hand is
# equally fine. Durable copy: chezmoi source (matthewfrazier/dotfiles,
# dot_local/bin/executable_host-boot.sh); `chezmoi apply` restores it.
#
# Health = the loop's PROCESS is alive, never "a tmux session by that name
# exists". Exit 0 only when every step succeeded; otherwise exit 1 and say so.
set -uo pipefail
STATE="$HOME/.local/state/host-boot"
mkdir -p "$STATE"
LOG="$STATE/boot.log"
exec > >(tee -a "$LOG") 2>&1
echo "> host-boot $(date +%Y%m%dT%H%M%S%z) on $(hostname -s)"
FAILED=0

# ensure_loop <session> <script-basename> <command>: the loop is healthy when
# the tmux pane is alive (pane_dead=0) AND a process running <script-basename>
# descends from that pane — never "a session by that name exists". A session
# whose loop died is killed and recreated; a loop running outside tmux is left
# alone and reported, never duplicated.
ensure_loop() {
  local name="$1" proc="$2" cmd="$3" pane_pid dead child
  if tmux has-session -t "$name" 2>/dev/null; then
    read -r pane_pid dead < <(tmux list-panes -t "$name" -F '#{pane_pid} #{pane_dead}' | head -1)
    child="$(pgrep -f "$proc" -P "$pane_pid" | head -1 || true)"
    if [[ "$dead" == "0" && -n "$child" ]]; then
      echo "= $name: running (pid $child)"
      return 0
    fi
    echo "! $name: tmux session exists but $proc is not running under it; recreating"
    tmux kill-session -t "$name"
  elif pgrep -f "$proc" >/dev/null; then
    echo "! $name: $proc runs outside tmux (pid $(pgrep -f "$proc" | head -1)); not duplicating it"
    return 0
  fi
  if tmux new-session -d -s "$name" "$cmd"; then
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      pane_pid="$(tmux list-panes -t "$name" -F '#{pane_pid}' 2>/dev/null | head -1)"
      if [[ -n "$pane_pid" ]] && pgrep -f "$proc" -P "$pane_pid" >/dev/null; then echo "+ $name: started"; return 0; fi
      sleep 1
    done
    echo "! $name: session created but $proc did not come up within 10s"
  else
    echo "! $name: tmux new-session failed"
  fi
  FAILED=1
  return 1
}

# 1. tmux server + resurrect/continuum plugins (restores the `main` session
#    layout from the last save on first start).
if [[ -x "$HOME/.local/bin/tmux-persist-setup" ]]; then
  "$HOME/.local/bin/tmux-persist-setup" || { echo "! tmux-persist-setup failed"; FAILED=1; }
fi
tmux start-server

# 2. Fleet bus watcher (wakes idle sessions on hub events).
mkdir -p "$HOME/.relaygent"
ensure_loop hub-watcher hub-watcher.sh "HUB_WAKE_TMUX=main /usr/local/bin/hub-watcher.sh >> $HOME/.relaygent/watcher.log 2>&1"

# 3. Host health monitor (#fleet alerts on sustained load/mem/swap/disk/io/sshd).
mkdir -p "$HOME/.local/state/host-health"
ensure_loop host-health host-health-monitor.sh "$HOME/.local/bin/host-health-monitor.sh >> $HOME/.local/state/host-health/monitor.log 2>&1"

# 4. rac Ollama daily characteristic check.
ensure_loop rac-healthcheck rac-ollama-healthcheck-daily.sh "$HOME/.local/bin/rac-ollama-healthcheck-daily.sh >> $HOME/.local/state/rac-hc.log 2>&1"

# 5. opsurface-sync addon: start the daemon, pick up a published upgrade,
#    re-map tailscale serve. --upgrade also ensures the daemon is up. Bounded:
#    the upgrade check has its own 10 s curl timeout; the whole step is capped.
ADDON_HOME="${ADDON_HOME:-$HOME/.agenthub/addons/opsurface-sync}"
if [[ -x "$ADDON_HOME/ensure.sh" ]]; then
  if timeout 120 "$ADDON_HOME/ensure.sh" --upgrade; then
    echo "+ opsurface-sync: ensured"
  else
    echo "! opsurface-sync: ensure.sh --upgrade failed (exit $?)"; FAILED=1
  fi
else
  echo "= opsurface-sync: not installed"
fi

# 6. Bus handler window in `main` (Sonnet triage loop). hub-handler is itself
#    idempotent. `main` may still be restoring from resurrect: wait for it,
#    bounded, instead of skipping for good.
for _ in $(seq 1 30); do
  tmux has-session -t main 2>/dev/null && break
  sleep 2
done
if tmux has-session -t main 2>/dev/null; then
  "$HOME/.local/bin/hub-handler" || { echo "! handler: hub-handler failed"; FAILED=1; }
else
  echo "! handler: no main session after 60s; rerun host-boot.sh once it is restored"; FAILED=1
fi

if (( FAILED )); then
  echo "! host-boot done with failures (see above)"
  exit 1
fi
echo "+ host-boot done"
