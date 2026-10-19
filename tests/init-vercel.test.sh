#!/usr/bin/env bash
# Test the setup hint and full init with local-only fixture remotes.
set -eu
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; n=0
ok()  { n=$((n+1)); echo "ok $n - $1"; }
nok() { n=$((n+1)); fail=1; echo "not ok $n - $1"; }
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$T/home/.gitconfig"
export GIT_AUTHOR_NAME=Fixture GIT_AUTHOR_EMAIL=fixture@example.invalid
export GIT_COMMITTER_NAME=Fixture GIT_COMMITTER_EMAIL=fixture@example.invalid
mkdir -p "$T/home" "$T/project"
git config --global user.name Fixture
git config --global user.email fixture@example.invalid
HINT='Settings → Build and Deployment → Ignored Build Step: bash .claude/skills/agent-team/bin/vercel-ignore-build'
check_hint() {
  local expected=$1 label=$2 out
  out=$(bash "$SKILL/scripts/vercel-hint.sh" "$T/project")
  if [ "$out" = "$expected" ]; then ok "$label"; else nok "$label (got: $out)"; fi
}
check_hint '' 'no Vercel files gives no hint'
if [ ! -e "$T/project/vercel.json" ]; then ok 'hint creates no configuration'; else nok 'hint creates no configuration'; fi
printf '{"buildCommand":"fixture"}\n' > "$T/project/vercel.json"
cp "$T/project/vercel.json" "$T/expected.json"
check_hint "$HINT" 'vercel.json alone gives exact hint'
if cmp -s "$T/project/vercel.json" "$T/expected.json"; then ok 'hint preserves existing bytes'; else nok 'hint preserves existing bytes'; fi
mkdir "$T/project/.vercel"
check_hint "$HINT" 'both discovery paths give one hint'
rm "$T/project/vercel.json"
check_hint "$HINT" '.vercel alone gives exact hint'

full_init() {
  local mode=$1 ws="$T/$1" skill_dir output
  mkdir -p "$ws"
  git init -q --bare "$ws/origin.git"
  git init -q -b main "$ws/po"
  git -C "$ws/po" remote add origin "$ws/origin.git"
  skill_dir="$ws/po/.claude/skills/agent-team"
  mkdir -p "$skill_dir"
  # Only init's inputs; no developer Git configuration, hooks or remotes copied.
  cp -R "$SKILL/assets" "$SKILL/scripts" "$SKILL/workspace" "$skill_dir/"
  cp "$SKILL/SKILL.md" "$skill_dir/"
  if [ "$mode" = config ]; then cp "$T/expected.json" "$ws/po/vercel.json"; fi
  git -C "$ws/po" add .
  git -C "$ws/po" commit -qm fixture
  git -C "$ws/po" push -q -u origin main
  git --git-dir="$ws/origin.git" symbolic-ref HEAD refs/heads/main
  output="$ws/output"
  if (cd "$ws/po" && env HOME="$T/home" bash "$skill_dir/scripts/init.sh" --name Fixture) > "$output" 2>&1; then
    ok "full init succeeds ($mode)"
  else
    nok "full init succeeds ($mode)"
    cat "$output"
    return
  fi
  if [ "$mode" = config ]; then
    if grep -Fxq "$HINT" "$output"; then ok 'full init prints exact hint'; else nok 'full init prints exact hint'; fi
    if cmp -s "$T/expected.json" "$ws/po/vercel.json"; then ok 'full init preserves Vercel bytes'; else nok 'full init preserves Vercel bytes'; fi
  else
    if grep -Fq "$HINT" "$output"; then nok 'full init without Vercel gives no hint'; else ok 'full init without Vercel gives no hint'; fi
    if [ ! -e "$ws/po/vercel.json" ]; then ok 'full init creates no Vercel configuration'; else nok 'full init creates no Vercel configuration'; fi
  fi
  for clone in architect coder reviewer; do
    if [ "$mode" = config ]; then
      if cmp -s "$T/expected.json" "$ws/$clone/vercel.json"; then ok "$clone preserves Vercel bytes"; else nok "$clone preserves Vercel bytes"; fi
    else
      if [ ! -e "$ws/$clone/vercel.json" ]; then ok "$clone has no Vercel configuration"; else nok "$clone has no Vercel configuration"; fi
    fi
  done
}
full_init config
full_init absent
exit "$fail"
