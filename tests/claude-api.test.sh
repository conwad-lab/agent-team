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
    if [ -f "$ST/hook_race" ] && [[ "$body" == "claude-api: started "* ]]; then
      jq '. + [{id: 11, user: {login: "conwad-lab"}, body: "claude-api: started other on mini for 10"}]' "$ST/comments.json" > "$ST/c.n" && mv "$ST/c.n" "$ST/comments.json"
    fi
    jq --arg b "$body" '(map(.id) | max + 1) as $i | . + [{id: $i, user: {login: "conwad-lab"}, body: $b}]' "$ST/comments.json" > "$ST/c.n" && mv "$ST/c.n" "$ST/comments.json"; jq '{id: ([.[].id] | max)}' "$ST/comments.json" | out ;;
  "DELETE repos/o/r/issues/comments/"*) id="${url##*/}"; jq --argjson i "$id" 'map(select(.id != $i))' "$ST/comments.json" > "$ST/c.n" && mv "$ST/c.n" "$ST/comments.json"; echo '{}' ;;
  "GET repos/o/r/pulls/1") cat "$ST/pr.json" | out ;;
  "POST repos/o/r/pulls/1/reviews") echo "$body" > "$ST/review_posted"; echo '{}' ;;
  "DELETE repos/o/r/issues/1/labels/"*) echo '{}' ;;
  "GET repos/o/r/pulls/1/reviews"*) cat "$ST/pr_reviews.json" 2>/dev/null || echo '[]' ;;
  "GET repos/o/r/pulls/1/comments"*) [ ! -f "$ST/fail_inline" ] || { echo "HTTP 502" >&2; exit 1; }; cat "$ST/pr_inline.json" 2>/dev/null || echo '[]' ;;
  "GET repos/o/r2/pulls?"*) echo "HTTP 502" >&2; exit 1 ;;
  "GET repos/o/r/pulls?"*) echo '[]' | out ;;
  "POST repos/o/r/pulls") echo '{"number":7}' | out ;;
  "POST repos/o/r/issues/7/labels") echo '[]' ;;
  "POST repos/o/r/issues/7/comments") echo '{"id":1}' | out ;;
  "GET repos/o/r") echo '{"default_branch":"main"}' | out ;;
  *) echo "fake gh: unhandled $method $url" >&2; exit 1 ;;
esac
G
cat > "$T/bin/claude" <<'C'
#!/usr/bin/env bash
# fake claude: writes review.md and result.json in the directory its prompt names, per $ST/claude_mode
prompt="$2"
case "$(cat "$ST/claude_mode")" in plan*)
  d="$(printf '%s' "$prompt" | grep -o '[^ ]*/result\.json' | head -1)"; d="${d%/result.json}"
  mkdir -p .team/plans; echo plan > .team/plans/one.md
  case "$(cat "$ST/claude_mode")" in
    planfile)  echo x > code.py ;;
    plancommit) echo x > code.py; git add code.py; git -c user.email=a@b -c user.name=t commit -qm sneaky ;;
    planrename) git mv README .team/plans/readme.md ;;
    plantoken) echo "github_pat_FAKE0123456789abcdefghijkl" >> .team/plans/one.md ;;
  esac
  echo '{"plan":true,"slug":"one","pr_title":"board: one","issue_title":"1: one","order":"codex-cli: build\nPlan: .team/plans/one.md"}' > "$d/result.json"
  echo '{"total_cost_usd": 1.5}'; exit 0 ;;
esac
dir="$(printf '%s' "$prompt" | grep -o '[^ ]*/review\.md' | head -1)"; dir="${dir%/review.md}"
echo "$ANTHROPIC_API_KEY" > "$ST/key_seen"; cp -r "$dir/context" "$ST/context_seen" 2>/dev/null; [ -z "${GH_TOKEN:-}" ] || echo leaked > "$ST/gh_leak"
case "$(cat "$ST/claude_mode")" in
  approve) printf -- '---\nverdict: approve\n---\nok\n' > "$dir/review.md"; echo '{"verdict":"approve","needs_human":"","summary":"fine"}' > "$dir/result.json" ;;
  human)   printf -- '---\nverdict: approve\n---\nok\n' > "$dir/review.md"; echo '{"verdict":"approve","needs_human":"Human-merge path","summary":"fine"}' > "$dir/result.json" ;;
  leak)    printf -- '---\nverdict: approve\n---\ngithub_pat_FAKE0123456789abcdefghijkl\n' > "$dir/review.md"; echo '{"verdict":"approve","needs_human":"","summary":"fine"}' > "$dir/result.json" ;;
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
  jq -n --arg s "$HEAD0" '{title:"1: x",head:{sha:$s,ref:"feat/1-x",repo:{full_name:"o/r"}},base:{ref:"main"},mergeable_state:"clean",updated_at:"2026-11-26T00:00:00Z"}' > "$ST/pr.json"
  # Codex's finished review of the feature commit, as its summary comment shows it
  jq --arg s "$HEAD0" '. + [{id: 12, user: {login: "chatgpt-codex-connector[bot]"}, body: ("<!-- codex-review-state:v1 &#123;\"code_review\":&#123;\"commit_sha\":\"" + $s + "\",\"has_any_findings\":false,\"has_unresolved_findings\":false,\"status\":\"completed\"&#125;&#125; -->")}]' "$ST/comments.json" > "$ST/c.n" && mv "$ST/c.n" "$ST/comments.json"
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

