#!/usr/bin/env bash
# tests for the script in assets/root/.github/workflows/agent-team-merge.yml, run with a fake gh.
# Run: bash tests/agent-team-merge.test.sh
set -u
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
WF="$SKILL/assets/root/.github/workflows/agent-team-merge.yml"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; n=0
ok()  { n=$((n+1)); echo "ok $n - $1"; }
nok() { n=$((n+1)); fail=1; echo "not ok $n - $1"; }

cmp -s "$WF" "$SKILL/.github/workflows/agent-team-merge.yml" && ok "repo copy equals the template" || nok "repo copy equals the template"
sed -n '/# --- begin agent-team-merge script/,/# --- end agent-team-merge script/p' "$WF" | sed 's/^          //' > "$T/merge.sh"
[ -s "$T/merge.sh" ] && ok "script extracted" || nok "script extracted"

S=0123456789abcdef0123456789abcdef01234567
mkdir -p "$T/bin"
cat > "$T/bin/gh" <<'G'
#!/usr/bin/env bash
echo "$*" >> "$FAKE/calls"
case "$*" in
  "api repos/o/r/pulls/7") cat "$FAKE/pr.json" ;;
  "api repos/o/r/contents/.team?ref=main") [ -f "$FAKE/team-500" ] && { echo "HTTP 502: Bad Gateway" >&2; exit 1; }; [ -f "$FAKE/has-team" ] && echo '[]' || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; } ;;
  "api --paginate repos/o/r/pulls/7/files --jq"*) printf '%s\n' .team/reviews/007-x.md .team/reviews/007-x.response.md src/a.js ;;
  "api repos/o/r/contents/.team/reviews/007-x.md?ref="*) [ -f "$FAKE/review-500" ] && { echo "HTTP 502: Bad Gateway" >&2; exit 1; }; base64 < "$FAKE/review.md" ;;
  "api repos/o/r/contents/.team/reviews/007-x.response.md?ref="*) printf 'verdict: approve\n' | base64 ;;
  "api --paginate repos/o/r/issues/7/comments --jq"*) if [ -f "$FAKE/comments.json" ]; then jq -r "${*: -1}" "$FAKE/comments.json"; else cat "$FAKE/comments" 2>/dev/null; fi ;;
  "api --paginate repos/o/r/issues/7/reactions --jq"*) cat "$FAKE/pr-reactions" 2>/dev/null ;;
  "api --paginate repos/o/r/issues/comments/11/reactions --jq"*) cat "$FAKE/c11-reactions" 2>/dev/null ;;
  "api repos/o/r/git/ref/heads/feat --jq .object.sha") cat "$FAKE/branch-sha" ;;
  "api --paginate repos/o/r/pulls/7/reviews --jq"*) cat "$FAKE/reviews" 2>/dev/null ;;
  "api -X PUT repos/o/r/pulls/7/merge"*) [ -f "$FAKE/refuse" ] && { echo "Required status check is expected" >&2; exit 1; } ; echo '{"merged":true}' ;;
  *) : ;;
esac
G
chmod +x "$T/bin/gh"

run() { # $1 = comment body; uses $T/case/*
  : > "$FAKE/calls"
  REPO=o/r PR=7 BODY="$1" COMMENT_URL=u AFTER_MERGE_WORKFLOWS="${AMW:-}" GH_TOKEN=x PATH="$T/bin:$PATH" bash "$FAKE/../merge.sh" > "$FAKE/out" 2>&1; echo $? > "$FAKE/rc"
}
setup() { # $1 title  $2 draft  $3 head
  export FAKE="$T/case"; rm -rf "$FAKE"; mkdir -p "$FAKE"
  printf '{"state":"open","draft":%s,"title":"%s","head":{"sha":"%s","ref":"feat","repo":{"full_name":"o/r"}},"base":{"ref":"main"}}' "$2" "$1" "$3" > "$FAKE/pr.json"
  touch "$FAKE/has-team"; printf -- '---\nverdict: approve\n---\n' > "$FAKE/review.md"; printf '9\tchatgpt-codex-connector[bot]\tfalse\n' > "$FAKE/comments"; echo "$3" > "$FAKE/branch-sha"
}
merged() { grep -q "^api -X PUT repos/o/r/pulls/7/merge -f sha=$S -f merge_method=squash" "$FAKE/calls"; }
said()   { grep -q -- "$1" "$FAKE/calls"; }

setup "feat: x" false $S; run "Merge on agreement: Judge approve, head $S
agent-team-merge: $S"
merged && said "Merged by agent-team-merge: head $S" && said "DELETE repos/o/r/git/refs/heads/feat" && [ "$(cat "$FAKE/rc")" = 0 ] && ok "agreement: merges the pinned head, deletes the branch, says so" || nok "agreement merge"

