#!/usr/bin/env bash
# Synthetic Git history only; no Vercel account or credentials needed.
set -eu
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; n=0
ok()  { n=$((n+1)); echo "ok $n - $1"; }
nok() { n=$((n+1)); fail=1; echo "not ok $n - $1"; }
# Isolate commits and configuration from the developer's Git setup.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Fixture GIT_AUTHOR_EMAIL=fixture@example.invalid
export GIT_COMMITTER_NAME=Fixture GIT_COMMITTER_EMAIL=fixture@example.invalid
REAL_GIT=$(command -v git)
git init -q --bare "$T/origin.git"
git init -q "$T/repo"
cd "$T/repo"
git remote add origin "$T/origin.git"
mkdir -p src
printf 'initial\n' > src/file
git add . && git commit -qm initial
BASE=$(git rev-parse HEAD)
change() {
  git reset -q --hard "$BASE"
  mkdir -p "$(dirname "$1")"
  printf 'changed\n' > "$1"
  git add . && git commit -qm fixture
  HEAD_SHA=$(git rev-parse HEAD)
}
check() {
  local expected=$1 label=$2 environment=$3 previous=$4 current=$5 actual=0 out
  out=$(VERCEL_ENV="$environment" VERCEL_GIT_PREVIOUS_SHA="$previous" VERCEL_GIT_COMMIT_SHA="$current" bash "$SKILL/bin/vercel-ignore-build") || actual=$?
  if [ "$actual" -eq "$expected" ]; then ok "$label"; else nok "$label (exit $actual: $out)"; fi
}
change .team/story.md
BOARD=$HEAD_SHA
for environment in production preview; do
  check 0 "$environment skips board-only diff" "$environment" "$BASE" "$BOARD"
done
change src/file
CODE=$HEAD_SHA
for environment in production preview; do
  check 1 "$environment builds code changes" "$environment" "$BASE" "$CODE"
done
mkdir -p .team
printf 'story\n' > .team/story.md
git add . && git commit -qm board-after-code
MIXED=$(git rev-parse HEAD)
check 1 'whole interval catches earlier code commit' preview "$BASE" "$MIXED"
git reset -q --hard "$BASE"
mkdir -p .team
printf 'story\n' > .team/story.md
printf 'code\n' > src/file
git add . && git commit -qm mixed
check 1 'mixed commit builds' preview "$BASE" "$(git rev-parse HEAD)"
for path in .teamx/story.md foo/.team/story.md .team; do
  change "$path"
  check 1 "outside root .team/: $path" preview "$BASE" "$HEAD_SHA"
done
git reset -q --hard "$BASE"
mkdir -p .team
git mv src/file .team/file
git commit -qm rename
check 1 'rename from code to board builds' preview "$BASE" "$(git rev-parse HEAD)"
change $'.team/space and\nnewline.md'
check 0 'board filename with space and newline skips' preview "$BASE" "$HEAD_SHA"
change $'src/a\n.team/b'
check 1 'newline cannot disguise a code path as board' preview "$BASE" "$HEAD_SHA"
for revision in '' invalid 1234 0000000000000000000000000000000000000000 0000000000000000000000000000000000000000000000000000000000000000 ffffffffffffffffffffffffffffffffffffffff; do
  check 1 "invalid or unavailable previous revision: ${revision:-missing}" preview "$revision" "$BOARD"
  check 1 "invalid or unavailable current revision: ${revision:-missing}" preview "$BASE" "$revision"
done
check 1 'empty diff builds' preview "$BASE" "$BASE"
check 1 'empty environment builds' '' "$BASE" "$BOARD"
check 1 'unknown environment builds' development "$BASE" "$BOARD"
actual=0
env -u VERCEL_ENV -u VERCEL_GIT_PREVIOUS_SHA -u VERCEL_GIT_COMMIT_SHA bash "$SKILL/bin/vercel-ignore-build" >/dev/null || actual=$?
if [ "$actual" -eq 1 ]; then ok 'unset variables build'; else nok 'unset variables build'; fi
# A shallow checkout must fetch the missing previous deployment revision.
git reset -q --hard "$BOARD"
git push -q origin HEAD:refs/heads/fixture
git clone -q --depth=1 --branch fixture "file://$T/origin.git" "$T/shallow"
cd "$T/shallow"
if git cat-file -e "$BASE^{commit}" 2>/dev/null; then nok 'fetch fixture starts without base'; else ok 'fetch fixture starts without base'; fi
check 0 'missing local previous revision fetched from origin' preview "$BASE" "$BOARD"
# Check the other endpoint's fetch branch too.
git clone -q --depth=1 --branch fixture "file://$T/origin.git" "$T/shallow-current"
cd "$T/shallow-current"
check 0 'missing local current revision fetched from origin' production "$BOARD" "$BASE"
cd "$T/repo"
mkdir -p "$T/bin"
cat > "$T/bin/git" <<'WRAPPER'
#!/usr/bin/env bash
if [ "$1" = diff ]; then exit 128; fi
exec "$REAL_GIT" "$@"
WRAPPER
chmod +x "$T/bin/git"
export REAL_GIT
PATH="$T/bin:$PATH" check 1 'failed diff builds' preview "$BASE" "$BOARD"
exit "$fail"
