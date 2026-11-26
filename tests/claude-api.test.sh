#!/usr/bin/env bash
# tests for bin/claude-api-poll (judge, merge, cap and credit paths) with a fake gh (state in files), a fake claude, a
# fake security and a local bare repo as GitHub. Run: bash tests/claude-api.test.sh
set -u
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "${T:?}"' EXIT
fail=0; n=0
ok()  { n=$((n+1)); echo "ok $n - $1"; }
nok() { n=$((n+1)); fail=1; echo "not ok $n - $1"; }
check() { if eval "$2"; then ok "$1"; else nok "$1"; fi; }

ST="$T/state"; mkdir -p "$T/bin" "$ST" "$T/home" "$T/gh/o"
export ST GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 HOME="$T/home"

git init -q --bare -b main "$T/gh/o/r.git"
git clone -q "$T/gh/o/r.git" "$T/seed" 2>/dev/null
( cd "$T/seed" && git config user.email a@b && git config user.name t && mkdir -p .team && echo x > README && echo y > .team/team.md \
  && git add -A && git commit -qm init && git push -q origin HEAD:main && git checkout -qb feat/1-x && echo z > code.txt \
  && git add -A && git commit -qm feat && git push -q origin feat/1-x )
HEAD0="$(git -C "$T/seed" rev-parse HEAD)"

cat > "$T/bin/security" <<'S'
#!/usr/bin/env bash
case "$*" in *agent-team-claude-api-key*) echo sk-ant-FAKEKEY0123456789abcdef ;; *) echo github_pat_FAKE0123456789abcdefghijkl ;; esac
S
cat > "$T/bin/gh" <<'G'
#!/usr/bin/env bash
set -u
shift; url=""; method=GET; body=""; jqf=""
while [ $# -gt 0 ]; do
  case "$1" in
    -X) method="$2"; shift 2 ;;
    -f|-F) case "$2" in body=*) body="${2#body=}" ;; esac; shift 2 ;;
    --jq) jqf="$2"; shift 2 ;;
    --paginate) shift ;;
    *) [ -z "$url" ] && url="$1"; shift ;;
  esac
done
echo "$method $url" >> "$ST/calls"
out() { if [ -n "$jqf" ]; then jq -r "$jqf"; else cat; fi; }
case "$method $url" in
  "GET user") echo '{"login":"conwad-lab"}' | out ;;
  "GET search/issues"*) cat "$ST/search.json" | out ;;
  "GET repos/o/r/issues/1/comments"*) cat "$ST/comments.json" | out ;;
  "POST repos/o/r/issues/1/comments")
    jq --arg b "$body" '(map(.id) | max + 1) as $i | . + [{id: $i, user: {login: "conwad-lab"}, body: $b}]' "$ST/comments.json" > "$ST/c.n" && mv "$ST/c.n" "$ST/comments.json"; echo 1 | out ;;
  "GET repos/o/r/pulls/1") cat "$ST/pr.json" | out ;;
  "POST repos/o/r/pulls/1/reviews") echo "$body" > "$ST/review_posted"; echo '{}' ;;
  "DELETE repos/o/r/issues/1/labels/"*) echo '{}' ;;
  "GET repos/o/r/pulls?"*) echo '[]' ;;
  "GET repos/o/r") echo '{"default_branch":"main"}' | out ;;
  *) echo "fake gh: unhandled $method $url" >&2; exit 1 ;;
esac
G
cat > "$T/bin/claude" <<'C'
#!/usr/bin/env bash
# fake claude: writes review.md and result.json in the directory its prompt names, per $ST/claude_mode
prompt="$2"; dir="$(printf '%s' "$prompt" | grep -o '[^ ]*/review\.md' | head -1)"; dir="${dir%/review.md}"
echo "$ANTHROPIC_API_KEY" > "$ST/key_seen"; [ -z "${GH_TOKEN:-}" ] || echo leaked > "$ST/gh_leak"
case "$(cat "$ST/claude_mode")" in
  approve) printf -- '---\nverdict: approve\n---\nok\n' > "$dir/review.md"; echo '{"verdict":"approve","needs_human":"","summary":"fine"}' > "$dir/result.json" ;;
  human)   printf -- '---\nverdict: approve\n---\nok\n' > "$dir/review.md"; echo '{"verdict":"approve","needs_human":"Human-merge path","summary":"fine"}' > "$dir/result.json" ;;
  nocredit) echo "Your credit balance is too low to access the Anthropic API" >&2; exit 1 ;;
  nofile)  : ;;
esac
echo '{"total_cost_usd": 0.42, "result": "done"}'
C
chmod +x "$T/bin/"*
export PATH="$T/bin:$PATH"

cat > "$T/claude-api.env" <<EOF
ENABLED=1
HOST=testmac
HUMAN=Conny
WORK_DIR="$T/work"
REPOS="o/r"
PLAN_REPOS=""
ALLOW="conwad-lab"
POLL_SEC=1
EOF
export CLAUDE_API_ENV="$T/claude-api.env" GIT_BASE="file://$T/gh"

