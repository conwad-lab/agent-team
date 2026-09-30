#!/usr/bin/env bash
# Start the whole team, unattended, and leave it running.
#   ./open-team.sh          start (or attach if already running)
#   ./stop-team.sh          stop everything
# Each role runs under a supervisor loop: if a session dies (API 529, low memory, a stray
# Esc, Codex ending its turn) it is restarted after 60 s and re-reads the board — the board
# is derived from git, so a restart loses nothing. The tmux session is detached; attach with
# `tmux attach -t <session>`, detach with Ctrl-b d. caffeinate keeps the Mac awake.
# Session name: the workspace folder without "-team" (override with AGENT_TEAM_SESSION).
set -u
WS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="${AGENT_TEAM_SESSION:-$(basename "$WS" | sed 's/-team$//')}"
unset AGENT_TEAM_CODEX_FLAGS            # a stale export here once sent the coder to the wrong model
export BASH_MAX_TIMEOUT_MS="${BASH_MAX_TIMEOUT_MS:-3600000}"
L=.claude/skills/agent-team/bin

tmux has-session -t "$S" 2>/dev/null && { echo "session '$S' is running — attaching (Ctrl-b d to detach)"; exec tmux attach -t "$S"; }

for r in po architect coder reviewer; do
  def="$(git -C "$WS/$r" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
  git -C "$WS/$r" checkout -q "${def:-main}" 2>/dev/null || echo "warning: $r could not switch to ${def:-main} — check that clone" >&2
  git -C "$WS/$r" pull -q --rebase --autostash 2>/dev/null || echo "warning: pull failed in $r" >&2
  git -C "$WS/$r" submodule update -q --init 2>/dev/null
  [ -x "$WS/$r/$L/$r" ] || { echo "missing $r/$L/$r — is the team submodule checked out? (./team pull)" >&2; exit 1; }
done

# supervise <role>: restart the launcher whenever it exits; stop when $WS/.stop exists
sup() { echo "until [ -e '$WS/.stop' ]; do '$WS/$1/$L/$1'; [ -e '$WS/.stop' ] || { echo; echo '[$1 exited — restarting in 60 s, Ctrl-C to abort]'; sleep 60; }; done"; }

rm -f "$WS/.stop"
tmux new-session  -d -s "$S" -n team -c "$WS/po"        "$(sup po)"
tmux select-pane  -t "$S" -T po
tmux split-window -t "$S" -c "$WS/architect" "$(sup architect)"
tmux select-pane  -t "$S" -T architect
tmux split-window -t "$S" -c "$WS/coder"     "$(sup coder)"
tmux select-pane  -t "$S" -T coder
tmux split-window -t "$S" -c "$WS/reviewer"  "$(sup reviewer)"
tmux select-pane  -t "$S" -T reviewer
tmux select-layout -t "$S" tiled
tmux set-option -t "$S" pane-border-status top >/dev/null 2>&1
if command -v caffeinate >/dev/null; then
  tmux new-window -d -t "$S" -n keepawake "caffeinate -i"   # lives as long as the session
fi
echo "team started in tmux session '$S' (detached). Attach: tmux attach -t $S   Board: ./team status   Stop: ./stop-team.sh"