setup "feat: x" false $S; run "no marker here"
[ ! -s "$FAKE/calls" ] && [ "$(cat "$FAKE/rc")" = 0 ] && ok "no marker line: no calls" || nok "no marker line"

setup "feat: x" false $S; run "text agent-team-merge: $S"
[ ! -s "$FAKE/calls" ] && ok "marker not at line start: ignored" || nok "marker not at line start"

setup "feat: x" false ffffffffffffffffffffffffffffffffffffffff; run "agent-team-merge: $S"
! merged && said "not the pinned $S" && [ "$(cat "$FAKE/rc")" = 1 ] && ok "head moved: refused with a comment" || nok "head moved"

setup "feat: x" true $S; run "agent-team-merge: $S"
! merged && said "is a draft" && ok "draft: refused" || nok "draft"

setup "feat: x" false $S; printf 'verdict: request-changes\n' > "$FAKE/review.md"; run "agent-team-merge: $S"
! merged && said "no review file" && ok "no approving review file: refused (a response file does not count)" || nok "no approving review file"

setup "feat: x" false $S; printf '11\tconwad-lab\ttrue\n' > "$FAKE/comments"; run "agent-team-merge: $S"
! merged && said "no Codex" && ok "no Codex on the PR: refused" || nok "no Codex"

setup "board: order" false $S; printf 'verdict: request-changes\n' > "$FAKE/review.md"; : > "$FAKE/comments"; run "agent-team-merge: $S"
merged && ok "board PR: no review file or Codex needed" || nok "board PR"

setup "feat: x" false $S; rm "$FAKE/has-team"; printf 'verdict: request-changes\n' > "$FAKE/review.md"; run "agent-team-merge: $S"
merged && ok "repo without .team (agent-team itself): Codex enough" || nok "repo without .team"

setup "feat: x" false $S; printf '11\tconwad-lab\ttrue\n' > "$FAKE/comments"; echo 'chatgpt-codex-connector[bot]' > "$FAKE/c11-reactions"; run "agent-team-merge: $S"
merged && ok "Codex 👍 on the @codex request comment counts" || nok "Codex 👍 on request comment"

setup "feat: x" false $S; : > "$FAKE/comments"; echo 'chatgpt-codex-connector[bot]' > "$FAKE/pr-reactions"; run "agent-team-merge: $S"
merged && ok "Codex 👍 on the PR counts" || nok "Codex 👍 on the PR"

setup "feat: x" false $S; { printf -- '---\nverdict: approve\n---\n'; head -c 1000000 /dev/zero | tr '\0' 'x' | fold -w 100; } > "$FAKE/review.md"; run "agent-team-merge: $S"
merged && ok "large approving review file (grep stops early, base64 must not fail the test): merges" || nok "large approving review file"

setup "feat: x" false $S; touch "$FAKE/review-500"; run "agent-team-merge: $S"
! merged && said "could not read .team/reviews/007-x.md" && [ "$(cat "$FAKE/rc")" = 1 ] && ok "review file unreadable: refused, names the file" || nok "review file unreadable"

setup "feat: x" false $S; touch "$FAKE/team-500"; run "agent-team-merge: $S"
! merged && said "could not tell whether the repo has .team/" && ok ".team lookup error (not 404): refused" || nok ".team lookup error"

setup "feat: x" false $S; echo ffffffffffffffffffffffffffffffffffffffff > "$FAKE/branch-sha"; run "agent-team-merge: $S"
merged && ! said "DELETE repos/o/r/git/refs/heads/feat" && ok "branch moved after the merge: kept" || nok "branch moved: kept"

setup "feat: x" false $S; touch "$FAKE/refuse"; run "agent-team-merge: $S"
said "GitHub refused the merge: Required status check" && ! said "Merged by" && [ "$(cat "$FAKE/rc")" = 1 ] && ok "GitHub refuses (checks): says why, no success comment" || nok "GitHub refuses"

setup "feat: x" false $S; AMW="deploy.yml" run "agent-team-merge: $S"
said "actions/workflows/deploy.yml/dispatches -f ref=main" && ok "after-merge workflows dispatched on the base branch" || nok "after-merge dispatch"

