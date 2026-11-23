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
  put "repos/o/r/commits/$H/status?per_page=100" '{"state":"pending","total_count":0,"statuses":[]}'
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

asetup; rm -f "$A/repos~o~r~contents~AGENTS.md?ref=main"; arun
! amerged && quiet && [ "$(cat "$A/rc")" = 0 ] && grep -q "no AGENTS.md on main" "$A/out" && ok "auto: no AGENTS.md on the default branch (agent-team itself) does nothing, green (v0.8.16)" || { nok "auto: no AGENTS.md"; cat "$A/out"; }

asetup; echo 'not json' > "$A/repos~o~r~contents~AGENTS.md?ref=main"; arun
! amerged && [ "$(cat "$A/rc")" = 1 ] && grep -q "could not read AGENTS.md on main" "$A/out" && ok "auto: an unreadable AGENTS.md (not a 404) stays an error" || { nok "auto: unreadable AGENTS.md"; cat "$A/out"; }

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

asetup; put "repos/o/r/commits/$H" '{"files":[{"filename":".team/reviews/030-bump.md"},{"filename":".team/reviews/030-bump.response.md"}]}'; arun
amerged && ok "auto: a review-only commit with two review files is not taken for code (Codex M10 on #36)" || nok "auto: two review files"

asetup; rm "$A/repos~o~r~commits~$H"; arun
! amerged && [ "$(cat "$A/rc")" = 1 ] && quiet && ok "auto: a commit's files unreadable: stops without merging" || nok "auto: commit files unreadable"

asetup; jq -n '{files: ([range(0; 3000)] | map({filename: (".team/reviews/r\(.).md")}))}' > "$A/repos~o~r~commits~$H"; arun
! amerged && asaid "lists 3000 files" && ok "auto: a commit at GitHub's 3000-file cap refuses (Codex M9 on #36)" || nok "auto: commit file cap"

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

asetup; put "repos/o/r/commits/$H/status?per_page=100" '{"state":"failure","total_count":1,"statuses":[{"context":"Vercel","state":"failure"}]}'; arun
! amerged && asaid "status Vercel is failure" && ok "auto: a red commit status refuses" || nok "auto: red status"
# M11: more contexts than one page shows; the aggregate state or a row count mismatch stops it
asetup; put "repos/o/r/commits/$H/status?per_page=100" '{"state":"failure","total_count":31,"statuses":[{"context":"a","state":"success"}]}'; arun
! amerged && grep -q "read 1 of 31 statuses" "$A/out" && quiet && [ "$(cat "$A/rc")" = 1 ] && ok "auto: a status list shorter than total_count stops without merging" || nok "auto: short status list"
asetup; put "repos/o/r/commits/$H/status?per_page=100" '{"state":"failure","total_count":1,"statuses":[{"context":"a","state":"success"}]}'; arun
! amerged && asaid "the combined status is failure" && ok "auto: a red combined status refuses even when every row read is green" || nok "auto: red aggregate"
asetup; put "repos/o/r/commits/$H/status?per_page=100" '{"state":"pending","total_count":1,"statuses":[{"context":"a","state":"success"}]}'; arun
! amerged && quiet && ok "auto: a pending combined status waits quietly" || nok "auto: pending aggregate"
asetup; put "repos/o/r/commits/$H/status?per_page=100" '{"state":"success","total_count":1,"statuses":[{"context":"a","state":"success"}]}'; arun
amerged && ok "auto: a green combined status merges" || nok "auto: green aggregate"

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

