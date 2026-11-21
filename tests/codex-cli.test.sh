#!/usr/bin/env bash
# tests for bin/codex-cli-poll and bin/codex-cli-install --dry-run, with a fake gh (issue and comment state in
# files), a fake codex (behaviour per test), a fake security and a local bare repo as GitHub.
# Run: bash tests/codex-cli.test.sh
set -u
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; n=0
ok()  { n=$((n+1)); echo "ok $n - $1"; }
nok() { n=$((n+1)); fail=1; echo "not ok $n - $1"; }
check() { if eval "$2"; then ok "$1"; else nok "$1"; fi; }

FAKE_TOKEN="github_pat_FAKE0123456789abcdefghijkl"
ST="$T/state"; mkdir -p "$T/bin" "$T/home/.codex/sessions"
export ST FAKE_TOKEN FAKE_ME=conwad-lab GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

cat > "$T/bin/gh" <<'G'
#!/usr/bin/env bash
# fake gh api: state in $ST (issue_<n>.json, comments_<n>.json, pulls.json), every call logged to $ST/calls
set -u
[ "$1" = api ] || { echo "fake gh: only api" >&2; exit 1; }
shift
url=""; method=GET; body=""; input=""; jqf=""; tokseen="${GH_TOKEN:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    -X|--method) method="$2"; shift 2 ;;
    -f|-F) case "$2" in body=*) body="${2#body=}" ;; esac; shift 2 ;;
    --input) input="$2"; shift 2 ;;
    --jq|-q) jqf="$2"; shift 2 ;;
    --paginate) shift ;;
    *) [ -z "$url" ] && url="$1"; shift ;;
  esac
done
echo "$method $url" >> "$ST/calls"
[ "$tokseen" = "$FAKE_TOKEN" ] || echo "NO-TOKEN $url" >> "$ST/calls"
out() { if [ -n "$jqf" ]; then jq -r "$jqf"; else cat; fi; }
num() { printf '%s' "$url" | sed -E 's#^repos/[^/]+/[^/]+/issues/([0-9]+).*#\1#'; }
case "$method $url" in
  "GET search/issues"*)
    for f in "$ST"/issue_*.json; do [ -f "$f" ] && jq -c 'select(.state=="open" and ([.labels[].name]|index("codex-cli")))' "$f"; done \
      | jq -s '{items: map({repository_url: "https://api.github.com/repos/o/r", number})}' | out ;;
  "GET user") echo "{\"login\":\"$FAKE_ME\"}" | out ;;
  "GET repos/o/r") echo '{"default_branch":"main"}' | out ;;
  "GET repos/o/r/issues/"*"/comments"*)
    if [ -f "$ST/hook_fail_reread" ] && grep -q "codex-cli: started" "$ST/comments_$(num).json"; then echo "HTTP 502" >&2; exit 1; fi
    cat "$ST/comments_$(num).json" | out ;;
  "POST repos/o/r/issues/"*"/comments")
    i="$(num)"; c="$ST/comments_$i.json"
    first="$(printf '%s\n' "$body" | head -1)"
    if [ -f "$ST/hook_fail_outcome" ] && [ "$first" = "codex-cli: done" ]; then rm -f "$ST/hook_fail_outcome"; echo "HTTP 503" >&2; exit 1; fi
    if [ -f "$ST/hook_fail_bounce" ] && [ "$first" = "codex-cli: bounced" ]; then rm -f "$ST/hook_fail_bounce"; echo "HTTP 503" >&2; exit 1; fi
    if [ -f "$ST/hook_race" ] && [[ "$first" == "codex-cli: started "* ]]; then
      jq --arg b "codex-cli: started other-run on mini for ${first##* for }" '. + [{id: 1500, user: {login: "conwad-lab"}, body: $b}]' "$c" > "$c.n" && mv "$c.n" "$c"
    fi
    if [ -f "$ST/hook_unlabel" ] && [[ "$first" == "codex-cli: started "* ]]; then
      jq '.labels = []' "$ST/issue_$i.json" > "$ST/x" && mv "$ST/x" "$ST/issue_$i.json"
    fi
    id=$(( $(jq '[.[].id] | max // 1000' "$c") + 100 ))
    jq --argjson id "$id" --arg b "$body" --arg u "$FAKE_ME" '. + [{id: $id, user: {login: $u}, body: $b}]' "$c" > "$c.n" && mv "$c.n" "$c"
    if [ -f "$ST/hook_lose_claim" ] && [[ "$first" == "codex-cli: started "* ]]; then rm -f "$ST/hook_lose_claim"; echo "HTTP 502" >&2; exit 1; fi
    echo "{\"id\":$id}" | out ;;
  "DELETE repos/o/r/issues/comments/"*)
    id="${url##*/}"
    for c in "$ST"/comments_*.json; do jq --argjson id "$id" 'map(select(.id != $id))' "$c" > "$c.n" && mv "$c.n" "$c"; done ;;
  "GET repos/o/r/issues/"*) cat "$ST/issue_$(num).json" | out ;;
  "GET repos/o/r/pulls?"*) cat "$ST/pulls.json" 2>/dev/null | jq '[.[] | select(.state=="open")]' | out ;;
  "POST repos/o/r/pulls")
    jq '. + {state: "open", html_url: "https://github.com/o/r/pull/77", number: 77}' "$input" > "$ST/pr_new.json"
    jq -s '.' "$ST/pr_new.json" > "$ST/pulls.json"
    out < "$ST/pr_new.json" ;;
  *) echo "fake gh: unhandled $method $url" >&2; exit 1 ;;