# v0.8.6: a usage-limit reply and Codex's status summary are not a review (wording from agent-team #24, #25)
BOT='chatgpt-codex-connector[bot]'
QUOTA='You have reached your Codex usage limits for code reviews. You can see your limits in the [Codex usage dashboard](https://chatgpt.com/codex/cloud/settings/usage).'
SUMMARY='<!-- codex-pull-request-review-summary -->\n<!-- codex-review-state:v1 {"code_review":{"status":"failed"}} -->\nCodex Review Summary: Failed'
cj() { jq -n --arg bot "$BOT" --arg q "$QUOTA" --arg s "$(printf "$SUMMARY")" "$1" > "$FAKE/comments.json"; }
setup "feat: x" false $S; cj '[{id:11,user:{login:"conwad-lab"},body:"@codex review"},{id:12,user:{login:$bot},body:$s},{id:13,user:{login:$bot},body:$q},{id:14,user:{login:$bot},body:"You have reached your Codex usage limits."}]'; run "agent-team-merge: $S"
! merged && said "no Codex comment, review or 👍" && [ "$(cat "$FAKE/rc")" = 1 ] && ok "only usage-limit replies and the status summary from Codex: refused" || nok "quota-only PR refused"

setup "feat: x" false $S; cj '[{id:11,user:{login:"conwad-lab"},body:"@codex review"},{id:13,user:{login:$bot},body:$q}]'; echo "$BOT" > "$FAKE/reviews"; run "agent-team-merge: $S"
merged && ok "usage-limit reply, then a Codex review: merges" || nok "quota then review"

setup "feat: x" false $S; cj '[{id:13,user:{login:$bot},body:$q},{id:15,user:{login:$bot},body:"<!-- codex-review-receipt:v1 -->\nCodex Review: no major issues in the usage limit rule."}]'; run "agent-team-merge: $S"
merged && ok "usage-limit reply, then a review receipt comment (even one that says usage limit): merges" || nok "quota then receipt"

setup "feat: x" false $S; cj '[{id:15,user:{login:$bot},body:"<!-- codex-review-receipt:v1 -->\n\nCodex Review: no major issues in the `codex-pull-request-review-summary` and `codex-review-state:` filter."}]'; run "agent-team-merge: $S"
merged && ok "a receipt that names the summary markers still counts (Codex M2 on #27)" || nok "receipt naming the summary markers"

setup "feat: x" false $S; cj '[{id:17,user:{login:$bot},body:"To use Codex here, [create an environment for this repo](https://chatgpt.com/codex/cloud/settings/environments)."},{id:18,user:{login:$bot},body:"I quote <!-- codex-review-receipt:v1 --> but did not review."}]'; run "agent-team-merge: $S"
! merged && said "no Codex comment, review or 👍" && ok "a setup notice, or the marker quoted mid-comment, is no review: refused" || nok "setup notice"

setup "feat: x" false $S; cj '[{id:19,user:{login:"someone"},body:"<!-- codex-review-receipt:v1 -->\nCodex Review: fine"}]'; run "agent-team-merge: $S"
! merged && ok "a receipt marker in someone else's comment: refused" || nok "foreign receipt"

setup "feat: x" false $S; cj '[{id:11,user:{login:"conwad-lab"},body:"@codex review"},{id:13,user:{login:$bot},body:$q}]'; echo "$BOT" > "$FAKE/c11-reactions"; run "agent-team-merge: $S"
merged && ok "usage-limit reply, then a Codex 👍 on the request: merges" || nok "quota then 👍"

setup "feat: x" false $S; cj '[{id:13,user:{login:$bot},body:$q}]'; run "Approved by Conny on a decision card, 2026-11-19, head $S
agent-team-merge: $S"
merged && ok "quota-only PR, the human's yes on a decision card: merges (Codex r3 M2 on #27)" || nok "card route"

setup "feat: x" false $S; cj '[{id:13,user:{login:$bot},body:$q}]'; printf 'verdict: request-changes\n' > "$FAKE/review.md"; run "Approved by Conny on a decision card, 2026-11-19, head $S
agent-team-merge: $S"
! merged && said "no review file" && ok "card route still needs the approving review file" || nok "card route without review file"

setup "feat: x" false $S; cj '[{id:13,user:{login:$bot},body:$q}]'; run "The PR was not Approved by Conny on a decision card, 2026-11-19, head $S
agent-team-merge: $S"
! merged && ok "the card line counts only at the start of a line" || nok "card line mid-line"

setup "feat: x" false $S; cj '[{id:13,user:{login:$bot},body:$q}]'; run "Approved by Conny on a decision card, 2026-11-19, head ffffffffffffffffffffffffffffffffffffffff
agent-team-merge: $S"
! merged && said "no Codex comment, review or 👍" && ok "a card approval of another head opens nothing (Codex r4 M1 on #27)" || nok "card for another head"

setup "feat: x" false $S; cj '[{id:13,user:{login:$bot},body:$q}]'; run "Approved by <human> on a decision card, <date>, head 0123456
Approved by Conny on a decision card, 2026-11-19, head 0123456 and more
agent-team-merge: $S"
! merged && ok "the format with placeholders, or trailing text after the head: opens nothing" || nok "card placeholders"