# ---- v0.8.19: class rules, a green rule change merges on agreement; the walls, a pause and Guard paths stop it (story X)
agents2() { # $1 Auto-merge  $2 Guard paths  $3 Builder
  printf '# r\n\n## Team settings\n\n- **Builder:** %s\n- **Human-only paths:** none\n- **Auto-merge:** %s\n- **Guard paths:** %s\n\n## Papercuts\n\nx\n' "$3" "$1" "$2"
}
files() { jq "$1" "$A/repos~o~r~pulls~7~files" > "$A/x" && mv "$A/x" "$A/repos~o~r~pulls~7~files"; }
rsetup() { # a team repo: a Rulebook story PR that moves the version line in .team/team.md
  asetup
  content repos/o/r/contents/AGENTS.md main "$(agents2 'release, rules' none claude)"
  content repos/o/r/contents/AGENTS.md "$MB" "$(agents2 'release, rules' none claude)"
  content repos/o/r/contents/AGENTS.md "$H" "$(agents2 'release, rules' none claude)"
  content repos/o/r/contents/.team/team.md main 'mode: cloud'
  put repos/o/r/pulls/7 "{\"state\":\"open\",\"draft\":false,\"merged\":false,\"title\":\"031: Rulebook story. Models per role\",\"head\":{\"sha\":\"$H\",\"ref\":\"bump\",\"repo\":{\"full_name\":\"o/r\"}},\"base\":{\"ref\":\"main\"}}"
  jq -n '[{status:"added",filename:".team/reviews/030-bump.md"},{status:"modified",filename:".team/team.md",patch:"@@ -8,1 +8,1 @@\n-  coder: codex\n+  coder: codex-cli"}]' > "$A/repos~o~r~pulls~7~files"
  put "repos/o/r/commits/$C" '{"files":[{"filename":".team/team.md"}]}'
}
rgreen() { amerged && asaid "Merged by agent-team-merge (rules, green): head $H"; }
carded() { asaid "agent-team-merge (rules) did not merge, head $H: " && asaid "goes to a decision card"; }

rsetup; arun
rgreen && [ "$(cat "$A/rc")" = 0 ] && ok "rules: a green rule change in a team repo merges on agreement and says so" || { nok "rules: green merges"; cat "$A/out"; }

rsetup; content repos/o/r/contents/AGENTS.md main "$(agents2 release none claude)"; arun
! amerged && quiet && grep -q "not a release bump" "$A/out" && ok "rules: Auto-merge: release alone leaves a rule change alone, silently" || nok "rules: release alone"

rsetup; content repos/o/r/contents/AGENTS.md main "$(agents2 'release, rules, code' none claude)"; arun
! amerged && quiet && grep -q "names 'code'" "$A/out" && ok "rules: an unknown word on the Auto-merge line turns the job off" || nok "rules: unknown Auto-merge word"

rsetup; content repos/o/r/contents/AGENTS.md main "$(agents2 rules none claude)"; arun
rgreen && ok "rules: Auto-merge: rules alone is enough" || nok "rules: rules alone"

asetup; content repos/o/r/contents/AGENTS.md main "$(agents2 rules none claude)"; arun
! amerged && quiet && grep -q "does not list release" "$A/out" && ok "rules: Auto-merge: rules alone leaves a release bump alone" || nok "rules: bump without release"

asetup; content repos/o/r/contents/AGENTS.md main "$(agents_md 'release, rules' none claude)"; arun
amerged && asaid "Merged by agent-team-merge (release bump): head $H" && ok "rules: a release bump still merges as a release bump under release, rules" || nok "rules: bump under both"

rsetup; jq '.title = "031: Models per role"' "$A/repos~o~r~pulls~7" > "$A/x" && mv "$A/x" "$A/repos~o~r~pulls~7"; arun
! amerged && quiet && grep -q "not titled 'Rulebook story.'" "$A/out" && ok "rules: a PR not titled Rulebook story. is left alone, silently" || nok "rules: title"

rsetup; files '. + [{status:"added",filename:".github/workflows/x.yml"}]'; arun
! amerged && carded && asaid ".github/workflows/x.yml is a wall" && ok "rules: a file under .github/ refuses, to a card" || { nok "rules: .github"; cat "$A/out"; }

rsetup; files '. + [{status:"modified",filename:"src/a.js"}]'; arun
! amerged && carded && asaid "src/a.js is outside the green class" && ok "rules: code refuses" || nok "rules: code"

rsetup; files '. + [{status:"added",filename:".team/automerge-pause"}]'; arun
! amerged && carded && asaid "changes only in a PR of its own" && ok "rules: the pause file beside other changes refuses" || nok "rules: pause mixed in"