esac
G

cat > "$T/bin/codex" <<'C'
#!/usr/bin/env bash
# fake codex exec: behaviour from $ST/mode; records argv, env and the prompt
set -u
last=""; prev=""
for a in "$@"; do [ "$prev" = -o ] && last="$a"; prev="$a"; done
echo "$*" > "$ST/codex_args"
env > "$ST/codex_env"
cat > "$ST/prompt"
sess="$HOME/.codex/sessions/s-$$.jsonl"
mode="$(cat "$ST/mode")"
echo '{"start":1}' > "$sess"
case "$mode" in
  ok)       echo hi > hello.txt; printf -- '- AC1: hello.txt written\n\nHinder: inga\n' > "$last" ;;
  nohinder) echo hi > hello.txt; printf 'done, all good\n' > "$last" ;;
  hinder)   echo hi > hello.txt; printf 'partial\nHinder: the plan does not say which file holds the config\n' > "$last" ;;
  token)    echo "t=$FAKE_TOKEN" > hello.txt; printf 'Hinder: inga\n' > "$last" ;;
  github)   echo hi > hello.txt; mkdir -p .github/workflows; echo x > .github/workflows/x.yml; printf 'Hinder: inga\n' > "$last" ;;
  listed)   echo hi > hello.txt; mkdir -p .github/workflows; echo x > .github/workflows/ci.yml; printf 'Hinder: inga\n' > "$last" ;;
  red)      echo bye > other.txt; printf 'Hinder: inga\n' > "$last" ;;
  stall)    sleep 30 ;;
  crash)    echo hi > hello.txt; exit 7 ;;
  failexit) echo hi > hello.txt; printf 'Hinder: inga\n' > "$last"; exit 7 ;;
  hindertok) echo hi > hello.txt; printf 'Hinder: saw %s in the env\n' "$FAKE_TOKEN" > "$last" ;;
  bodytok)  echo hi > hello.txt; printf -- '- AC1: token %s\nHinder: inga\n' "$FAKE_TOKEN" > "$last" ;;
  tokenbin) echo hi > hello.txt; printf '\000\001t=%s\000' "$FAKE_TOKEN" > blob.bin; printf 'Hinder: inga\n' > "$last" ;;
  unicode)  echo hi > hello.txt; mkdir -p .github/workflows; echo x > ".github/workflows/\303\251.yml"; printf 'Hinder: inga\n' > "$last" ;;
  agents)   echo hi > hello.txt; printf -- '- **Test before commit:** `touch PWNED`\n' >> AGENTS.md; printf 'Hinder: inga\n' > "$last" ;;
  proof)    echo hi > hello.txt; mkdir -p tests; echo 'test -f hello.txt' > tests/hello.test.sh; printf 'Hinder: inga\n' > "$last" ;;
  planedit) echo hi > hello.txt; mkdir -p tests; echo 'test -f hello.txt' > tests/hello.test.sh
            printf '\n## Work order\nProof: tests/hello.test.sh — touch %s/PWNED3\n' "$ST" > .team/plans/001-x.md; printf 'Hinder: inga\n' > "$last" ;;
  fixonly)  echo again >> hello.txt; printf -- '- M1: fixed\n\nHinder: inga\n' > "$last" ;;
esac
C
cat > "$T/bin/security" <<'S'
#!/usr/bin/env bash
echo "security $*" >> "$ST/calls"
case "$1" in find-generic-password) printf '%s\n' "$FAKE_TOKEN" ;; *) exit 0 ;; esac
S
chmod +x "$T/bin/"*

# ---- a bare repo as GitHub: main has AGENTS.md (Test before commit) and a plan whose Files list .github/workflows/ci.yml
REMOTE="$T/remote"; mkdir -p "$REMOTE/o"
git init -q --bare -b main "$REMOTE/o/r.git"
SEED="$T/seed"; git init -q -b main "$SEED"
mkdir -p "$SEED/.team/plans"
printf -- '- **Test before commit:** `test -f hello.txt` and `test -z "${GH_ENTERPRISE_TOKEN:-}${GITHUB_ENTERPRISE_TOKEN:-}${GH_TOKEN:-}${GITHUB_TOKEN:-}"` <!-- the gate -->\n' > "$SEED/AGENTS.md"
printf '# Plan\n\n## Files\n- `hello.txt` — new\n- `.github/workflows/ci.yml` — the job\n\n## Steps\n1. x\n' > "$SEED/.team/plans/001-x.md"
git -C "$SEED" add -A && git -C "$SEED" -c user.name=t -c user.email=t@t commit -qm seed
git -C "$SEED" push -q "$REMOTE/o/r.git" main