# 6c. a token-shaped string in review.md stops the run before anything is committed or posted
reset; echo leak > "$ST/claude_mode"; out="$(tick)"
check "token in review.md bounces" 'jq -e "any(.[]; .body | test(\"^judge-claude: bounced\"))" "$ST/comments.json" >/dev/null'
check "token never reached the branch" '! git -C "$T/gh/o/r.git" ls-tree -r --name-only feat/1-x | grep -q "^.team/reviews/"'
check "token never reached GitHub" '[ ! -s "$ST/review_posted" ]'

# 6d. the Judge is handed Codex's reviews, findings and status as files; no finished Codex review means needs_human
reset; echo '[{"id":3,"state":"COMMENTED","body":"P1 finding"}]' > "$ST/pr_reviews.json"; out="$(tick)"
check "context: PR title and Codex review handed over" 'jq -e ".title == \"1: x\"" "$ST/context_seen/pr.json" >/dev/null && grep -q "P1 finding" "$ST/context_seen/reviews.json"'
check "context: Codex status handed over" 'grep -q "completed" "$ST/context_seen/codex-status.txt"'
reset; jq 'map(select(.user.login != "chatgpt-codex-connector[bot]"))' "$ST/comments.json" > "$ST/c.n" && mv "$ST/c.n" "$ST/comments.json"; out="$(tick)"
check "no Codex review: approve becomes needs-the-human" 'jq -e "any(.[]; .body | test(\"^judge-claude: approve [0-9a-f]{40} needs the human: no finished Codex review\"))" "$ST/comments.json" >/dev/null'
check "no Codex review: not an approval" '! jq -e "any(.[]; .body | test(\"^judge-claude: approved\"))" "$ST/comments.json" >/dev/null'
rm -f "$ST/pr_reviews.json"

# 6e. the review context cannot be read: the run bounces without Claude and without a review
reset; touch "$ST/fail_inline"; out="$(tick)"
check "failed inline fetch bounces" 'jq -e "any(.[]; .body | test(\"^judge-claude: bounced\"))" "$ST/comments.json" >/dev/null'
check "failed inline fetch: Claude never ran" '[ ! -f "$ST/key_seen" ]'
check "failed inline fetch: no review posted" '[ ! -s "$ST/review_posted" ]'

# 6f. the head is a merge of main: Codex's finished review of an ancestor does not cover it
( cd "$T/seed" && git checkout -q main && echo m > main.txt && git add -A && git commit -qm main2 && git push -q origin main \
  && git checkout -q feat/1-x && git merge -q --no-ff -m "merge main" main && git push -q origin feat/1-x )
MERGEHEAD="$(git -C "$T/seed" rev-parse HEAD)"
reset; git -C "$T/gh/o/r.git" update-ref refs/heads/feat/1-x "$MERGEHEAD"
jq --arg s "$MERGEHEAD" '.head.sha = $s' "$ST/pr.json" > "$ST/p" && mv "$ST/p" "$ST/pr.json"
out="$(tick)"
check "merge head: Codex's review of an ancestor does not count" 'grep -q "none for $MERGEHEAD" "$ST/context_seen/codex-status.txt"'
check "merge head: needs the human" 'jq -e "any(.[]; .body | test(\"needs the human: no finished Codex review\"))" "$ST/comments.json" >/dev/null'
git -C "$T/gh/o/r.git" update-ref refs/heads/feat/1-x "$HEAD0"

# 6g. the same evidence the merge workflow accepts: a receipt review naming the commit counts, a failed summary does not
reset; jq 'map(select(.user.login != "chatgpt-codex-connector[bot]"))' "$ST/comments.json" > "$ST/c.n" && mv "$ST/c.n" "$ST/comments.json"
jq -n --arg s "${HEAD0:0:10}" '[{id: 3, commit_id: "x", user: {login: "chatgpt-codex-connector[bot]"}, body: ("<!-- codex-review-receipt:v1 -->\n**Reviewed commit:** `" + $s + "`")}]' > "$ST/pr_reviews.json"
out="$(tick)"
check "a receipt review on the head counts as a finished review" 'jq -e "any(.[]; .body | test(\"^judge-claude: approved\"))" "$ST/comments.json" >/dev/null'
reset; jq 'map(select(.user.login != "chatgpt-codex-connector[bot]"))' "$ST/comments.json" > "$ST/c.n" && mv "$ST/c.n" "$ST/comments.json"
jq -n '[{id: 3, commit_id: "x", user: {login: "chatgpt-codex-connector[bot]"}, body: "<!-- codex-review-receipt:v1 -->\n**Reviewed commit:** `deadbeef00`"}]' > "$ST/pr_reviews.json"
out="$(tick)"
check "a receipt for another commit does not count" 'grep -q "none for $HEAD0" "$ST/context_seen/codex-status.txt" && jq -e "any(.[]; .body | test(\"needs the human: no finished Codex review\"))" "$ST/comments.json" >/dev/null'
reset; jq --arg s "$HEAD0" 'map(if .user.login == "chatgpt-codex-connector[bot]" then .body = ("<!-- codex-review-state:v1 &#123;\"code_review\":&#123;\"commit_sha\":\"" + $s + "\",\"has_any_findings\":false,\"has_unresolved_findings\":false,\"status\":\"failed\"&#125;&#125; -->") else . end)' "$ST/comments.json" > "$ST/c.n" && mv "$ST/c.n" "$ST/comments.json"
out="$(tick)"
check "a failed Codex review does not count" 'grep -q "failed" "$ST/context_seen/codex-status.txt" && jq -e "any(.[]; .body | test(\"needs the human: no finished Codex review\"))" "$ST/comments.json" >/dev/null'
rm -f "$ST/pr_reviews.json"

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