akey() { jq --arg p "$1" '. + [{status:"modified",filename:"AGENTS.md",patch:$p}]' "$A/repos~o~r~pulls~7~files" > "$A/x" && mv "$A/x" "$A/repos~o~r~pulls~7~files"; }
rsetup; akey '@@ -7,1 +7,1 @@
-- **Auto-merge:** release, rules
+- **Auto-merge:** release, rules, code'; arun
! amerged && carded && asaid "a line that only a card may change" && ok "rules: a change to the Auto-merge key refuses" || { nok "rules: Auto-merge key"; cat "$A/out"; }

rsetup; akey '@@ -8,1 +8,1 @@
-- **Guard paths:** `x`
+- **Guard paths:** none'; arun
! amerged && carded && asaid "a line that only a card may change" && ok "rules: a change to the Guard paths key beside other changes refuses" || nok "rules: Guard paths key"

# Codex M1 on relationsmodellen-site #80: a guarded key's continuation lines are the key's too
agents3() { # $1 the Human-merge paths continuation line  $2 an extra line after the key line  $3 the Builder continuation line
  printf '# r\n\n## Team settings\n\n- **Builder:** claude\n  %s\n- **Human-merge paths:** all. The Judge merges only on\n%s  %s\n- **Human-only paths:** none\n- **Auto-merge:** release, rules\n- **Guard paths:** none\n\n## Papercuts\n\nx\n' "$3" "$2" "$1"
}
c3setup() { # $1 $2 $3 at the head, against agents3 'agreement with Codex.' '' 'extra'
  rsetup
  content repos/o/r/contents/AGENTS.md main "$(agents3 'agreement with Codex.' '' extra)"
  content repos/o/r/contents/AGENTS.md "$MB" "$(agents3 'agreement with Codex.' '' extra)"
  content repos/o/r/contents/AGENTS.md "$H" "$(agents3 "$1" "$2" "$3")"
  akey "$4"
}
c3setup 'its own word.' '' extra '@@ -8,1 +8,1 @@
-  agreement with Codex.
+  its own word.'; arun
! amerged && carded && asaid "a key's continuation lines count" && ok "rules: a changed continuation line of a guarded key refuses (Codex M1 on relationsmodellen-site #80)" || { nok "rules: guarded continuation"; cat "$A/out"; }

c3setup 'agreement with Codex.' $'- **Note:** x\n' extra '@@ -7,0 +8,1 @@
+- **Note:** x'; arun
! amerged && carded && asaid "a key's continuation lines count" && ok "rules: a bullet slipped in between a guarded key and its continuation refuses" || { nok "rules: split guarded entry"; cat "$A/out"; }

c3setup 'agreement with Codex.' '' 'more' '@@ -6,1 +6,1 @@
-  extra
+  more'; arun
rgreen && ok "rules: a continuation line of an unguarded key stays green" || { nok "rules: unguarded continuation"; cat "$A/out"; }

rsetup; akey '@@ -5,1 +5,1 @@
-- **Builder:** claude
+- **Builder:** codex-cli'; arun
rgreen && ok "rules: another Team settings line may change" || { nok "rules: Builder line"; cat "$A/out"; }

rsetup; content repos/o/r/contents/AGENTS.md main "$(agents2 'release, rules' '`.team/team.md`' claude)"; arun
! amerged && carded && asaid ".team/team.md is on Guard paths" && ok "rules: a file on the repo's Guard paths refuses" || nok "rules: Guard path"

rsetup; content repos/o/r/contents/AGENTS.md main "$(agents2 'release, rules' 'the rulebook' claude)"; arun
! amerged && carded && asaid "Guard paths line in AGENTS.md lists no backticked paths" && ok "rules: a Guard paths line that is not globs refuses" || nok "rules: unreadable Guard paths"

asetup; content repos/o/r/contents/AGENTS.md main "$(agents2 'release, rules' '`.team/team.md`' claude)"; arun
amerged && ok "rules: Guard paths do not stop a release bump" || nok "rules: Guard paths and a bump"

rsetup; files '(.[] | select(.filename == ".team/team.md")) |= . + {patch:"@@ -17,1 +17,1 @@\n-merge: human\n+merge: auto"}'; arun
! amerged && carded && asaid ".team/team.md changes a line that only a card may change" && ok "rules: a merge: change in .team/team.md refuses" || nok "rules: team.md merge line"