CONF="$T/codex-cli.env"
cat > "$CONF" <<E
ENABLED=1
HOST=testmac
WORK_DIR=$T/work
REPOS="o/r"
ALLOW="Conwad-Lab"
HUMAN=Conny
GIT_BASE=file://$REMOTE
MODELS="astra=gpt-6-astra sol=gpt-6-sol-test broken=bad;id"
STALL_SEC=2
POLL_SEC=1
RUN_LIMIT_SEC=60
E
export CODEX_CLI_ENV="$CONF" HOME="$T/home"

ORDER='codex-cli: build
Branch: feat/001-x
Plan: .team/plans/001-x.md
PR title: 001: say hello

Goal: write hello.txt.
Hinder: inga or a list, as the very last line.'

reset() { # reset MODE [ORDER_AUTHOR]
  rm -rf "$ST" "$T/work"; mkdir -p "$ST"
  echo "$1" > "$ST/mode"
  echo '{"number":5,"state":"open","labels":[{"name":"codex-cli"}]}' > "$ST/issue_5.json"
  jq -n --arg b "$ORDER" --arg u "${2:-conwad-lab}" '[{id: 1000, user: {login: "someone"}, body: "story text"}, {id: 1001, user: {login: $u}, body: $b}]' > "$ST/comments_5.json"
  git -C "$SEED" push -q -f "$REMOTE/o/r.git" main
  git --git-dir="$REMOTE/o/r.git" branch -D feat/001-x >/dev/null 2>&1 || true
}
tick() { PATH="$T/bin:$PATH" bash "$SKILL/bin/codex-cli-poll" "$@" > "$T/out" 2> "$T/err"; echo $? > "$T/rc"; }
last_comment() { jq -r '.[-1].body' "$ST/comments_5.json"; }
bodies() { jq -r '.[].body' "$ST/comments_5.json"; }
remote_has() { git --git-dir="$REMOTE/o/r.git" rev-parse --verify --quiet "refs/heads/$1" >/dev/null; }

# 1 order from an allowed author → claimed, run, pushed, draft PR, outcome done
reset ok; GH_TOKEN=t1 GITHUB_TOKEN=t2 GH_ENTERPRISE_TOKEN=t3 GITHUB_ENTERPRISE_TOKEN=t4 tick
check "done: rc 0" '[ "$(cat $T/rc)" = 0 ]'
check "done: claim posted for the order" 'bodies | grep -q "^codex-cli: started .* on testmac for 1001$"'
check "done: outcome comment" 'last_comment | head -1 | grep -qx "codex-cli: done"'
check "done: PR link, Hinder and signature" 'last_comment | grep -q "pull/77 (draft), head [0-9a-f]\{40\}" && last_comment | grep -qx "Hinder: inga" && last_comment | grep -qx "— Coder (Codex CLI, testmac) on behalf of Conny"'
check "done: Test before commit green, comment stripped, no token variables" 'last_comment | grep -qF "Test before commit: green (\`test -f hello.txt && test -z" && ! last_comment | grep -q "the gate"'
check "done: branch pushed with hello.txt" 'git --git-dir="$REMOTE/o/r.git" show feat/001-x:hello.txt | grep -qx hi'
check "done: draft PR with title, head, base and Codex's answer" 'jq -e ".[0] | .draft == true and .title == \"001: say hello\" and .head == \"feat/001-x\" and .base == \"main\" and (.body | contains(\"AC1: hello.txt written\"))" $ST/pulls.json >/dev/null'
check "done: codex got model, sandbox and the order on stdin" 'grep -q -- "exec -m gpt-6-astra -s workspace-write -o .* -$" $ST/codex_args && grep -q "^PR title: 001: say hello$" $ST/prompt'
check "done: no GitHub token in codex env" '! grep -v "^FAKE_TOKEN=" $ST/codex_env | grep -qF "$FAKE_TOKEN" && ! grep -Eq "^(GH_|GITHUB_)(ENTERPRISE_)?TOKEN=" $ST/codex_env'
check "done: every gh call carried the token" '! grep -q NO-TOKEN $ST/calls'
check "done: worktree removed, run logged, no current file" '[ -z "$(ls -A $T/work/wt 2>/dev/null)" ] && grep -q "done" $T/work/runs.log && [ ! -f $T/work/current ] && [ ! -d $T/work/.lock ]'
check "done: token never in logs or output" '! grep -rqF "$FAKE_TOKEN" $T/work $T/out $T/err'