setup "feat: x" false $S; cj '[{id:13,user:{login:$bot},body:$q}]'; run "Approved by Conny on a decision card, 2026-11-19, head 0123456789ab
agent-team-merge: $S"
merged && ok "a card approval naming the pinned head by a short sha: merges" || nok "card short sha"

setup "feat: x" false $S; cj '[{id:16,user:{login:$bot},body:null}]'; run "agent-team-merge: $S"
! merged && said "no Codex comment, review or 👍" && ok "a Codex comment with an empty body: refused for that reason (jq does not fail)" || nok "null body"

# ---- v0.8.15: job auto merges a release bump on agreement by itself (story T)
sed -n '/# --- begin agent-team-auto script/,/# --- end agent-team-auto script/p' "$WF" | sed 's/^          //' > "$T/auto.sh"
[ -s "$T/auto.sh" ] && ok "auto script extracted" || nok "auto script extracted"
mkdir -p "$T/abin"
cat > "$T/abin/gh" <<'G'
#!/usr/bin/env bash
# a generic fake: GET <path> answers $A/<path with / as ~>, through --jq when given; writes are logged
echo "$*" >> "$A/calls"
shift # api
method=GET; path=""; jqx=""
while [ $# -gt 0 ]; do
  case "$1" in
    -X) method=$2; shift 2 ;;
    --paginate) shift ;;
    --jq) jqx=$2; shift 2 ;;
    -f) shift 2 ;;
    *) path=$1; shift ;;
  esac
done
if [ "$method" != GET ]; then
  case "$method $path" in "PUT "*/merge) [ -f "$A/refuse" ] && { echo "Required status check is expected" >&2; exit 1; } ;; esac
  echo '{}'; exit 0