rsetup; put repos/o/r/pulls/7/comments "[{\"user\":{\"login\":\"$BOT\"},\"original_commit_id\":\"$C\",\"body\":\"**<sub><sub>![P1 Badge](https://img.shields.io/badge/P1-orange)</sub></sub> Wrong model**\"}]"; arun
! amerged && asaid "Codex left a P0/P1 or M/S finding on 2222222" && asaid "The Judge goes on as CLOUD.md § Judge 5 says" && ok "rules: a Codex P1 on the last code commit refuses" || nok "rules: Codex P1"

rsetup; jq -n '[]' > "$A/repos~o~r~issues~7~comments"; arun
! amerged && quiet && grep -q "no finished Codex review of 2222222" "$A/out" && ok "rules: no Codex review yet: waits silently" || nok "rules: no Codex"

# the pause
pause() { content "repos/o/r/contents/$1" "$2" "$3"; }
rsetup; pause .team/automerge-pause main $'until: 2999-01-01\nreason: revert of #40'; arun
! amerged && carded && asaid "rule changes are paused until 2999-01-01: revert of #40" && ok "rules: a pause in the future refuses, with its reason" || { nok "rules: pause in force"; cat "$A/out"; }

rsetup; pause .team/automerge-pause main $'until: 2000-01-01\nreason: old'; arun
rgreen && ok "rules: a pause in the past does not stop it" || nok "rules: pause over"

rsetup; pause .team/automerge-pause main 'paused for now'; arun
! amerged && carded && asaid "no readable 'until: YYYY-MM-DD'" && ok "rules: a pause file without a date holds" || nok "rules: pause without date"

asetup; pause .team/automerge-pause main $'until: 2999-01-01\nreason: x'; content repos/o/r/contents/AGENTS.md main "$(agents_md 'release, rules' none claude)"; arun
amerged && ok "rules: a pause does not stop a release bump" || nok "rules: pause and a bump"

psetup() { # a PR that only sets the pause; no Codex review anywhere
  rsetup; jq -n '[{status:"added",filename:".team/reviews/030-bump.md"},{status:"'"$1"'",filename:".team/automerge-pause"}]' > "$A/repos~o~r~pulls~7~files"
  jq -n '[]' > "$A/repos~o~r~issues~7~comments"
  pause .team/automerge-pause "$H" "$2"
}
psetup added $'until: 2999-01-01\nreason: Must fix in the weekly sample, #41'; arun
amerged && asaid "Merged by agent-team-merge (rules, tightening): head $H" && ok "pause: a PR that only sets the pause merges on the Judge's approve, without Codex" || { nok "pause: sets"; cat "$A/out"; }

psetup added $'until: 2999-01-01\nreason: x'; content repos/o/r/contents/.team/reviews/030-bump.md "$H" $'---\nverdict: request-changes\n---\n'; arun
! amerged && quiet && ok "pause: still needs the Judge's approving review file" || nok "pause: no approve"

psetup modified $'until: 2999-02-01\nreason: x'; pause .team/automerge-pause main $'until: 2999-01-01\nreason: x'; arun
amerged && ok "pause: extending a pause merges" || nok "pause: extends"

psetup modified $'until: 2998-12-01\nreason: x'; pause .team/automerge-pause main $'until: 2999-01-01\nreason: x'; arun
! amerged && carded && asaid "only a card shortens a pause" && ok "pause: shortening a pause refuses" || { nok "pause: shortens"; cat "$A/out"; }

psetup removed ''; pause .team/automerge-pause main $'until: 2999-01-01\nreason: x'; arun
! amerged && carded && asaid "only a card ends a pause" && ok "pause: removing the pause file refuses" || nok "pause: removed"

rsetup; pause .team/automerge-pause main $'until: 2026-00-99\nreason: x'; arun
! amerged && carded && asaid "no readable 'until: YYYY-MM-DD'" && ok "rules: a pause whose date is no calendar date holds (Codex M6 on #40)" || { nok "rules: impossible pause date"; cat "$A/out"; }

psetup added $'until: 2999-02-31\nreason: x'; arun
! amerged && carded && ok "pause: a pause set to no calendar date refuses" || nok "pause: impossible date"

