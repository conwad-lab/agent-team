# agent-team-watchdog

Keeps unattended agent-team workspaces under ~/WebProjects moving. Plain bash, no model calls, every 15 minutes via launchd.

What it does, per workspace (a folder with `open-team.sh` and `po/.team/`):
1. No tmux session and no `.stop` file (e.g. after a reboot): starts the team with `./open-team.sh`. `./stop-team.sh` writes `.stop`, so a team you stopped stays stopped.
2. Known Claude Code dialogs: "Teach auto mode…" → "Not now"; "Yes, I trust this folder" on first start → trust (only ever the role's own clone).
3. A Claude role sitting at an empty prompt, unchanged on two checks in a row (≥15 min): sends it back into its loop. Codex roles are skipped — their supervisor restarts them.
4. Any other dialog: left alone, logged, and a macOS notification is shown.

It never merges, never answers permission questions for commands, and never touches git.

Files: `~/WebProjects/agent-team-tools/agent-team-watchdog.sh`, `~/Library/LaunchAgents/se.wadbro.agent-team-watchdog.plist`.
Log: `~/WebProjects/.agent-team-watchdog.log`.
Stop it: `launchctl bootout gui/$(id -u)/se.wadbro.agent-team-watchdog`. Start again: `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/se.wadbro.agent-team-watchdog.plist`.
New workspaces are picked up automatically if they live directly under ~/WebProjects.