reset() {
  git -C "$T/gh/o/r.git" update-ref refs/heads/feat/1-x "$HEAD0"
  rm -rf "${T:?}/work" "${ST:?}"/*; echo approve > "$ST/claude_mode"
  echo '{"items":[{"repository_url":"https://api.github.com/repos/o/r","number":1}]}' > "$ST/search.json"
  echo '[{"id":10,"user":{"login":"conwad-lab"},"body":"judge-claude: review"}]' > "$ST/comments.json"
  jq -n --arg s "$HEAD0" '{head:{sha:$s,ref:"feat/1-x",repo:{full_name:"o/r"}},base:{ref:"main"},mergeable_state:"clean",updated_at:"2026-11-26T00:00:00Z"}' > "$ST/pr.json"
}
tick() { bash "$SKILL/bin/claude-api-poll" "$@" 2>&1; }

# 1. dry run says what it would do and writes nothing
reset; out="$(tick --dry-run)"
check "dry run names the judge run" 'echo "$out" | grep -q "would judge o/r#1"'
check "dry run posts nothing" '! grep -q "^POST" "$ST/calls"'

# 2. an approving run: claimed, reviewed, review pushed to the branch, approval comment names the new head
reset; out="$(tick)"
check "claim comment posted" 'jq -e "any(.[]; .body | test(\"^claude-api: started .* for 10\$\"))" "$ST/comments.json" >/dev/null'
check "approval comment posted" 'jq -e "any(.[]; .body | test(\"^judge-claude: approved [0-9a-f]{40}\"))" "$ST/comments.json" >/dev/null'
newhead="$(git -C "$T/gh/o/r.git" rev-parse feat/1-x)"
check "review file committed to the PR branch" 'git -C "$T/gh/o/r.git" show feat/1-x:.team/reviews/1-x.md | grep -q "verdict: approve"'
check "approval names the pushed head" 'jq -e --arg h "$newhead" "any(.[]; .body | startswith(\"judge-claude: approved \" + \$h))" "$ST/comments.json" >/dev/null'
check "review posted as a GitHub review" '[ -s "$ST/review_posted" ]'
check "claude saw the API key" 'grep -q sk-ant-FAKEKEY "$ST/key_seen"'
check "claude never saw a GitHub token" '[ ! -f "$ST/gh_leak" ]'
check "cost is in the ledger" 'grep -q "0.42" "$T/work/claude-spend.log"'
check "no key or token in any comment" '! grep -q -E "sk-ant-|github_pat_" "$ST/comments.json"'

# 3. merge phase: head matches the approval and the state is clean -> the merge line, once
jq -n --arg s "$newhead" '{head:{sha:$s,ref:"feat/1-x",repo:{full_name:"o/r"}},base:{ref:"main"},mergeable_state:"clean",updated_at:"2026-11-26T00:00:00Z"}' > "$ST/pr.json"
out="$(tick)"
check "merge line posted for the approved head" 'jq -r ".[].body" "$ST/comments.json" | grep -q "^agent-team-merge: $newhead\$"'
before="$(jq length "$ST/comments.json")"; out="$(tick)"
check "no second merge line" '[ "$(jq length "$ST/comments.json")" = "$before" ]'

# 4. checks not green yet: no merge line
jq '.mergeable_state = "blocked" | .updated_at = "2099-01-01T00:00:00Z"' "$ST/pr.json" > "$ST/p" && mv "$ST/p" "$ST/pr.json"
jq 'map(select(.body | startswith("Judge approve") | not))' "$ST/comments.json" > "$ST/c" && mv "$ST/c" "$ST/comments.json"
out="$(tick)"
check "blocked state waits" '! jq -r ".[].body" "$ST/comments.json" | grep -q "^agent-team-merge:"'

# 5. an exception that needs the human is not merged
reset; echo human > "$ST/claude_mode"; out="$(tick)"
check "needs-human outcome posted" 'jq -e "any(.[]; .body | test(\"^judge-claude: approve [0-9a-f]{40} needs the human: Human-merge path\"))" "$ST/comments.json" >/dev/null'
check "needs-human is not an approval" '! jq -e "any(.[]; .body | test(\"^judge-claude: approved\"))" "$ST/comments.json" >/dev/null'

# 6. claude writes nothing: bounced
reset; echo nofile > "$ST/claude_mode"; out="$(tick)"
check "missing result bounces" 'jq -e "any(.[]; .body | test(\"^judge-claude: bounced\"))" "$ST/comments.json" >/dev/null'

# 6b. credits gone: stop stamp, then nothing runs and nothing is retried
reset; echo nocredit > "$ST/claude_mode"; out="$(tick)"
check "credit refusal leaves a stop stamp" '[ -f "$T/work/.credits-out" ]'
cnt="$(jq length "$ST/comments.json")"; echo approve > "$ST/claude_mode"; out="$(tick)"
check "no run while stopped" '[ "$(jq length "$ST/comments.json")" = "$cnt" ]'

# 7. the daily cap stops judging
reset; mkdir -p "$T/work"; printf '%s\tjudge\t99\n' "$(date -u +%F)" > "$T/work/claude-spend.log"
out="$(tick)"
check "cap reached: no claim posted" '! jq -e "any(.[]; .body | test(\"^claude-api: started\"))" "$ST/comments.json" >/dev/null'

# 7b. past ACTIVE_UNTIL nothing new starts
reset; echo 'ACTIVE_UNTIL=2020-01-01' >> "$T/claude-api.env"; out="$(tick)"
check "past the end date: no claim posted" '! jq -e "any(.[]; .body | test(\"^claude-api: started\"))" "$ST/comments.json" >/dev/null'
sed -i '/^ACTIVE_UNTIL/d' "$T/claude-api.env"

# 8. an order from a stranger is ignored
reset; echo '[{"id":10,"user":{"login":"mallory"},"body":"judge-claude: review"}]' > "$ST/comments.json"; out="$(tick)"
check "stranger's order ignored" '[ "$(jq length "$ST/comments.json")" = 1 ]'

echo "$n tests"; exit $fail