# 7c. a run budget that does not fit in what is left of the cap does not start (19.90 spent of 20, run budget 3)
reset; mkdir -p "$T/work"; printf '%s\tjudge\t19.9\n' "$(date -u +%F)" > "$T/work/claude-spend.log"
out="$(tick)"
check "budget larger than the remainder: no claim" '! jq -e "any(.[]; .body | test(\"^claude-api: started\"))" "$ST/comments.json" >/dev/null'

# 7d. a run that reports no cost is charged its whole budget
reset; echo nofile > "$ST/claude_mode"; sed -i 's/echo .{"total_cost_usd": 0.42, "result": "done"}./echo "{}"/' "$T/bin/claude"; out="$(tick)"
check "no cost report: the run budget goes in the ledger" 'grep -q "	3$" "$T/work/claude-spend.log"'
sed -i 's/^echo "{}"$/echo '"'"'{"total_cost_usd": 0.42, "result": "done"}'"'"'/' "$T/bin/claude"

# 7e. two claims for one order: the earlier one wins, the later withdraws and does not run
reset; touch "$ST/hook_race"; out="$(tick)"
check "losing claim withdrawn" '! jq -e "any(.[]; .body | test(\"^claude-api: started j\"))" "$ST/comments.json" >/dev/null'
check "loser ran nothing" '[ ! -f "$ST/key_seen" ]'

# 7f. planner: a board PR for a clean plan; refused for code, a Claude commit or a token in the diff
cat > "$T/plan.env" <<ENVEOF
ENABLED=1
HOST=testmac
WORK_DIR="$T/work"
REPOS="o/r"
PLAN_REPOS="o/r"
ALLOW="conwad-lab"
POLL_SEC=1
ENVEOF
ptick() { CLAUDE_API_ENV="$T/plan.env" bash "$SKILL/bin/claude-api-poll" 2>&1; }
boards() { git -C "$T/gh/o/r.git" for-each-ref --format='%(refname)' 'refs/heads/board/*'; }
reset; echo '{"items":[]}' > "$ST/search.json"; echo plan > "$ST/claude_mode"; out="$(ptick)"
check "planner pushes a board branch" 'boards | grep -q one'
check "planner opens the PR" 'grep -q "^POST repos/o/r/pulls$" "$ST/calls"'
for m in planfile plancommit plantoken planrename; do
  reset; for b in $(boards); do git -C "$T/gh/o/r.git" update-ref -d "$b"; done
  echo '{"items":[]}' > "$ST/search.json"; echo "$m" > "$ST/claude_mode"; out="$(ptick)"
  check "planner refuses $m" '[ -z "$(boards)" ] && ! grep -q "^POST repos/o/r/pulls$" "$ST/calls"'
done

# 7g. a broken GitHub answer for one repo is logged with repo and phase and the other repos go on
cat > "$T/plan2.env" <<ENVEOF
ENABLED=1
HOST=testmac
WORK_DIR="$T/work"
REPOS="o/r2 o/r"
PLAN_REPOS="o/r2 o/r"
ALLOW="conwad-lab"
POLL_SEC=1
ENVEOF
reset; echo '{"items":[]}' > "$ST/search.json"; echo plan > "$ST/claude_mode"; for b in $(boards); do git -C "$T/gh/o/r.git" update-ref -d "$b"; done
out="$(CLAUDE_API_ENV="$T/plan2.env" bash "$SKILL/bin/claude-api-poll" 2>&1)"
check "failure logged with repo and phase (orders)" 'echo "$out" | grep -q "o/r2 orders: GitHub request failed"'
check "failure logged with repo and phase (plan)" 'echo "$out" | grep -q "o/r2 plan: GitHub request failed"'
check "the next repo is still planned" 'boards | grep -q one'

# 8. an order from a stranger is ignored
reset; echo '[{"id":10,"user":{"login":"mallory"},"body":"judge-claude: review"}]' > "$ST/comments.json"; out="$(tick)"
check "stranger's order ignored" '[ "$(jq length "$ST/comments.json")" = 1 ]'

echo "$n tests"; exit $fail
