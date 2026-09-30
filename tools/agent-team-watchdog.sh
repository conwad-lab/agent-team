#!/usr/bin/env bash
# agent-team-watchdog — keeps unattended agent-team workspaces moving. No model calls.
# Runs every 15 min via launchd (se.wadbro.agent-team-watchdog). For every workspace under
# $ROOT that has open-team.sh + po/.team:
#   1. no tmux session and no .stop file (e.g. after a reboot)  -> start the team
#   2. a known Claude Code dialog in a pane                      -> answer it safely
#   3. a Claude role idle at an empty prompt on two checks in a row -> nudge it back into its loop
#   4. an unknown dialog ("Enter to confirm")                     -> leave it, notify
# Log: $ROOT/.agent-team-watchdog.log   State: $ROOT/.agent-team-watchdog/
set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.nvm/versions/node/v22.21.1/bin:/usr/bin:/bin:$PATH"
ROOT="${AGENT_TEAM_ROOT:-$HOME/WebProjects}"
STATE="$ROOT/.agent-team-watchdog"; LOG="$ROOT/.agent-team-watchdog.log"
mkdir -p "$STATE"
log()    { echo "$(date '+%F %T') $*" >> "$LOG"; }
notify() { osascript -e "display notification \"$1\" with title \"Agent team\"" >/dev/null 2>&1 || true; }
NUDGE='Continue your loop: follow the "On start" section of your role file (git pull, then run your wait-for / po-wait again). Do not end your turn while the loop is running.'

for ws in "$ROOT"/*/; do
  ws="${ws%/}"
  [ -x "$ws/open-team.sh" ] && [ -d "$ws/po/.team" ] || continue
  S="$(sed -n 's/^S=\([A-Za-z0-9._-]*\).*/\1/p' "$ws/open-team.sh" | head -1)"
  [ -n "$S" ] || S="$(basename "$ws" | sed 's/-team$//')"   # generic open-team.sh derives it from the folder
  [ -n "$S" ] || continue

  if ! tmux has-session -t "$S" 2>/dev/null; then
    if [ ! -e "$ws/.stop" ]; then
      log "$S: session missing, no .stop — starting team"
      (cd "$ws" && ./open-team.sh >/dev/null 2>&1)
      notify "$S: teamet startades om (sessionen saknades)"
    fi
    continue
  fi

  for pane in $(tmux list-panes -t "$S:team" -F '#{pane_index}' 2>/dev/null); do
    tgt="$S:team.$pane"
    title="$(basename "$(tmux display -p -t "$tgt" '#{pane_current_path}' 2>/dev/null)")"
    txt="$(tmux capture-pane -p -S -60 -t "$tgt" 2>/dev/null)"   # visible area + scrollback: small panes hide the spinner
    tail15="$(printf '%s\n' "$txt" | grep -v '^[[:space:]]*$' | tail -15)"
    key="$STATE/$S.$pane"

    # 2. known dialogs
    if printf '%s' "$tail15" | grep -q 'Teach auto mode'; then
      tmux send-keys -t "$tgt" Down; sleep 0.4; tmux send-keys -t "$tgt" Enter
      log "$S/$title: answered 'Teach auto mode' with 'Not now'"; rm -f "$key"; continue
    fi
    if printf '%s' "$tail15" | grep -q 'Yes, I trust this folder'; then
      tmux send-keys -t "$tgt" Down; sleep 0.4; tmux send-keys -t "$tgt" Enter
      log "$S/$title: trusted its own clone folder (first start)"; rm -f "$key"; continue
    fi
    # 4. unknown dialog: do not guess
    if printf '%s' "$tail15" | grep -q 'Enter to confirm'; then
      if [ ! -e "$key.dialog" ]; then
        log "$S/$title: unknown dialog — left for the human"; notify "$S/$title väntar på ett val i sitt fönster"
        touch "$key.dialog"
      fi
      continue
    fi
    rm -f "$key.dialog"

    # 3. idle Claude role: prompt visible, no running indicator, pane unchanged since last check
    printf '%s' "$tail15" | grep -q 'shift+tab to cycle' || { rm -f "$key"; continue; }   # Claude Code only; codex exec restarts itself
    # busy: a spinner line with elapsed time ("✽ Beboppin'… (4h 41m 30s)") means a turn or a long wait-for is running
    if printf '%s' "$tail15" | grep -Eq 'esc to interrupt|Running…|queued messages|… \(.*[0-9]+s\)'; then
      rm -f "$key"; continue
    fi
    printf '%s' "$tail15" | grep -q '❯' || { rm -f "$key"; continue; }
    sum="$(printf '%s' "$txt" | shasum | cut -c1-16)"
    if [ -f "$key" ] && [ "$(cat "$key")" = "$sum" ]; then
      tmux send-keys -t "$tgt" -l "$NUDGE"; sleep 0.4; tmux send-keys -t "$tgt" Enter
      log "$S/$title: idle two checks in a row — nudged back into its loop"; rm -f "$key"
    else
      echo "$sum" > "$key"
    fi
  done
done
# keep the log short
[ -f "$LOG" ] && tail -500 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
exit 0