# 1b the same order again: the outcome follows it, nothing runs
cp "$ST/comments_5.json" "$T/c.json"; : > "$ST/calls"; tick
check "taken order is not run twice" '[ "$(jq length $ST/comments_5.json)" = "$(jq length $T/c.json)" ]'

# 2 order from another author → ignored
reset ok someone-else; tick
check "other author: no claim, no run" '! bodies | grep -q "codex-cli: started" && [ ! -f $ST/codex_args ]'

# 3 an earlier claim on the same order → own claim withdrawn
reset ok; touch "$ST/hook_race"; tick
check "race: own claim deleted, other's kept" '[ "$(bodies | grep -c "^codex-cli: started")" = 1 ] && bodies | grep -q "started other-run"'
check "race: codex not run" '[ ! -f $ST/codex_args ]'

# 4 label removed between search and claim → nothing runs
reset ok; touch "$ST/hook_unlabel"; tick
check "unlabelled: claim withdrawn, codex not run" '! bodies | grep -q "codex-cli: started" && [ ! -f $ST/codex_args ]'

# 5 no Hinder line → bounced, no push
reset nohinder; tick
check "no Hinder: bounced with reason" 'last_comment | head -2 | tr "\n" "|" | grep -q "^codex-cli: bounced|Reason: no Hinder line"'
check "no Hinder: nothing pushed" '! remote_has feat/001-x'

# 6 Hinder with items → blocked, branch pushed, no PR
reset hinder; tick
check "Hinder items: blocked, Hinder copied" 'last_comment | head -1 | grep -qx "codex-cli: blocked" && last_comment | grep -qx "Hinder: the plan does not say which file holds the config"'
check "Hinder items: branch pushed, no PR" 'remote_has feat/001-x && [ ! -f $ST/pulls.json ]'

# 7 the token in the diff → guard, no push
reset token; tick
check "token: bounced by the guard" 'last_comment | grep -q "^Reason: guard: the diff contains a GitHub token"'
check "token: nothing pushed, token not echoed" '! remote_has feat/001-x && ! grep -rqF "$FAKE_TOKEN" $ST/comments_5.json $T/out $T/err $T/work/runs.log'

# 8 .github/ not in the plan's Files → guard; listed in Files → allowed
reset github; tick
check "wall file not in Files: guard, no push" 'last_comment | grep -q "^Reason: guard: .github/workflows/x.yml" && ! remote_has feat/001-x'
reset listed; tick
check "wall file listed in Files: done" 'last_comment | head -1 | grep -qx "codex-cli: done"'

# 9 stall → bounced
reset stall; tick
check "stall: bounced as stalled" 'last_comment | grep -q "^Reason: stalled"'
check "stall: nothing pushed" '! remote_has feat/001-x'

# 10 a started run with no outcome (host slept) → bounced on the next tick
reset ok; mkdir -p "$T/work/repos" "$T/work/wt"; echo "o/r 5 old-run" > "$T/work/current"
git clone -q "$REMOTE/o/r.git" "$T/work/repos/o_r"
git -C "$T/work/repos/o_r" worktree add -q -b cli/old-run "$T/work/wt/old-run" origin/main
echo half > "$T/work/wt/old-run/half.txt"
jq '. + [{id: 1002, user: {login: "conwad-lab"}, body: "codex-cli: started old-run on testmac for 1001"}]' "$ST/comments_5.json" > "$T/c.json" && mv "$T/c.json" "$ST/comments_5.json"
tick
check "slept: old run marked bounced" 'bodies | grep -q "^Reason: host slept or stopped (run old-run on testmac never finished)"'
check "slept: the order is not run again by itself" '[ ! -f $ST/codex_args ]'
check "slept: the old worktree and its branch are removed" '[ ! -e $T/work/wt/old-run ] && ! git -C $T/work/repos/o_r rev-parse --verify --quiet refs/heads/cli/old-run >/dev/null && ! git -C $T/work/repos/o_r worktree list | grep -q old-run'

# 11 ENABLED=0 → no API call at all
reset ok; sed -i.bak 's/^ENABLED=1/ENABLED=0/' "$CONF"; : > "$ST/calls"; tick
check "disabled: no call" '[ "$(cat $T/rc)" = 0 ] && [ ! -s $ST/calls ]'
sed -i.bak 's/^ENABLED=0/ENABLED=1/' "$CONF"

# 12 Test before commit red → bounced with the tail, no push
reset red; tick
check "test red: bounced with the last lines" 'last_comment | grep -q "^Reason: test red" && last_comment | grep -q "<summary>Last 30 lines</summary>"'
check "test red: nothing pushed" '! remote_has feat/001-x'