psetup added 'until: soon'; arun
! amerged && carded && asaid "no single line 'until: YYYY-MM-DD'" && ok "pause: a pause without a date refuses" || nok "pause: no date"

psetup added $'until: 2999-01-01\nreason: x'; put "repos/o/r/commits/$H/check-runs?per_page=100" '{"check_runs":[{"id":5,"name":"pr-check","status":"completed","conclusion":"failure"}]}'; arun
! amerged && asaid "check pr-check is failure" && ok "pause: a red check still refuses" || nok "pause: red check"

gsetup() { # a PR that only changes the Guard paths line: $1 old value, $2 new value
  rsetup; jq -n '[{status:"added",filename:".team/reviews/030-bump.md"},{status:"modified",filename:"AGENTS.md",patch:"@@ -8,1 +8,1 @@\n-- **Guard paths:** old\n+- **Guard paths:** new"}]' > "$A/repos~o~r~pulls~7~files"
  jq -n '[]' > "$A/repos~o~r~issues~7~comments"
  content repos/o/r/contents/AGENTS.md "$MB" "$(agents2 'release, rules' "$1" claude)"
  content repos/o/r/contents/AGENTS.md "$H" "$(agents2 'release, rules' "$2" claude)"
}
gsetup none '`.team/team.md`'; arun
amerged && asaid "(rules, tightening)" && ok "guard: a PR that only adds a Guard path merges on the Judge's approve, without Codex" || { nok "guard: adds"; cat "$A/out"; }

gsetup '`a/**`' '`a/**`, `b.md`'; arun
amerged && ok "guard: adding a second Guard path merges" || nok "guard: adds a second"

gsetup '`a/**`, `b.md`' '`a/**`'; arun
! amerged && carded && asaid "a line that only a card may change" && ok "guard: removing a Guard path is no tightening: refuses" || { nok "guard: removes"; cat "$A/out"; }

gsetup '`a/**`' '`b.md`'; arun
! amerged && carded && ok "guard: swapping a Guard path refuses" || nok "guard: swaps"

gsetup 'the rulebook' '`a/**`'; arun
! amerged && carded && ok "guard: replacing a Guard paths line that refused everything is no tightening (Codex M3 on #40)" || { nok "guard: malformed old value"; cat "$A/out"; }

rsetup; content repos/o/r/contents/AGENTS.md main "$(agents2 'release, rules' '`.team/Legal terms.md`' claude)"; files '. + [{status:"modified",filename:".team/Legal terms.md"}]'; arun
! amerged && carded && { asaid ".team/Legal terms.md is on Guard paths" || asaid ".team/Legal terms.md is outside the green class"; } && ok "rules: a Guard path with a space in it still guards (Codex M2 on #40)" || { nok "rules: guard with space"; cat "$A/out"; }

rsetup; content repos/o/r/contents/AGENTS.md main "$(agents2 'release, rules' '`.team/plans/Legal terms.md`' claude)"; files '. + [{status:"modified",filename:".team/plans/Legal terms.md"}]'; arun
! amerged && carded && asaid ".team/plans/Legal terms.md is on Guard paths" && ok "rules: a guarded green path with a space refuses" || { nok "rules: guarded green path with space"; cat "$A/out"; }

rsetup; files '. + [{status:"renamed",filename:".team/plans/b.md",previous_filename:"src/my file.js"}]'; arun
! amerged && carded && asaid "src/my file.js is outside the green class" && ok "rules: a rename source with a space is read whole" || { nok "rules: rename source with space"; cat "$A/out"; }

gsetup none '`a/**`'; content repos/o/r/contents/AGENTS.md "$H" "$(agents2 'release, rules, code' '`a/**`' claude)"; arun
! amerged && ok "guard: another line changed beside Guard paths is no tightening" || nok "guard: other line"

# agent-team itself: no .team/, the rules live in team/
CL='# Cloud mode

## Builder

1. Branch from main. [B2]
2. Build with tests. [B3]

## Judge

1. Check out. [J2]
4. Write the review. [J5]
5. **On approve.** Pin the head. [J6]
   - **Exceptions** never merge on your word. [J7]
   - **On agreement** only when a to d hold. [J10]
6. **Escalate** after the third round. [J11]

