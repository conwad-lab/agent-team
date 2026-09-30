#!/usr/bin/env bash
# Stop the team: tell the supervisors not to restart, then end the tmux session.
# Safe at any time — every role's state is in git; a story mid-flight resumes on next start.
WS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="${AGENT_TEAM_SESSION:-$(basename "$WS" | sed 's/-team$//')}"
touch "$WS/.stop"
tmux kill-session -t "$S" 2>/dev/null && echo "team stopped" || echo "team was not running"