# 12b Test before commit rewrites a tracked file → bounced, the untested commit is not pushed
reset ok; rm -rf "$T/fmt"; git clone -q "$REMOTE/o/r.git" "$T/fmt"
printf -- '- **Test before commit:** `test -f hello.txt && echo formatted > hello.txt`\n' > "$T/fmt/AGENTS.md"
git -C "$T/fmt" -c user.name=t -c user.email=t@t commit -qam "fmt gate" && git -C "$T/fmt" push -q origin main
tick
check "test rewrites files: bounced, nothing pushed" 'last_comment | grep -q "^Reason: Test before commit changed tracked files" && last_comment | grep -q "hello.txt" && ! remote_has feat/001-x'

# 13 Codex changing AGENTS.md cannot change the command the poller runs
reset agents; tick
check "Test before commit is read from main, not from Codex's diff" '[ ! -e $T/work/wt/PWNED ] && ! find $T/work -name PWNED | grep -q . && last_comment | grep -qF "green (\`test -f hello.txt && test -z"'

# 13b Codex exits without a last message → bounced, cleaned up, not "host slept" next tick
reset crash; tick
check "crash: bounced with no Hinder line and the exit code" 'last_comment | grep -q "^Reason: no Hinder line, codex exited 7"'
check "crash: worktree removed, no current file" '[ -z "$(ls -A $T/work/wt 2>/dev/null)" ] && [ ! -f $T/work/current ]'

# 13b2 Codex exits non-zero after writing a Hinder line → bounced, nothing pushed
reset failexit; tick
check "non-zero exit with Hinder: bounced, no push" 'last_comment | grep -q "^Reason: codex exited 7" && ! remote_has feat/001-x'

# 13b3 re-reading the issue after the claim fails → claim withdrawn, no recovery state left, codex not run
reset ok; touch "$ST/hook_fail_reread"; tick
check "re-read fails: claim deleted, no current file, codex not run" '! bodies | grep -q "codex-cli: started" && [ ! -f $T/work/current ] && [ ! -f $ST/codex_args ]'

# 13b4 a late outcome for an old order does not hide a newer order
reset ok
jq --arg b "$ORDER" '. + [{id: 1100, user: {login: "conwad-lab"}, body: "codex-cli: started r1 on testmac for 1001"},
  {id: 1200, user: {login: "conwad-lab"}, body: $b},
  {id: 1300, user: {login: "conwad-lab"}, body: "codex-cli: done\nRun: r1, 3 min, gpt-6-astra, order 1001"}]' "$ST/comments_5.json" > "$T/c.json" && mv "$T/c.json" "$ST/comments_5.json"
tick
check "newer order still taken after a late outcome for an old order" 'bodies | grep -q "^codex-cli: started .* for 1200$"'

# 13b5 the token inside a binary file → guard
reset tokenbin; tick
check "binary token: guard, no push" 'last_comment | grep -q "^Reason: guard: the diff contains a GitHub token" && ! remote_has feat/001-x'

# 13b6 a wall file with a non-ASCII name → guard
reset unicode; tick
check "non-ASCII wall path: guard, no push" 'last_comment | grep -q "^Reason: guard: .github/workflows/" && ! remote_has feat/001-x'

# 13b7 a forged claim by someone outside ALLOW does not suppress the order
reset ok
jq '. + [{id: 1050, user: {login: "someone-else"}, body: "codex-cli: started spoof on fake for 1001"}]' "$ST/comments_5.json" > "$T/c.json" && mv "$T/c.json" "$ST/comments_5.json"
tick
check "forged claim ignored: order built" 'last_comment | head -1 | grep -qx "codex-cli: done"'

# 13b8 the host-slept outcome is kept when GitHub refuses it
reset ok; mkdir -p "$T/work"; echo "o/r 5 old-run 1001" > "$T/work/current"; touch "$ST/hook_fail_bounce"
jq '. + [{id: 1002, user: {login: "conwad-lab"}, body: "codex-cli: started old-run on testmac for 1001"}]' "$ST/comments_5.json" > "$T/c.json" && mv "$T/c.json" "$ST/comments_5.json"
tick; tick
check "slept outcome retried on the next tick" 'bodies | grep -q "^Reason: host slept or stopped (run old-run" && [ -z "$(ls -A $T/work/pending 2>/dev/null)" ]'

# 13b9 a hanging Test before commit is stopped at the run limit
reset ok; printf -- '- **Test before commit:** `sleep 30`\n' > "$SEED/AGENTS.md"
git -C "$SEED" -c user.name=t -c user.email=t@t commit -qam hang; git -C "$SEED" push -q -f "$REMOTE/o/r.git" main
sed -i.bak 's/^RUN_LIMIT_SEC=60/RUN_LIMIT_SEC=4/' "$CONF"; s0=$(date +%s); tick; s1=$(date +%s)
sed -i.bak 's/^RUN_LIMIT_SEC=4/RUN_LIMIT_SEC=60/' "$CONF"; git -C "$SEED" reset -q --hard HEAD~1
check "hanging test: bounced at the time limit, quickly, no push" 'last_comment | grep -q "^Reason: time limit .* during Test before commit" && [ $((s1 - s0)) -lt 20 ] && ! remote_has feat/001-x && ! pgrep -f "sleep 30" >/dev/null'