## Human approval

The human gets a card only for a disagreement. [H1]

## Routines

One routine per project. [R1]

## Walls

- **Merge workflow.** No agent session runs a merge. [W3]'
ST='# Setup

## One-time setup per repo

1. Codex: connect the repo.

## Walls in full

- **Main ruleset.** PR only.'
hsetup() { # $1 = sed script that turns the base team/CLOUD.md into the head's
  asetup
  content repos/o/r/contents/AGENTS.md main "$(agents2 'release, rules' none claude)"
  rm -f "$A/repos~o~r~contents~.team~team.md?ref=main"
  content repos/o/r/contents/team/CLOUD.md main "$CL"; content repos/o/r/contents/team/CLOUD.md "$MB" "$CL"
  content repos/o/r/contents/team/CLOUD.md "$H" "$(sed "$1" <<<"$CL")"
  put repos/o/r/pulls/7 "{\"state\":\"open\",\"draft\":false,\"merged\":false,\"title\":\"Rulebook story. v0.9.0: x\",\"head\":{\"sha\":\"$H\",\"ref\":\"bump\",\"repo\":{\"full_name\":\"o/r\"}},\"base\":{\"ref\":\"main\"}}"
  jq -n '[{status:"modified",filename:"team/CLOUD.md"},{status:"modified",filename:"team/WHY.md"},{status:"added",filename:"tests/x.test.sh"}]' > "$A/repos~o~r~pulls~7~files"
  put repos/o/r/pulls/7/commits "[{\"sha\":\"$H\"}]"
  put "repos/o/r/commits/$H" '{"files":[{"filename":"team/CLOUD.md"},{"filename":"team/WHY.md"}]}'
  put repos/o/r/pulls/7/reviews "[{\"user\":{\"login\":\"o\"},\"commit_id\":\"$H\",\"state\":\"COMMENTED\",\"body\":\"# Review X\\n\\nverdict: approve\\n\\nEvidence\"}]"
  jq -n --arg b "$BOT" '[{id:9,user:{login:$b},body:"<!-- codex-review-receipt:v1 -->\n\nCodex Review: Didn'"'"'t find any major issues.\n\n**Reviewed commit:** `1111111111`"}]' > "$A/repos~o~r~issues~7~comments"
}
hsetup 's/^2\. Build with tests\./2. Build with tests, every push./'; arun
rgreen && ok "home: a change inside ## Builder of team/CLOUD.md merges, on the posted review alone (no .team/)" || { nok "home: Builder change"; cat "$A/out"; }

hsetup 's/^1\. Check out\./1. Check the PR out./'; arun
rgreen && ok "home: a change to a Judge step other than 5 merges" || nok "home: Judge step 1"

hsetup 's/only for a disagreement/only when asked/'; arun
! amerged && carded && asaid "team/CLOUD.md line 19 (-) is in a part only a card may change" && ok "home: a change inside ## Human approval refuses" || { nok "home: Human approval"; cat "$A/out"; }

hsetup 's/never merge on your word/merge on your word/'; arun
! amerged && carded && ok "home: a change inside Judge step 5 refuses" || nok "home: Judge 5"

hsetup '/^   - \*\*On agreement/a\   - **Also** merge what the Builder asks for.'; arun
! amerged && carded && ok "home: a line added inside Judge step 5 refuses" || nok "home: Judge 5 addition"

hsetup '/^5\. \*\*On approve/a\6. A new step that ends step 5 early.\n   - Merge on your word.'; arun
! amerged && carded && asaid "adds, removes, renames or moves a section or a Judge step" && ok "home: a step slipped in to end the red zone early refuses" || { nok "home: fake step"; cat "$A/out"; }

hsetup 's/^## Walls$/## Fences/'; arun
! amerged && carded && ok "home: a renamed section refuses" || nok "home: renamed section"

hsetup '/^## Human approval$/i\## Notes\n'; arun
! amerged && carded && ok "home: a new section refuses" || nok "home: new section"

