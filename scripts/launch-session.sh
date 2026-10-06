#!/usr/bin/env bash
# scripts/launch-session.sh: open (or reopen) a project's Claude session.
# Creates tmux window <name> in session "main" running a Remote Control Claude
# session named <name> in the repo of the caller's cwd. <name> defaults to the
# repo directory name (SESSION_NAME overrides). Idempotent: if the window
# already exists it just reports it. Use --continue after a restart to resume
# the previous conversation instead of starting from the project's own
# scripts/kickoff.md prompt. Canonical copy of the identical per-repo scripts
# (onetap, mobiharness, reciplan*), which differed only in the window name.
set -euo pipefail

REPO_DIR="$(git rev-parse --show-toplevel)"
TMUX_SESSION="${TMUX_SESSION:-main}"
WINDOW="${SESSION_NAME:-$(basename "$REPO_DIR")}"
MODE="${1:-kickoff}"

if tmux list-windows -t "$TMUX_SESSION" -F '#{window_name}' | grep -qx "$WINDOW"; then
  echo "tmux window ${TMUX_SESSION}:${WINDOW} already exists"
  exit 0
fi

case "$MODE" in
  kickoff)
    [ -f "$REPO_DIR/scripts/kickoff.md" ] || { echo "no scripts/kickoff.md in ${REPO_DIR}; use --continue or add one" >&2; exit 2; }
    CMD="claude --remote-control ${WINDOW} --name ${WINDOW} --permission-mode auto \"\$(cat scripts/kickoff.md)\""
    ;;
  --continue|continue)
    CMD="claude --continue --remote-control ${WINDOW} --name ${WINDOW} --permission-mode auto"
    ;;
  *)
    echo "usage: launch-session.sh [kickoff|--continue]" >&2
    exit 2
    ;;
esac

# Window holds a login shell (like the other project windows) so it survives
# claude exiting; the command is typed into it rather than used as the pane
# process.
tmux new-window -d -t "$TMUX_SESSION" -n "$WINDOW" -c "$REPO_DIR"
tmux send-keys -t "${TMUX_SESSION}:${WINDOW}" "$CMD" Enter
echo "launched ${TMUX_SESSION}:${WINDOW} (${MODE}) in ${REPO_DIR}"
