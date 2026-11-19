#!/usr/bin/env bash
# tests for bin/part-check (team/PARTS.md [P4]) in a temp git repo: one branch per case, cut from the same base.
# Run: bash tests/part-check.test.sh
set -u
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; n=0
ok()  { n=$((n+1)); echo "ok $n - $1"; }
nok() { n=$((n+1)); fail=1; echo "not ok $n - $1"; }
check() { if eval "$2"; then ok "$1"; else nok "$1"; fi; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
PC="$SKILL/bin/part-check"
R="$T/repo"; mkdir -p "$R"
g() { git -C "$R" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
g init -q -b main
mkdir -p "$R/src" "$R/tests" "$R/docs"
echo spine > "$R/src/api.ts"; echo old > "$R/src/old.ts"; echo keep > "$R/README.md"
g add -A; g commit -qm base
BASE="$(g rev-parse HEAD)"
printf 'I wrote the tests.\n\nHinder: inga\n\n' > "$T/inga.txt"
printf 'Wrote most of it.\nHinder: needs the schema name\n' > "$T/items.txt"
printf 'All done, no problems.\n' > "$T/nohinder.txt"
printf 'Hinder: inga\nThen I also changed something.\n' > "$T/notlast.txt"
printf 'Done.\r\nHinder: inga\r\n' > "$T/crlf.txt"

part() { g checkout -q -b "$1" "$BASE"; mkdir -p "$R/tests" "$R/docs"; }   # start a case on its own branch
commit() { g add -A; g commit -qm "part $1"; }
run() { rc=0; bash "$PC" --dir "$R" --base "$BASE" "$@" > "$T/out" 2> "$T/err" || rc=$?; }

part a; echo t > "$R/tests/api.test.ts"; commit a
run --files "tests/api.test.ts" --report "$T/inga.txt" --check "true"
check "(a) clean part, Hinder: inga, check true → 0" '[ "$rc" = 0 ] && [ "$(cat "$T/out")" = "Hinder: inga" ]'
run --files "tests/api.test.ts" --report "$T/inga.txt"
check "(a) no --check → 0" '[ "$rc" = 0 ]'
run --files "./tests/api.test.ts src/never.ts" --report "$T/crlf.txt" --check "test -f tests/api.test.ts"
check "(a) ./ prefix, CRLF report, check runs in the worktree root → 0" '[ "$rc" = 0 ]'
(cd "$R/tests" && bash "$PC" --base "$BASE" --files "tests/api.test.ts" --report "$T/inga.txt" --check "test -f README.md") > /dev/null 2>&1
check "(a) run from a subdirectory without --dir → 0" '[ $? = 0 ]'

part b; echo t > "$R/tests/api.test.ts"; echo hacked >> "$R/src/api.ts"; commit b
run --files "tests/api.test.ts" --report "$T/inga.txt" --check "true"
check "(b) extra path → 1, named" '[ "$rc" = 1 ] && grep -q "outside the part.s list: src/api.ts" "$T/err"'

part c; echo t > "$R/tests/api.test.ts"; g rm -q src/old.ts; commit c
run --files "tests/api.test.ts" --report "$T/inga.txt" --check "true"
check "(c) deletion of an unlisted file → 1" '[ "$rc" = 1 ] && grep -q "outside the part.s list: src/old.ts" "$T/err"'

part d; g mv src/old.ts tests/api.test.ts; commit d
run --files "tests/api.test.ts" --report "$T/inga.txt" --check "true"
check "(d) rename from an unlisted path → 1" '[ "$rc" = 1 ] && grep -q "outside the part.s list: src/old.ts" "$T/err"'

part e; echo t > "$R/tests/api.test.ts"; commit e
run --files "tests/api.test.ts" --report "$T/nohinder.txt" --check "true"
check "(e) report without a Hinder line → 1" '[ "$rc" = 1 ] && [ ! -s "$T/out" ] && grep -q "last line" "$T/err"'
run --files "tests/api.test.ts" --report "$T/notlast.txt" --check "true"
check "(e) Hinder line not last → 1" '[ "$rc" = 1 ]'
run --files "tests/api.test.ts" --report "$T/missing.txt" --check "true"
check "(e) no report file → 1" '[ "$rc" = 1 ]'

run --files "tests/api.test.ts" --report "$T/items.txt" --check "true"
check "(f) Hinder items → 3, line printed" '[ "$rc" = 3 ] && [ "$(cat "$T/out")" = "Hinder: needs the schema name" ]'

run --files "tests/api.test.ts" --report "$T/inga.txt" --check "false"
check "(g) check false → 1" '[ "$rc" = 1 ] && grep -q "check failed: false" "$T/err"'
run --files "tests/api.test.ts" --report "$T/items.txt" --check "false"
check "(g) Hinder items and a failed check → 1, not 3" '[ "$rc" = 1 ]'
run --files "tests/api.test.ts" --report "$T/inga.txt" --check "echo CHECKOUT"
check "(g) the check's output stays off stdout" '[ "$rc" = 0 ] && [ "$(cat "$T/out")" = "Hinder: inga" ] && grep -q CHECKOUT "$T/err"'

part h; echo d > "$R/docs/a.md"; mkdir -p "$R/docs/deep"; echo d > "$R/docs/deep/b.md"; commit h
run --files "docs/" --report "$T/inga.txt" --check "true"
check "(h) listed directory docs/ allows docs/a.md and below → 0" '[ "$rc" = 0 ]'
run --files "docs" --report "$T/inga.txt" --check "true"
check "(h) docs without the slash is a file name, not a directory → 1" '[ "$rc" = 1 ]'
part h2; echo d > "$R/docs-private.md"; mkdir -p "$R/docsx"; echo d > "$R/docsx/a.md"; commit h2
run --files "docs/" --report "$T/inga.txt" --check "true"
check "(h) docs/ does not allow docsx/ or docs-private.md → 1" '[ "$rc" = 1 ] && [ "$(grep -c "outside the part" "$T/err")" = 2 ]'

# what Codex was asked to attack: files outside the committed diff, submodule pointers, a part off its base
part i; echo t > "$R/tests/api.test.ts"; commit i; echo stray > "$R/src/untracked.ts"
run --files "tests/api.test.ts" --report "$T/inga.txt" --check "true"
check "(i) untracked file left in the worktree → 1" '[ "$rc" = 1 ] && grep -q "uncommitted or untracked.*src/untracked.ts" "$T/err"'
rm "$R/src/untracked.ts"; echo edited >> "$R/src/api.ts"
run --files "tests/api.test.ts" --report "$T/inga.txt" --check "true"
check "(i) uncommitted change to a spine file → 1" '[ "$rc" = 1 ] && grep -q "uncommitted or untracked" "$T/err"'
g checkout -q -- src/api.ts

part j; echo t > "$R/tests/api.test.ts"; g add -A; g update-index --add --cacheinfo "160000,$BASE,vendor/rulebook"; g commit -qm "part j"
run --files "tests/api.test.ts" --report "$T/inga.txt" --check "true"
check "(j) submodule pointer outside the list → 1" '[ "$rc" = 1 ] && grep -q "outside the part.s list: vendor/rulebook" "$T/err"'
g reset -q --hard

part k
run --files "tests/api.test.ts" --report "$T/inga.txt" --check "true"
check "(k) no commit since the base → 1" '[ "$rc" = 1 ] && grep -q "committed no change" "$T/err"'

g checkout -q --orphan l; g rm -rqf . ; mkdir -p "$R/tests"; echo t > "$R/tests/api.test.ts"; commit l
run --files "tests/api.test.ts" --report "$T/inga.txt" --check "true"
check "(l) branch that does not contain the base → 1" '[ "$rc" = 1 ] && grep -q "not an ancestor" "$T/err"'
rc=0; bash "$PC" --dir "$R" --base nosuchsha --files "tests/api.test.ts" --report "$T/inga.txt" > /dev/null 2>&1 || rc=$?
check "(l) unknown base → 1" '[ "$rc" = 1 ]'

g checkout -q a
for bad in "/" "/etc/passwd" "../x" "a/../b" "." ; do
  run --files "$bad" --report "$T/inga.txt"
  [ "$bad" = "." ] && { check "usage: --files . is a file name and allows nothing → 1" '[ "$rc" = 1 ]'; continue; }
  check "usage: --files $bad → 2" '[ "$rc" = 2 ]'
done
run --files "*" --report "$T/inga.txt" --check "true"
check "usage: * is not a glob → 1" '[ "$rc" = 1 ]'
rc=0; bash "$PC" --dir "$R" --files "tests/api.test.ts" --report "$T/inga.txt" > /dev/null 2>&1 || rc=$?
check "usage: no --base → 2" '[ "$rc" = 2 ]'
run --files "" --report "$T/inga.txt"
check "usage: empty --files → 2" '[ "$rc" = 2 ]'
rc=0; bash "$PC" --base "$BASE" --files x --report "$T/inga.txt" --dir "$T" > /dev/null 2>&1 || rc=$?
check "usage: --dir outside a git worktree → 2" '[ "$rc" = 2 ]'
rc=0; bash "$PC" --base > /dev/null 2>&1 || rc=$?
check "usage: flag without a value → 2" '[ "$rc" = 2 ]'
check "bash 3.2: no mapfile, readarray, associative arrays or case modification" '! grep -nE "mapfile|readarray|declare -A|\\$\\{[A-Za-z_]+(,,|\\^\\^)" "$PC"'

echo "1..$n"; exit $fail