# 13b10 a token in Codex's answer never reaches a comment or the PR body
reset hindertok; tick
check "token in the Hinder line: redacted in the outcome" 'last_comment | head -1 | grep -qx "codex-cli: blocked" && ! grep -qF "$FAKE_TOKEN" $ST/comments_5.json && last_comment | grep -q "\[redacted\]"'
reset bodytok; tick
check "token in the answer: redacted in the PR body" '[ -f $ST/pulls.json ] && ! grep -qF "$FAKE_TOKEN" $ST/pulls.json && grep -q "\[redacted\]" $ST/pulls.json'

# 13b11 the claim is saved but its answer is lost → the next tick bounces the order
reset ok; touch "$ST/hook_lose_claim"; tick
check "lost claim answer: recovery state kept, codex not run" '[ -f $T/work/current ] && [ ! -f $ST/codex_args ]'
tick
check "lost claim answer: bounced on the next tick, not built" 'bodies | grep -q "^Reason: host slept or stopped" && [ ! -f $ST/codex_args ]'

# 13c Test before commit with && inside one backtick command, and two commands
reset ok; printf -- '- **Test before commit:** `test -f hello.txt && true` and `true`\n' > "$SEED/AGENTS.md"
git -C "$SEED" -c user.name=t -c user.email=t@t commit -qam tbc; git -C "$SEED" push -q -f "$REMOTE/o/r.git" main; tick
check "Test before commit keeps && inside a command" 'last_comment | grep -q "green (.test -f hello.txt && true && true.)"'
git -C "$SEED" reset -q --hard HEAD~1

# 13d the outcome post fails once → kept and posted on the next tick
reset ok; touch "$ST/hook_fail_outcome"; tick
check "outcome kept when GitHub refuses it" '! bodies | grep -qx "codex-cli: done" && ls $T/work/pending/* >/dev/null 2>&1'
tick
check "outcome posted on the next tick, pending emptied" 'bodies | grep -qx "codex-cli: done" && [ -z "$(ls -A $T/work/pending)" ] && ! bodies | grep -q "host slept"'

# ---- v0.8.14: a model per order ([K7])
with_order() { # with_order MODE ORDER_TEXT: reset, then replace the order comment's body
  reset "$1"
  jq --arg b "$2" 'map(if .id == 1001 then .body = $b else . end)' "$ST/comments_5.json" > "$T/c.json" && mv "$T/c.json" "$ST/comments_5.json"
}
MORDER="$(printf '%s\n' "$ORDER" | sed 's/^PR title: .*/&\
Model: sol/')"
with_order ok "$MORDER"; tick
check "Model: sol runs the Sol id from MODELS" 'grep -q -- "exec -m gpt-6-sol-test -s workspace-write" $ST/codex_args && last_comment | head -1 | grep -qx "codex-cli: done"'
check "Model: sol is named in the outcome, the commit and the PR body" 'last_comment | grep -q "^Run: .* min, gpt-6-sol-test, order 1001$" && git --git-dir="$REMOTE/o/r.git" log -1 --format=%b feat/001-x | grep -q "Built by Codex CLI (gpt-6-sol-test) on testmac" && jq -r ".[0].body" $ST/pulls.json | grep -q "Built by Codex CLI (gpt-6-sol-test)"'
with_order ok "$(printf '%s\n' "$MORDER" | sed 's/^Model: sol$/Model: luna/')"; tick
check "unknown model: bounced with the name, codex not run, nothing pushed" 'last_comment | head -2 | tr "\n" "|" | grep -q "^codex-cli: bounced|Reason: order names model .luna., not in this host.s MODELS" && [ ! -f $ST/codex_args ] && ! remote_has feat/001-x'
with_order ok "$(printf '%s\n' "$MORDER" | sed 's/^Model: sol$/Model: gpt-6-astra; touch PWNED/')"; tick
check "Model line that is not a plain name: bounced, never passed to codex" 'last_comment | grep -q "^Reason: order.s Model line is not a plain lowercase name" && [ ! -f $ST/codex_args ] && ! find $T/work -name PWNED | grep -q .'
with_order ok "$(printf '%s\n' "$MORDER" | sed 's/^Model: sol$/Model: broken/')"; tick
check "a MODELS id that is not a plain id: bounced, codex not run" 'last_comment | grep -q "^Reason: order names model .broken., not in this host.s MODELS" && [ ! -f $ST/codex_args ]'
reset ok; tick
check "no Model line runs MODEL, also with MODELS set" 'grep -q -- "exec -m gpt-6-astra -s workspace-write" $ST/codex_args && last_comment | grep -q "^Run: .* min, gpt-6-astra, order 1001$"'
check "no Proof line in the plan: Proof not set, done as before" 'last_comment | grep -qx "Proof: not set" && last_comment | head -1 | grep -qx "codex-cli: done"'

