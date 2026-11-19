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
# Images: dangling ones every job; every unused image and the build cache only when the machine is short of disk,
# so a job does not pull its images again each time. Never fatal: an image holds no secret this hook is here to remove.
docker image prune -f >/dev/null 2>&1 || true
free=$(df -Pk / 2>/dev/null | awk 'NR == 2 && $4 ~ /^[0-9]+$/ { print $4 }') || free=""
if [ -n "$free" ] && [ "$free" -lt "${RUNNER_MIN_FREE_KB:-10485760}" ]; then
  docker image prune -af >/dev/null 2>&1 || true
  docker builder prune -af >/dev/null 2>&1 || true
fi