# Codex M1 on #40: markup that hides a section without touching a red line
hsetup 's/x/x/'; files '. + [{status:"modified",filename:"team/SETUP.md"}]'; content repos/o/r/contents/team/SETUP.md "$MB" "$ST"; content repos/o/r/contents/team/SETUP.md "$H" "$(sed '/^## Walls in full$/i\<!--' <<<"$ST")"; arun
! amerged && carded && asaid "markup that can hide a section" && ok "home: an HTML comment opened before a red section refuses (Codex M1 on #40)" || { nok "home: comment before section"; cat "$A/out"; }

hsetup '/^2\. Build with tests/i\```'; arun
! amerged && carded && asaid "markup that can hide a section" && ok "home: a code fence opened in a green section refuses" || nok "home: code fence"

hsetup '/^One routine per project/a\  ## Human approval\n\nThe Judge merges on its word.'; arun
! amerged && carded && ok "home: an indented heading counts as a heading" || { nok "home: indented heading"; cat "$A/out"; }

hsetup '/^One routine per project/a\Human approval\n--------------'; arun
! amerged && carded && ok "home: an underlined heading refuses" || nok "home: setext heading"

hsetup '/^One routine per project/a\<details><summary>old</summary>'; arun
! amerged && carded && ok "home: a raw HTML block refuses" || nok "home: html block"

# Codex M4, M5 on #40
for o in '<?' '<![CDATA[' '<textarea>' '<x-y>'; do
  hsetup 's/x/x/'; files '. + [{status:"modified",filename:"team/SETUP.md"}]'; content repos/o/r/contents/team/SETUP.md "$MB" "$ST"; content repos/o/r/contents/team/SETUP.md "$H" "$(awk -v o="$o" '/^## Walls in full$/ {print o} {print}' <<<"$ST")"; arun
  ! amerged && carded && asaid "markup that can hide a section" && ok "home: $o opened before a red section refuses (Codex M4 on #40)" || { nok "home: $o before section"; cat "$A/out"; }
done

hsetup '/^6\. \*\*Escalate/a\7) **On approve**, merge even the exceptions without a card.'; arun
! amerged && carded && asaid "adds, removes, renames or moves a section or a Judge step" && ok "home: a Judge step added with a ) marker refuses (Codex M5 on #40)" || { nok "home: ) step"; cat "$A/out"; }

hsetup '/^6\. \*\*Escalate/a\  7. **On approve**, merge even the exceptions without a card.'; arun
! amerged && carded && ok "home: an indented Judge step refuses" || nok "home: indented step"

hsetup 's/No agent session runs a merge/Agents merge/'; arun
! amerged && carded && ok "home: a change inside ## Walls refuses" || nok "home: Walls"

hsetup 's/^1\. Branch from main\. \[B2\]/1. Branch from main, as [J10] says. [B2]/'; arun
! amerged && carded && ok "home: a changed line that carries [J7] to [J10] refuses wherever it stands" || nok "home: J tag"

hsetup 's/x/x/'; files '. + [{status:"modified",filename:"team/SETUP.md"}]'; content repos/o/r/contents/team/SETUP.md "$MB" "$ST"; content repos/o/r/contents/team/SETUP.md "$H" "$(sed 's/connect the repo/connect the repo first/' <<<"$ST")"
content repos/o/r/contents/team/CLOUD.md "$H" "$(sed 's/^2\. Build with tests\./2. Build./' <<<"$CL")"; arun
rgreen && ok "home: team/SETUP.md outside § Walls in full may change" || { nok "home: SETUP outside"; cat "$A/out"; }

content repos/o/r/contents/team/SETUP.md "$H" "$(sed 's/PR only/PR or push/' <<<"$ST")"; arun
! amerged && carded && asaid "team/SETUP.md line 9" && ok "home: team/SETUP.md § Walls in full refuses" || { nok "home: SETUP walls"; cat "$A/out"; }

hsetup 's/^2\. Build with tests\./2. Build./'; files '(.[] | select(.filename == "team/CLOUD.md")) |= . + {status:"removed"}'; arun
! amerged && carded && asaid "team/CLOUD.md is removed, not modified" && ok "home: removing team/CLOUD.md refuses" || nok "home: CLOUD removed"

hsetup 's/^2\. Build with tests\./2. Build./'; rm "$A/repos~o~r~contents~team~CLOUD.md?ref=$H"; arun
! amerged && quiet && [ "$(cat "$A/rc")" = 1 ] && ok "home: team/CLOUD.md unreadable at the head stops without merging" || nok "home: CLOUD unreadable"