# ---- v0.8.14: the plan's Proof ([K7])
plan_proof() { # plan_proof TEXT...: main's plan gets a `## Work order` holding the given lines (after a reset)
  rm -rf "$T/pp"; git clone -q "$REMOTE/o/r.git" "$T/pp"
  { printf '# Plan\n\n## Approach\nProof: tests/hello.test.sh — touch %s/PWNED4\n\n## Files\n- `hello.txt` — new\n- `tests/hello.test.sh` — new\n\n## Work order\n```\nGoal: say hello\n' "$ST"
    printf '%s\n' "$@"; printf 'Must not: push\n```\n\n## Steps\n1. x\nProof: tests/hello.test.sh — touch %s/PWNED5\n' "$ST"; } > "$T/pp/.team/plans/001-x.md"
  git -C "$T/pp" -c user.name=t -c user.email=t@t commit -qam "plan with a work order" && git -C "$T/pp" push -q origin main
}
GREEN='Proof: tests/hello.test.sh — sh tests/hello.test.sh && test -z "${GH_TOKEN:-}${GITHUB_TOKEN:-}" && touch '"$ST/PROOF_RAN"
reset ok; plan_proof "$GREEN"; tick
check "Proof file missing from the diff: bounced, command not run, nothing pushed" 'last_comment | grep -qx "Reason: proof: tests/hello.test.sh not in the diff" && last_comment | grep -qx "Proof: tests/hello.test.sh not in the diff" && ! remote_has feat/001-x && [ ! -e $ST/PROOF_RAN ]'
reset proof; plan_proof 'Proof: `tests/hello.test.sh` — `echo proof-says-no; false`'; tick
check "Proof command red: bounced with the last lines, nothing pushed" 'last_comment | grep -qx "Reason: proof red" && last_comment | grep -qx "Proof: red (tests/hello.test.sh)" && last_comment | grep -qx "proof-says-no" && ! remote_has feat/001-x'
reset proof; plan_proof "$GREEN"; GH_TOKEN=t1 GITHUB_TOKEN=t2 tick
check "Proof green: done, named in the outcome, test file pushed" 'last_comment | head -1 | grep -qx "codex-cli: done" && last_comment | grep -qx "Proof: green (tests/hello.test.sh)" && git --git-dir="$REMOTE/o/r.git" show feat/001-x:tests/hello.test.sh | grep -q hello.txt'
check "Proof ran, after Test before commit, without a token" 'last_comment | grep -qF "Test before commit: green" && [ -e $ST/PROOF_RAN ]'
check "a Proof line outside ## Work order is never run" '[ ! -e $ST/PWNED4 ] && [ ! -e $ST/PWNED5 ]'

# a fix order on the branch that already holds the test file: the Proof file is in the branch's diff against main
FIX='codex-cli: fix
Branch: feat/001-x
Plan: .team/plans/001-x.md
Model: sol

Fix: M1 hello.txt says too little'
jq --arg b "$FIX" '. + [{id: 5000, user: {login: "conwad-lab"}, body: $b}]' "$ST/comments_5.json" > "$T/c.json" && mv "$T/c.json" "$ST/comments_5.json"
echo fixonly > "$ST/mode"; tick
check "fix order: Proof file counted against the default branch, green, pushed on Sol" 'last_comment | head -1 | grep -qx "codex-cli: done" && last_comment | grep -qx "Proof: green (tests/hello.test.sh)" && git --git-dir="$REMOTE/o/r.git" show feat/001-x:hello.txt | grep -qx again && grep -q -- "exec -m gpt-6-sol-test " $ST/codex_args'

