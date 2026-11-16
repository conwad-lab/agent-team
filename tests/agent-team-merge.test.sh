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

setup "feat: x" false $S; cj '[{id:16,user:{login:$bot},body:null}]'; run "agent-team-merge: $S"
! merged && said "no Codex comment, review or 👍" && ok "a Codex comment with an empty body: refused for that reason (jq does not fail)" || nok "null body"

grep -q 'github.event.comment.body }}' "$WF" && ! grep -qE 'run:.*\$\{\{' "$WF" && ok "comment body reaches the script only through env" || nok "body through env"
grep -q 'actions/checkout' "$WF" && nok "checks out no code" || ok "checks out no code"

[ $fail = 0 ] && echo "PASS ($n)" || { echo FAIL; exit 1; }
