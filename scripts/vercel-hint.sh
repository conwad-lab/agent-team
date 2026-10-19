#!/usr/bin/env bash
# Print setup advice only; never change the project's Vercel configuration.
set -euo pipefail
ROOT=${1:?usage: vercel-hint.sh project-root}
if [ -e "$ROOT/vercel.json" ] || [ -d "$ROOT/.vercel" ]; then
  echo 'Settings → Build and Deployment → Ignored Build Step: bash .claude/skills/agent-team/bin/vercel-ignore-build'
fi