# the Proof command comes from the plan on the default branch: not from the order comment, not from Codex's diff
PORDER="$ORDER
Proof: tests/hello.test.sh — touch $ST/PWNED2"
with_order proof "$PORDER"; plan_proof "$GREEN"; tick
check "Proof in the order comment is ignored: the plan's command ran" 'last_comment | grep -qx "Proof: green (tests/hello.test.sh)" && [ -e $ST/PROOF_RAN ] && [ ! -e $ST/PWNED2 ]'
with_order proof "$PORDER"; tick
check "Proof only in the order comment: not set, never run" 'last_comment | grep -qx "Proof: not set" && last_comment | head -1 | grep -qx "codex-cli: done" && [ ! -e $ST/PWNED2 ]'
reset planedit; plan_proof "$GREEN"; tick
check "Codex rewriting the plan's Proof cannot change the command" '[ ! -e $ST/PWNED3 ] && [ -e $ST/PROOF_RAN ] && last_comment | grep -qx "Proof: green (tests/hello.test.sh)"'
reset proof; plan_proof 'Proof: tests/hello.test.sh'; tick
check "Proof line without a command: bounced, nothing pushed" 'last_comment | grep -q "^Reason: proof: the plan.s Proof line is not" && ! remote_has feat/001-x'
reset proof; plan_proof 'Proof: ../../etc/passwd — true'; tick
check "Proof file that is not a plain repo path: bounced" 'last_comment | grep -q "^Reason: proof: the plan.s Proof line is not" && ! remote_has feat/001-x'
reset proof; plan_proof 'Proof: tests/hello.test.sh — echo changed > hello.txt'; tick
check "Proof rewrites a tracked file: bounced, nothing pushed" 'last_comment | grep -q "^Reason: Proof changed tracked files" && ! remote_has feat/001-x'
reset hinder; plan_proof "$GREEN"; tick
check "blocked run: Proof not run" 'last_comment | head -1 | grep -qx "codex-cli: blocked" && last_comment | grep -qx "Proof: not run" && [ ! -e $ST/PROOF_RAN ]'
reset proof; plan_proof 'Proof: tests/hello.test.sh — sleep 30'
sed -i.bak 's/^RUN_LIMIT_SEC=60/RUN_LIMIT_SEC=4/' "$CONF"; s0=$(date +%s); tick; s1=$(date +%s)
sed -i.bak 's/^RUN_LIMIT_SEC=4/RUN_LIMIT_SEC=60/' "$CONF"
check "hanging Proof: bounced at the time limit, quickly, no push" 'last_comment | grep -q "^Reason: time limit .* during Proof" && [ $((s1 - s0)) -lt 20 ] && ! remote_has feat/001-x && ! pgrep -f "sleep 30" >/dev/null'

# 14 dry run posts nothing
reset ok; tick --dry-run
check "dry-run: names the order, posts nothing" 'grep -q "would take build order 1001 on o/r#5" $T/err && ! grep -q "^POST" $ST/calls'

# 15 the installer's dry run prints the plist it would write
PATH="$T/bin:$PATH" bash "$SKILL/bin/codex-cli-install" --dry-run > "$T/inst" 2>&1; irc=$?
check "installer dry-run: rc 0" '[ "$irc" = 0 ]'
check "installer dry-run: plist with label, interval and poller" 'grep -q "<string>se.agent-team.codex-cli</string>" $T/inst && grep -q "<integer>300</integer>" $T/inst && grep -q "codex-cli-poll</string>" $T/inst'
check "installer dry-run: wrote nothing" '[ ! -e $T/home/Library ] && [ ! -e $T/home/.config/agent-team ]'

# installer: the old-loop match leaves Conny's own Codex alone; typed values with # or & survive the config sed
eval "$(grep -m1 '^OLD_LOOPS=' "$SKILL/bin/codex-cli-install")"
eval "$(grep -m1 '^esc()' "$SKILL/bin/codex-cli-install")"
check "installer: old loops matched, own Codex not" 'printf "%s\n" "bash /Users/c/x/bin/coder" "bash /Users/c/x/bin/wait-for 30" "codex exec You are the Coder" | grep -Ecq "$OLD_LOOPS" && [ "$(printf "%s\n" "bash /Users/c/x/bin/coder" "bash /Users/c/x/bin/wait-for 30" "codex exec You are the Coder" | grep -Ec "$OLD_LOOPS")" = 3 ] && ! printf "%s\n" "codex" "/Applications/Codex.app/Contents/Resources/codex app-server" "node /Users/c/.vscode/extensions/openai.chatgpt/bin/codex" "codex resume" | grep -Eq "$OLD_LOOPS"'
eval "$(grep -m1 '^model_id()' "$SKILL/bin/codex-cli-install")"
eval "$(grep -m1 '^model_ok()' "$SKILL/bin/codex-cli-install")"
check "installer: a re-run reads the old model ids from the config's MODELS" '[ "$(model_id sol "astra=gpt-6-astra sol=my-sol.1")" = my-sol.1 ] && [ "$(model_id astra "astra=a_1 sol=s")" = a_1 ] && ! model_id sol "astra=a" >/dev/null && ! model_id sol "" >/dev/null'
check "installer: a model id must be a plain id" 'model_ok gpt-6-sol && model_ok "gpt-6.2_sol" && ! model_ok "a b" && ! model_ok "a;b" && ! model_ok ""'
check "installer: the example config has MODEL and MODELS lines the installer rewrites" '[ "$(sed -e "s#^MODEL=.*#MODEL=aa#" -e "s#^MODELS=.*#MODELS=\"astra=aa sol=ss\"#" "$SKILL/assets/codex-cli/codex-cli.env.example" | grep -c -x -e "MODEL=aa" -e "MODELS=\"astra=aa sol=ss\"")" = 2 ]'
check "installer dry-run: says it asks for the two model ids" 'grep -q "model ids for Astra and Sol" $T/inst'
check "installer: # and & in a typed value survive the config sed" '[ "$(echo "HOST=x" | sed -e "s#^HOST=.*#HOST=$(esc "a#b&c\\d")#")" = "HOST=a#b&c\\d" ]'

echo
[ "$fail" = 0 ] && echo "all $n passed" || echo "FAILED"
exit "$fail"