for f in assets/runner/cleanup.sh assets/cloud/main-ruleset.json assets/root/.claude/settings.json assets/root/.github/workflows/agent-team-merge.yml .github/workflows/agent-team-merge.yml new-project.sh .team/reviews/x.md; do
  hsetup 's/^2\. Build with tests\./2. Build./'; files ". + [{status:\"modified\",filename:\"$f\"}]"; arun
  ! amerged && carded && ok "home: $f refuses" || { nok "home: $f"; cat "$A/out"; }
done

hsetup 's/^2\. Build with tests\./2. Build./'; files '. + [{status:"renamed",filename:"team/NOTES.md",previous_filename:"REVIEW.md"}]'; arun
! amerged && carded && asaid "REVIEW.md is a wall" && ok "home: a rename's source counts" || nok "home: rename source"

hsetup 's/^2\. Build with tests\./2. Build./'; files '. + [{status:"modified",filename:"assets/root/AGENTS.md",patch:"@@ -7,1 +7,1 @@\n-- **Auto-merge:** none\n+- **Auto-merge:** release, rules"}]'
content repos/o/r/contents/assets/root/AGENTS.md "$MB" "$(agents2 none none claude)"; content repos/o/r/contents/assets/root/AGENTS.md "$H" "$(agents2 'release, rules' none claude)"; arun
! amerged && carded && asaid "assets/root/AGENTS.md changes a line that only a card may change" && ok "home: a guard key in the AGENTS.md template refuses" || { nok "home: template key"; cat "$A/out"; }

hsetup 's/^2\. Build with tests\./2. Build./'; put repos/o/r/pulls/7/reviews "[{\"user\":{\"login\":\"o\"},\"commit_id\":\"$H\",\"state\":\"COMMENTED\",\"body\":\"**Verdict: approve**\"}]"; arun
! amerged && quiet && grep -q "does not say 'verdict: approve'" "$A/out" && ok "home: a review without the line verdict: approve does not count" || nok "home: review without verdict line"

hsetup 's/^2\. Build with tests\./2. Build./'; pause team/automerge-pause main $'until: 2999-01-01\nreason: x'; arun
! amerged && carded && asaid "paused until 2999-01-01" && ok "home: the pause file is team/automerge-pause" || nok "home: pause"

hsetup 's/x/x/'; jq -n '[{status:"added",filename:"team/automerge-pause"}]' > "$A/repos~o~r~pulls~7~files"; jq -n '[]' > "$A/repos~o~r~issues~7~comments"; pause team/automerge-pause "$H" $'until: 2999-01-01\nreason: revert of #40'; arun
amerged && asaid "(rules, tightening)" && ok "home: a PR that only sets team/automerge-pause merges on the Judge's review" || { nok "home: sets pause"; cat "$A/out"; }

hsetup 's/^2\. Build with tests\./2. Build./'; content repos/o/r/contents/.team/team.md main 'mode: cloud'; arun
! amerged && carded && asaid "team/CLOUD.md is outside the green class (.team/" && ok "home: a repo with .team/team.md is a team repo, whatever else it holds" || nok "home: detection"

grep -q "startsWith(github.event.comment.body, 'Judge review posted, head ')" "$WF" && ok "auto: the Judge's 'Judge review posted' comment wakes the job" || nok "auto: wake comment"

grep -q "workflows: \[" "$WF" && grep -q 'pull_request_target' "$WF" && grep -q "github.event.action == 'created' && github.event.issue.pull_request" "$WF" && grep -q "user.login == 'chatgpt-codex-connector\[bot\]'" "$WF" && ok "auto: triggers on the PR, Codex's comments and finished CI" || nok "auto: triggers"

grep -q 'github.event.comment.body }}' "$WF" && ! grep -qE 'run:.*\$\{\{' "$WF" && ok "comment body reaches the script only through env" || nok "body through env"
grep -q 'actions/checkout' "$WF" && nok "checks out no code" || ok "checks out no code"

[ $fail = 0 ] && echo "PASS ($n)" || { echo FAIL; exit 1; }