fi
f="$A/${path//\//\~}"
[ -f "$f" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
if [ -n "$jqx" ]; then jq -r "$jqx" "$f"; else cat "$f"; fi
G
chmod +x "$T/abin/gh"
H=1111111111111111111111111111111111111111; C=2222222222222222222222222222222222222222; MB=3333333333333333333333333333333333333333
OLD=4444444444444444444444444444444444444444; NEW=5555555555555555555555555555555555555555
put() { printf '%s' "$2" > "$A/${1//\//\~}"; }
content() { jq -n --arg c "$(printf '%s' "$3" | base64 -w0)" '{content: $c}' > "$A/${1//\//\~}?ref=$2"; }
agents_md() { # $1 Auto-merge value  $2 Human-only value  $3 Builder value
  printf '# r\n\n## Project conventions\n\n- Stack: x\n\n## Team settings\n\n- **Builder:** %s\n- **Human-only paths:** %s\n- **Auto-merge:** %s\n\n## Papercuts\n\nx\n' "$3" "$2" "$1"
}
# the AGENTS.md patch for a Builder line change: line 9 of the file above
BPATCH='@@ -8,3 +8,3 @@
 
-- **Builder:** claude
+- **Builder:** codex-cli
 - **Human-only paths:** none'
asetup() {
  export A="$T/auto"; rm -rf "$A"; mkdir -p "$A"; : > "$A/calls"
  put repos/o/r '{"default_branch":"main"}'
  content repos/o/r/contents/AGENTS.md main "$(agents_md release none claude)"
  content repos/o/r/contents/AGENTS.md "$MB" "$(agents_md release none claude)"
  content repos/o/r/contents/AGENTS.md "$H" "$(agents_md release none codex-cli)"
  put repos/o/r/pulls/7 "{\"state\":\"open\",\"draft\":false,\"merged\":false,\"head\":{\"sha\":\"$H\",\"ref\":\"bump\",\"repo\":{\"full_name\":\"o/r\"}},\"base\":{\"ref\":\"main\"}}"
  jq -n --arg p "$BPATCH" '[{status:"modified",filename:".claude/skills/agent-team"},{status:"added",filename:".team/reviews/030-bump.md"},{status:"modified",filename:".team/team.md",patch:"@@ -8,1 +8,1 @@\n-  coder: codex\n+  coder: codex-cli"},{status:"modified",filename:"AGENTS.md",patch:$p}]' > "$A/repos~o~r~pulls~7~files"
  put "repos/o/r/compare/main...$H" "{\"behind_by\":0,\"merge_base_commit\":{\"sha\":\"$MB\"}}"
  put "repos/o/r/contents/.claude/skills/agent-team?ref=$MB" "{\"type\":\"submodule\",\"sha\":\"$OLD\"}"
  put "repos/o/r/contents/.claude/skills/agent-team?ref=$H" "{\"type\":\"submodule\",\"sha\":\"$NEW\"}"
  content repos/o/r/contents/.gitmodules main '[submodule ".claude/skills/agent-team"]
	path = .claude/skills/agent-team
	url = https://github.com/u/agent-team.git
'
  put repos/u/agent-team '{"default_branch":"main"}'
  put "repos/u/agent-team/compare/$OLD...$NEW" '{"status":"ahead"}'
  put "repos/u/agent-team/compare/$NEW...main" '{"status":"identical"}'
  content repos/o/r/contents/.team/reviews/030-bump.md "$H" $'---\nid: 030\nverdict: approve\n---\n# Review 030'
  put repos/o/r/pulls/7/reviews "[{\"user\":{\"login\":\"o\"},\"commit_id\":\"$H\",\"state\":\"COMMENTED\",\"body\":\"---\\nid: 030\\nverdict: approve\\n---\\n# Review 030\"}]"
  put repos/o/r/pulls/7/commits "[{\"sha\":\"$C\"},{\"sha\":\"$H\"}]"
  put "repos/o/r/commits/$C" '{"commit":{"committer":{"date":"2026-11-21T10:00:00Z"}},"files":[{"filename":".claude/skills/agent-team"},{"filename":"AGENTS.md"}]}'
  put "repos/o/r/commits/$H" '{"commit":{"committer":{"date":"2026-11-21T10:10:00Z"}},"files":[{"filename":".team/reviews/030-bump.md"}]}'
  jq -n --arg b "$BOT" '[{id:8,user:{login:"o"},created_at:"2026-11-21T10:01:00Z",body:"@codex review"},
    {id:9,user:{login:$b},created_at:"2026-11-21T10:05:00Z",body:"<!-- codex-review-receipt:v1 -->\n\nCodex Review: Didn'"'"'t find any major issues.\n\n**Reviewed commit:** `2222222`"}]' > "$A/repos~o~r~issues~7~comments"
  put repos/o/r/issues/7/reactions '[]'; put repos/o/r/issues/comments/8/reactions '[]'; put repos/o/r/pulls/7/comments '[]'
  put "repos/o/r/commits/$H/check-runs?per_page=100" '{"check_runs":[{"id":5,"name":"pr-check","status":"completed","conclusion":"success"}]}'
  put "repos/o/r/commits/$H/status" '{"statuses":[]}'
  put repos/o/r/git/ref/heads/bump "{\"object\":{\"sha\":\"$H\"}}"
}
arun() { : > "$A/calls"; REPO=o/r OWNER=o AGENT_ACCOUNT="${AA:-}" PRS="${APRS-7}" HEAD_SHA="${AHS:-}" AFTER_MERGE_WORKFLOWS="" GH_TOKEN=x PATH="$T/abin:$PATH" bash "$T/auto.sh" > "$A/out" 2>&1; echo $? > "$A/rc"; }
amerged() { grep -q "^api -X PUT repos/o/r/pulls/7/merge -f sha=$H -f merge_method=squash" "$A/calls"; }
asaid() { grep -q -- "$1" "$A/calls"; }
quiet() { ! grep -q 'issues/7/comments -f body' "$A/calls"; }

asetup; arun
amerged && asaid "Merged by agent-team-merge (release bump): head $H" && asaid "DELETE repos/o/r/git/refs/heads/bump" && [ "$(cat "$A/rc")" = 0 ] && ok "auto: a green release bump merges the head, deletes the branch, says so" || { nok "auto: green bump merges"; cat "$A/out"; }

asetup; content repos/o/r/contents/AGENTS.md main "$(agents_md none none claude)"; arun
! amerged && quiet && grep -q "do not say Auto-merge: release" "$A/out" && ok "auto: Auto-merge none does nothing" || nok "auto: Auto-merge none"

asetup; jq '(.[] | select(.filename == "AGENTS.md") | .patch) = "@@ -9,2 +9,2 @@\n - **Builder:** claude\n-- **Human-only paths:** none\n+- **Human-only paths:** `src/legal/**`"' "$A/repos~o~r~pulls~7~files" > "$A/x" && mv "$A/x" "$A/repos~o~r~pulls~7~files"; arun
! amerged && asaid "a line that only a card may change" && ok "auto: a change to Human-only paths in AGENTS.md refuses" || nok "auto: Human-only paths line"

asetup; jq '(.[] | select(.filename == "AGENTS.md") | .patch) = "@@ -5,1 +5,1 @@\n-- Stack: x\n+- Stack: y"' "$A/repos~o~r~pulls~7~files" > "$A/x" && mv "$A/x" "$A/repos~o~r~pulls~7~files"; arun
! amerged && asaid "line 5 (-) is outside ## Team settings" && ok "auto: an AGENTS.md line outside Team settings refuses" || nok "auto: outside Team settings"

asetup; jq '. + [{status:"modified",filename:".github/workflows/ci.yml"}]' "$A/repos~o~r~pulls~7~files" > "$A/x" && mv "$A/x" "$A/repos~o~r~pulls~7~files"; arun
! amerged && asaid ".github/workflows/ci.yml is outside a release bump" && ok "auto: a file under .github/ refuses" || nok "auto: .github file"

asetup; jq '. + [{status:"renamed",filename:".team/plans/x.md",previous_filename:"REVIEW.md"}]' "$A/repos~o~r~pulls~7~files" > "$A/x" && mv "$A/x" "$A/repos~o~r~pulls~7~files"; arun
! amerged && asaid "REVIEW.md is outside a release bump" && ok "auto: a rename's source counts" || nok "auto: rename source"

asetup; content repos/o/r/contents/AGENTS.md main "$(agents_md release '`.team/team.md`' claude)"; arun
! amerged && asaid ".team/team.md is on Human-only paths" && ok "auto: a file on the repo's Human-only paths refuses" || nok "auto: Human-only path file"

asetup; content repos/o/r/contents/AGENTS.md main "$(agents_md release 'the rulebook' claude)"; arun
! amerged && asaid "lists no backticked paths" && ok "auto: a Human-only line that is not globs refuses" || nok "auto: unreadable Human-only line"

asetup; put "repos/u/agent-team/compare/$OLD...$NEW" '{"status":"behind"}'; arun
! amerged && asaid "the pin does not move forward" && ok "auto: a pin that moves backwards refuses" || nok "auto: pin backwards"

asetup; put "repos/u/agent-team/compare/$NEW...main" '{"status":"diverged"}'; arun
! amerged && asaid "is not on u/agent-team main" && ok "auto: a pin off agent-team main refuses" || nok "auto: pin off main"

asetup; jq '[.[] | select(.filename != ".claude/skills/agent-team")]' "$A/repos~o~r~pulls~7~files" > "$A/x" && mv "$A/x" "$A/repos~o~r~pulls~7~files"; arun
! amerged && quiet && grep -q "not a release bump" "$A/out" && ok "auto: a PR that does not move the submodule is left alone, silently" || nok "auto: not a bump"

asetup; content repos/o/r/contents/.team/reviews/030-bump.md "$H" $'---\nverdict: request-changes\n---\n'; arun
! amerged && quiet && grep -q "no review file with" "$A/out" && ok "auto: no approving review file: waits silently" || nok "auto: no approve"

asetup; put repos/o/r/pulls/7/reviews "[{\"user\":{\"login\":\"o\"},\"commit_id\":\"$C\",\"body\":\"old\"}]"; arun
! amerged && quiet && grep -q "the review is not posted on $H by o" "$A/out" && ok "auto: the review not posted on this head: waits silently" || nok "auto: review on another head"

asetup; put repos/o/r/pulls/7/comments "[{\"user\":{\"login\":\"$BOT\"},\"original_commit_id\":\"$C\",\"body\":\"**<sub><sub>![P1 Badge](https://img.shields.io/badge/P1-orange)</sub></sub> Pin moves too far**\"}]"; arun
! amerged && asaid "Codex left a P0/P1 or M/S finding on 2222222" && ok "auto: a Codex P1 on the last code commit refuses" || nok "auto: Codex P1"

asetup; jq -n --arg b "$BOT" '[{id:9,user:{login:$b},created_at:"2026-11-21T09:00:00Z",body:"<!-- codex-review-receipt:v1 -->\nCodex Review: fine.\n**Reviewed commit:** `9999999`"}]' > "$A/repos~o~r~issues~7~comments"; arun
! amerged && quiet && grep -q "no finished Codex review of 2222222" "$A/out" && ok "auto: a receipt for an older commit is no review of the last one: waits silently" || nok "auto: receipt for older commit"

summary() { jq -n --arg b "$BOT" --arg s "$1" '[{id:8,user:{login:"o"},body:"@codex review"},{id:10,user:{login:$b},body:("<!-- codex-pull-request-review-summary -->\n<!-- codex-review-state:v1 {\"code_review\":{" + $s + "},\"security_review\":{}} -->")}]' > "$A/repos~o~r~issues~7~comments"; }
asetup; summary "\"commit_sha\":\"$C\",\"has_any_findings\":false,\"has_unresolved_findings\":false,\"status\":\"completed\""; arun
amerged && ok "auto: Codex's status summary, completed without findings on the last code commit, counts as clean" || nok "auto: summary clean"

asetup; summary "\"commit_sha\":\"$C\",\"has_any_findings\":true,\"has_unresolved_findings\":true,\"status\":\"completed\""; arun
amerged && ok "auto: the summary's findings flag alone does not refuse: it counts the PR's open threads (48516c6 on #36: clean receipt, flag true)" || nok "auto: summary flag"

asetup; jq --arg b "$BOT" --arg c "$C" '. + [{id:11,user:{login:$b},body:("<!-- codex-pull-request-review-summary -->\n<!-- codex-review-state:v1 &#123;\"code_review\":&#123;\"commit_sha\":\"" + $c + "\",\"has_any_findings\":null,\"has_unresolved_findings\":null,\"status\":\"failed\"&#125;&#125; -->")}]' "$A/repos~o~r~issues~7~comments" > "$A/x" && mv "$A/x" "$A/repos~o~r~issues~7~comments"; arun
! amerged && asaid "a Codex review of 2222222 ended failed" && ok "auto: a clean receipt plus a failed summary for the same commit refuses (Codex M7 on #36; escaped braces as GitHub stores them)" || nok "auto: failed summary"

asetup; summary "\"commit_sha\":\"$C\",\"has_any_findings\":null,\"has_unresolved_findings\":null,\"status\":\"running\""; arun
! amerged && quiet && grep -q "still running" "$A/out" && ok "auto: a Codex review still running on the last code commit: waits silently" || nok "auto: summary running"

asetup; summary "\"commit_sha\":\"$H\",\"has_any_findings\":false,\"has_unresolved_findings\":false,\"status\":\"completed\""; arun
! amerged && quiet && ok "auto: a summary for another commit is no review of the last code commit" || nok "auto: summary other commit"

asetup; jq -n '[{id:8,user:{login:"o"},created_at:"2026-11-21T10:01:00Z",body:"@codex review"}]' > "$A/repos~o~r~issues~7~comments"; put repos/o/r/issues/comments/8/reactions "[{\"user\":{\"login\":\"$BOT\"},\"content\":\"+1\",\"created_at\":\"2026-11-21T10:04:00Z\"}]"; put repos/o/r/issues/7/reactions "[{\"user\":{\"login\":\"$BOT\"},\"content\":\"+1\",\"created_at\":\"2026-11-21T10:30:00Z\"}]"; arun
! amerged && quiet && grep -q "no finished Codex review of 2222222" "$A/out" && ok "auto: a Codex 👍 alone never counts: it names no commit (Codex M2 on #36)" || nok "auto: thumbs alone"

asetup; put repos/o/r/pulls/7/reviews "[{\"user\":{\"login\":\"o\"},\"commit_id\":\"$H\",\"state\":\"COMMENTED\",\"body\":\"verdict: approve\"},{\"user\":{\"login\":\"o\"},\"commit_id\":\"$H\",\"state\":\"CHANGES_REQUESTED\",\"body\":\"verdict: request-changes. Do not merge\"}]"; arun
! amerged && quiet && grep -q "does not say 'verdict: approve'" "$A/out" && ok "auto: a later request-changes review by the owner on the head stops it (Codex M1 on #36)" || nok "auto: negative review"

asetup; put repos/o/r/pulls/7/reviews "[{\"user\":{\"login\":\"o\"},\"commit_id\":\"$H\",\"state\":\"COMMENTED\",\"body\":\"looks fine\"}]"; arun
! amerged && quiet && ok "auto: a review on the head without the verdict line does not count" || nok "auto: review without verdict"

asetup; jq '(.[] | select(.filename == ".team/team.md")) |= . + {patch:"@@ -17,1 +17,1 @@\n-merge: human\n+merge: auto"}' "$A/repos~o~r~pulls~7~files" > "$A/x" && mv "$A/x" "$A/repos~o~r~pulls~7~files"; arun
! amerged && asaid ".team/team.md changes a line that only a card may change: merge: human" && ok "auto: a merge: change in .team/team.md refuses (Codex M5 on #36)" || nok "auto: team.md merge line"

asetup; jq '(.[] | select(.filename == ".team/team.md")) |= . + {patch:"@@ -30,1 +30,1 @@\n-team: .claude/skills/agent-team @ v0.8.14\n+team: .claude/skills/agent-team @ v0.8.15"}' "$A/repos~o~r~pulls~7~files" > "$A/x" && mv "$A/x" "$A/repos~o~r~pulls~7~files"; arun
amerged && ok "auto: the version line in .team/team.md may move" || nok "auto: team.md version line"

asetup; put "repos/o/r/commits/$H" '{"files":[{"filename":".team/reviews/cfg.md","previous_filename":".team/team.md"}]}'; arun
! amerged && quiet && grep -q "no finished Codex review of 1111111" "$A/out" && ok "auto: a rename out of .team/ into reviews/ makes that commit the last code commit (Codex M4 on #36)" || nok "auto: rename source in commit"

asetup; rm "$A/repos~o~r~pulls~7~commits"; arun
! amerged && [ "$(cat "$A/rc")" = 1 ] && quiet && ok "auto: the PR's commit list unreadable: stops without merging (Codex M8 on #36)" || nok "auto: commits unreadable"

asetup; put repos/o/r/pulls/7/commits "[{\"sha\":\"$C\"}]"; arun
! amerged && [ "$(cat "$A/rc")" = 1 ] && grep -q "does not end at the head" "$A/out" && ok "auto: a commit list cut short (it does not end at the head): stops without merging" || nok "auto: commits cut short"

asetup; rm "$A/repos~o~r~pulls~7~comments"; arun
! amerged && [ "$(cat "$A/rc")" = 1 ] && quiet && ok "auto: Codex's inline comments unreadable: stops without merging (Codex M3 on #36)" || nok "auto: inline unreadable"

asetup; put "repos/o/r/commits/$H/check-runs?per_page=100" '{"check_runs":[{"id":5,"name":"pr-check","status":"completed","conclusion":"cancelled"},{"id":6,"name":"pr-check","status":"completed","conclusion":"success"}]}'; arun
amerged && ok "auto: a cancelled older run with a green newer run of the same check merges" || nok "auto: latest run per check"

asetup; put "repos/o/r/commits/$H/check-runs?per_page=100" '{"check_runs":[{"id":5,"name":"pr-check","status":"completed","conclusion":"failure"}]}'; arun
! amerged && asaid "check pr-check is failure" && ok "auto: a red check refuses" || nok "auto: red check"

asetup; put "repos/o/r/commits/$H/check-runs?per_page=100" '{"check_runs":[{"id":5,"name":"pr-check","status":"in_progress","conclusion":null}]}'; arun
! amerged && quiet && grep -q "check pr-check is in_progress" "$A/out" && ok "auto: a running check: waits silently" || nok "auto: running check"

asetup; put "repos/o/r/commits/$H/status" '{"statuses":[{"context":"Vercel","state":"failure"}]}'; arun
! amerged && asaid "status Vercel is failure" && ok "auto: a red commit status refuses" || nok "auto: red status"

asetup; put "repos/o/r/compare/main...$H" "{\"behind_by\":2,\"merge_base_commit\":{\"sha\":\"$MB\"}}"; arun
! amerged && asaid "2 commits behind main" && ok "auto: a head behind main refuses" || nok "auto: behind main"

asetup; put "repos/o/r/compare/main...$H" "{\"behind_by\":2,\"merge_base_commit\":{\"sha\":\"$MB\"}}"; jq --arg h "$H" '. + [{id:20,user:{login:"github-actions[bot]"},created_at:"2026-11-21T10:20:00Z",body:("agent-team-merge (release bump) did not merge, head " + $h + ": earlier")}]' "$A/repos~o~r~issues~7~comments" > "$A/x" && mv "$A/x" "$A/repos~o~r~issues~7~comments"; arun
! amerged && quiet && grep -q "not merged: the branch is 2 commits behind" "$A/out" && ok "auto: one refusal comment per head" || nok "auto: once per head"

asetup; put repos/o/r/pulls/7 "{\"state\":\"open\",\"draft\":true,\"head\":{\"sha\":\"$H\",\"ref\":\"bump\",\"repo\":{\"full_name\":\"o/r\"}},\"base\":{\"ref\":\"main\"}}"; arun
! amerged && quiet && grep -q "the PR is a draft" "$A/out" && ok "auto: a draft is left alone" || nok "auto: draft"

asetup; put "repos/o/r/commits/$H/pulls" '[{"number":7,"state":"open"}]'; APRS="" AHS="$H" arun
amerged && ok "auto: a workflow_run or check_suite event finds the PR by its head" || nok "auto: PR by head sha"

asetup; touch "$A/refuse"; arun
! amerged || true; asaid "GitHub refused the merge: Required status check" && ! asaid "Merged by" && ok "auto: GitHub refuses: says why, no success comment" || nok "auto: GitHub refuses"

grep -q "workflows: \[" "$WF" && grep -q 'pull_request_target' "$WF" && grep -q "github.event.action == 'created' && github.event.issue.pull_request" "$WF" && grep -q "user.login == 'chatgpt-codex-connector\[bot\]'" "$WF" && ok "auto: triggers on the PR, Codex's comments and finished CI" || nok "auto: triggers"

grep -q 'github.event.comment.body }}' "$WF" && ! grep -qE 'run:.*\$\{\{' "$WF" && ok "comment body reaches the script only through env" || nok "body through env"
grep -q 'actions/checkout' "$WF" && nok "checks out no code" || ok "checks out no code"

[ $fail = 0 ] && echo "PASS ($n)" || { echo FAIL; exit 1; }
