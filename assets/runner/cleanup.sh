#!/bin/sh
# Runs before and after every job (ACTIONS_RUNNER_HOOK_JOB_STARTED/COMPLETED), team/RUNNER.md § Rules "Clean between jobs".
# GitHub runs hooks with bash -e: a real cleanup error stops the job (fail closed), so guard only the empty cases.
if [ -n "$GITHUB_WORKSPACE" ] && [ -d "$GITHUB_WORKSPACE" ]; then
  find "$GITHUB_WORKSPACE" -mindepth 1 -delete
fi
rm -f "$HOME/.docker/config.json" "$HOME/.npmrc" "$HOME/.netrc" "$HOME/.git-credentials"
ids=$(docker ps -aq)
if [ -n "$ids" ]; then docker rm -f $ids >/dev/null; fi
docker volume prune -af >/dev/null   # -a: named volumes too, not only anonymous ones
docker network prune -f >/dev/null
