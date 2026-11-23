#!/usr/bin/env bash
# tests for bin/watch, run with a fake gh that serves one fixture file per API path.
# Run: bash tests/watch.test.sh
set -u
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; n=0
ok()  { n=$((n+1)); echo "ok $n - $1"; }
nok() { n=$((n+1)); fail=1; echo "not ok $n - $1"; }
check() { if eval "$2"; then ok "$1"; else nok "$1"; fi; }

FIX="$T/fix"; mkdir -p "$FIX" "$T/bin"
cat > "$T/bin/gh" <<'G'
#!/usr/bin/env bash
url="${*: -1}"; f="$FIX/$(printf '%s' "$url" | tr -c 'A-Za-z0-9' '_')"
echo "$url" >> "$FIX/calls"
[ -f "$f.502" ] && { echo "HTTP 502: Bad Gateway" >&2; exit 1; }
[ -f "$f.404" ] && { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
[ -f "$f" ] && { cat "$f"; exit 0; }
case "$url" in
  */actions/runs/*/jobs) echo '{"jobs":[]}' ;;
  */actions/runs*) echo '{"workflow_runs":[]}' ;;
  */git/trees/*) echo '{"tree":[]}' ;;
  */reactions) echo '[]' ;;
  *) echo '[]' ;;
esac
G
chmod +x "$T/bin/gh"
export FIX WATCH_RETRY_WAIT=0

NOW_ISO=2026-11-10T12:00:00Z
NOW="$(jq -rn --arg t "$NOW_ISO" '$t|fromdateiso8601')"
t() { jq -rn --argjson s $(( NOW - $1 )) '$s|todateiso8601'; }   # t <seconds ago>
H=3600; D=86400
put() { cat > "$FIX/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '_')"; }
b64() { printf '%s' "$1" | base64 | tr -d '\n'; }
run() { : > "$FIX/calls"; PATH="$T/bin:$PATH" bash "$SKILL/bin/watch" --now "$NOW_ISO" --board "$T/board.md" "$@" > "$T/out" 2> "$T/err"; echo $? > "$T/rc"; }
has()  { grep -q "$1" "$T/out"; }
row()  { grep -F "| $1 |" "$T/board.md"; }

# ---- repo o/r: one story in every state, every stall kind
put repos/o/r <<< '{"default_branch":"main"}'
{ for s in 001-ready 002-planned 003-split 004-superseded _005-parked 006-building 007-draft 008-judging 009-approved 010-changes 011-escalated 012-done 013-done-old 015-stale 016-superseded-pr; do
    echo ".team/backlog/$s.md"; done; printf '%s\n' .team/plans/002-planned.md .team/plans/003-split.md .team/plans/006-building.md .team/backlog/.gitkeep
} | jq -R '{path: .}' | jq -s '{tree: .}' | put "repos/o/r/git/trees/main?recursive=1"
put "repos/o/r/contents/.team/plans/003-split.md?ref=main" <<< "{\"content\":\"$(b64 $'---\nverdict: needs-split\n---\n')\"}"
put "repos/o/r/contents/.team/plans/002-planned.md?ref=main" <<< "{\"content\":\"$(b64 $'---\nverdict: plan\n---\n')\"}"
put "repos/o/r/contents/.team/backlog/004-superseded.md?ref=main" <<< "{\"content\":\"$(b64 $'---\nsuperseded-by: 006\n---\n')\"}"

pr() { # number title state draft merged_at updated_ago ref
  local m=null; [ "$5" != - ] && m="\"$5\""
  printf '{"number":%s,"title":"%s","state":"%s","draft":%s,"merged_at":%s,"updated_at":"%s","head":{"ref":"%s","sha":"sha%s"},"html_url":"https://github.com/o/r/pull/%s"},' \
    "$1" "$2" "$3" "$4" "$m" "$(t "$6")" "$7" "$1" "$1"
}
{
  printf '['
  pr 7  "007: draft"      open   true  -           $((2*H))  feat/007-draft
  pr 8  "008: judging"    open   false -           $((30*H)) feat/008-judging
  pr 9  "009: approved"   open   false -           $((30*H)) feat/009-approved
  pr 10 "010: changes"    open   false -           $((30*H)) feat/010-changes
  pr 11 "011: escalated"  open   false -           $((3*H))  feat/011-escalated
  pr 12 "012: done"       closed false "$(t $((2*D)))"  $((2*D))  feat/012-done
  pr 13 "013: done old"   closed false "$(t $((10*D)))" $((10*D)) feat/013-done-old
  pr 15 "015: stale"      open   false -           $((2*H))  feat/015-stale
  pr 16 "016: superseded" open   true  -           $((1*H))  feat/016-superseded-pr
  pr 14 "014: no story"   open   true  -           $((1*H))  feat/014-x
  pr 20 "board: tidy"     open   false -           $((1*H))  board/2026-11-10-tidy
  printf '{"number":1,"title":"old","state":"closed","draft":false,"merged_at":null,"updated_at":"%s","head":{"ref":"x","sha":"s"},"html_url":"u"}]' "$(t $((20*D)))"
} | put "repos/o/r/pulls?state=all&per_page=100"
put "repos/o/r/branches?per_page=100" <<< '[{"name":"main","commit":{"sha":"m"}},{"name":"feat/006-building","commit":{"sha":"b6"}},{"name":"feat/008-judging","commit":{"sha":"sha8"}},{"name":"feat/099-fresh","commit":{"sha":"b99"}}]'
put "repos/o/r/compare/main...feat/006-building" <<< '{"ahead_by":3}'
put "repos/o/r/compare/main...feat/099-fresh" <<< '{"ahead_by":1}'
put repos/o/r/commits/b6  <<< "{\"commit\":{\"committer\":{\"date\":\"$(t $((2*D)))\"}}}"
put repos/o/r/commits/b99 <<< "{\"commit\":{\"committer\":{\"date\":\"$(t $((2*H)))\"}}}"
put "repos/o/r/contents/.team/reviews?ref=sha8" <<< '[{"name":"008-x.response.md"}]'
for p in 009:approve 010:request-changes 011:escalate; do
  id="${p%%:*}"; v="${p#*:}"; s="sha$((10#$id))"
  put "repos/o/r/contents/.team/reviews?ref=$s" <<< "[{\"name\":\"$id-x.md\"},{\"name\":\"$id-x.response.md\"}]"
  put "repos/o/r/contents/.team/reviews/$id-x.md?ref=$s" <<< "{\"content\":\"$(b64 "---"$'\n'"verdict: $v"$'\n'"---"$'\n')\"}"
done

# 015: request-changes, then the Builder pushed code: the verdict is stale → judging (r3 M1)
put "repos/o/r/contents/.team/reviews?ref=sha15" <<< '[{"name":"015-x.md"}]'
put "repos/o/r/contents/.team/reviews/015-x.md?ref=sha15" <<< "{\"content\":\"$(b64 $'---\nverdict: request-changes\n---\n')\"}"
put "repos/o/r/commits?sha=sha15&path=.team/reviews/015-x.md&per_page=1" <<< '[{"sha":"r15"}]'
put "repos/o/r/compare/r15...sha15" <<< '{"files":[{"filename":".team/reviews/015-x.response.md"},{"filename":"src/a.js"}]}'
put "repos/o/r/contents/.team/backlog/016-superseded-pr.md?ref=main" <<< "{\"content\":\"$(b64 $'---\nsuperseded-by: 017\n---\n')\"}"
# 009: only the response file changed after the review: the verdict stands
put "repos/o/r/commits?sha=sha9&path=.team/reviews/009-x.md&per_page=1" <<< '[{"sha":"r9"}]'
put "repos/o/r/compare/r9...sha9" <<< '{"files":[{"filename":".team/reviews/009-x.response.md"}]}'
cm() { printf '{"id":%s,"user":{"login":"%s"},"created_at":"%s","body":"%s"},' "$1" "$2" "$(t "$3")" "$4"; }
BOT='chatgpt-codex-connector[bot]'
# 008: Codex's summary comment still says running: not an answer
jq -n --arg t1 "$(t $((2*H)))" --arg t2 "$(t 7000)" --arg bot "$BOT" '[{id:81,user:{login:"conwad-lab"},created_at:$t1,body:"@codex review\n\nfocus"},
  {id:82,user:{login:$bot},created_at:$t2,body:"<!-- codex-review-state:v1 {\"code_review\":{\"status\":\"running\"}} -->\nCodex Review Summary: Running"}]' | put "repos/o/r/issues/8/comments?per_page=100"
put "repos/o/r/issues/7/comments?per_page=100"  <<< "[$(cm 71 conwad-lab $((3*H)) '@codex review')$(cm 72 conwad-lab 5400 '@codex review' | sed 's/,$//')]"
put "repos/o/r/issues/9/comments?per_page=100"  <<< "[$(cm 91 conwad-lab $((2*H)) '@codex review')$(cm 92 "$BOT" 5400 'Codex Review: no issues')$(cm 93 conwad-lab $((20*H)) 'Card posted 2026-11-09T16:00Z: Human-only, recommended Merga' | sed 's/,$//')]"
put "repos/o/r/issues/10/comments?per_page=100" <<< "[$(cm 101 conwad-lab $((2*H)) '@codex review')$(cm 102 conwad-lab $((20*H)) 'Card posted 2026-11-09T16:00Z: x')$(cm 103 conwad-lab $((19*H)) 'Card answered 2026-11-09T17:00Z: Vänta' | sed 's/,$//')]"
put "repos/o/r/issues/comments/101/reactions" <<< "[{\"user\":{\"login\":\"$BOT\"},\"content\":\"+1\"}]"
put "repos/o/r/issues/30/comments?per_page=100" <<< "[$(cm 301 conwad-lab 1800 '@codex fix M1' | sed 's/,$//')]"
iss() { printf '{"number":%s,"html_url":"https://github.com/o/r/issues/%s"%s},' "$1" "$1" "$2"; }
put "repos/o/r/issues?state=all&per_page=100&since=$(t $((7*D)))" <<< "[$(iss 7 ',"pull_request":{}')$(iss 8 ',"pull_request":{}')$(iss 9 ',"pull_request":{}')$(iss 10 ',"pull_request":{}')$(iss 40 ',"pull_request":{}')$(iss 41 ',"pull_request":{}')$(iss 42 '')$(iss 43 ',"pull_request":{}')$(iss 44 ',"pull_request":{}')$(iss 46 ',"pull_request":{}')$(iss 30 '')$(iss 48 ',"pull_request":{}')$(printf '{"number":47,"html_url":"u47","user":{"login":"conwad-lab"},"created_at":"%s","body":"@codex build x"},' "$(t $((3*H)))")$(printf '{"number":45,"html_url":"https://github.com/o/r/issues/45","user":{"login":"conwad-lab"},"created_at":"%s","body":"@codex build .team/plans/045-x.md"}' "$(t $((3*H)))")]"
put "repos/o/r/issues/45/reactions" <<< "[{\"user\":{\"login\":\"$BOT\"},\"content\":\"eyes\"}]"
# 047: an issue whose body got an @codex line by an edit: Codex never reacted, so no task (r3 M3)
# 048: original review 5 h, its retry 3 h, one result 2 h: the result answers both (v0.8.16; was r3 M2)
put "repos/o/r/issues/48/comments?per_page=100" <<< "[$(cm 481 conwad-lab $((5*H)) '@codex review')$(cm 482 conwad-lab $((3*H)) '@codex review' | sed 's/,$//')]"
put "repos/o/r/pulls/48/reviews?per_page=100" <<< "[{\"id\":2,\"user\":{\"login\":\"$BOT\"},\"submitted_at\":\"$(t $((2*H)))\"}]"
# 043: the summary comment, completed, is still not an answer (round 2 M1)
jq -n --arg t1 "$(t $((2*H)))" --arg t2 "$(t 6900)" --arg bot "$BOT" '[{id:431,user:{login:"conwad-lab"},created_at:$t1,body:"@codex review"},
  {id:432,user:{login:$bot},created_at:$t2,body:"<!-- codex-pull-request-review-summary -->\n<!-- codex-review-state:v1 {\"status\":\"completed\"} -->"}]' | put "repos/o/r/issues/43/comments?per_page=100"
# 044: a fix answered after an older review hangs: the answer takes the task, the review stays open (round 2 M2)
put "repos/o/r/issues/44/comments?per_page=100" <<< "[$(cm 441 conwad-lab $((3*H)) '@codex review')$(cm 442 conwad-lab 600 '@codex fix M1')$(cm 443 "$BOT" 300 'Pushed a fix for M1.' | sed 's/,$//')]"
# 046: a retry five minutes old is still within its hour (round 2 S1)
put "repos/o/r/issues/46/comments?per_page=100" <<< "[$(cm 461 conwad-lab $((3*H)) '@codex review')$(cm 462 conwad-lab 300 '@codex review' | sed 's/,$//')]"
# 040: two angle requests in one batch, one review answers both (v0.8.16; was one each, M2)
put "repos/o/r/issues/40/comments?per_page=100" <<< "[$(cm 401 conwad-lab $((3*H)) '@codex review — security')$(cm 402 conwad-lab $((3*H-120)) '@codex review — failure paths' | sed 's/,$//')]"
put "repos/o/r/pulls/40/reviews?per_page=100" <<< "[{\"id\":1,\"user\":{\"login\":\"$BOT\"},\"submitted_at\":\"$(t $((5*H/2)))\"}]"
# 041: an earlier request answered by 👍, a new one unanswered → retry, not silent
put "repos/o/r/issues/41/comments?per_page=100" <<< "[$(cm 411 conwad-lab $((5*H)) '@codex review')$(cm 412 conwad-lab $((2*H)) '@codex review' | sed 's/,$//')]"
put "repos/o/r/issues/comments/411/reactions" <<< "[{\"user\":{\"login\":\"$BOT\"},\"content\":\"+1\"}]"
# 042: a fix task unanswered → codex-task, never an automatic review retry
put "repos/o/r/issues/42/comments?per_page=100" <<< "[$(cm 421 conwad-lab $((2*H)) '@codex fix M1: quote the path' | sed 's/,$//')]"
put "repos/o/r/actions/runs?status=queued&per_page=100" <<< "{\"workflow_runs\":[{\"id\":100,\"name\":\"ci\",\"created_at\":\"$(t 2700)\",\"html_url\":\"r100\"},{\"id\":101,\"name\":\"ci\",\"created_at\":\"$(t 600)\",\"html_url\":\"r101\"},{\"id\":102,\"name\":\"ci\",\"created_at\":\"$(t $((2*H)))\",\"html_url\":\"r102\",\"pull_requests\":[{\"number\":10}]}]}"
put "repos/o/r/actions/runs?status=failure&created=%3E%3D$(t $((7*D)))&per_page=100" <<< "{\"workflow_runs\":[{\"id\":200,\"name\":\"ci\",\"created_at\":\"$(t $H)\",\"html_url\":\"r200\"},{\"id\":201,\"name\":\"e2e\",\"created_at\":\"$(t $H)\",\"html_url\":\"r201\"},{\"id\":203,\"name\":\"ci\",\"created_at\":\"$(t $((2*D)))\",\"updated_at\":\"$(t $H)\",\"html_url\":\"r203\"},{\"id\":204,\"name\":\"ci\",\"created_at\":\"$(t $((3*D)))\",\"updated_at\":\"$(t $((2*D)))\",\"html_url\":\"r204\"}]}"
put repos/o/r/actions/runs/200/jobs <<< '{"jobs":[{"steps":[],"runner_name":null}]}'
put repos/o/r/actions/runs/201/jobs <<< '{"jobs":[{"steps":[{"name":"x"}],"runner_name":"GitHub Actions 2"}]}'

run o/r
check "stalls exit 1" '[ "$(cat "$T/rc")" = 1 ]'
check "pr-idle: ready PR, no card"            'has "pr-idle	#8 008: judging"'
check "pr-idle skipped: open card"            '! has "pr-idle	#9 "'
check "pr-idle skipped: Vänta answer"         '! has "pr-idle	#10 "'
check "fresh PRs not idle"                    '! has "pr-idle	#7 " && ! has "pr-idle	#20 "'
check "branch-idle: no PR, 2 d"               'has "branch-idle	feat/006-building"'
check "fresh branch not idle"                 '! has "feat/099-fresh"'
check "queued past 30 min"                    'has "queued	ci: queued" && has "r100" && ! has "r101"'
check "old run failing today is caught, old failure is not" 'has "r203" && ! has "r204"'
check "queued run on a carded PR skipped (r3 S1)" '! has "r102"'
check "not-started run flagged, started one not" 'has "not-started" && has "r200" && ! has "r201"'
check "codex-retry: asked once, 2 h"          'has "codex-retry	#8:"'
check "codex-silent: asked twice"             'has "codex-silent	#7:"'
check "Codex comment answers"                 '! has "#9: @codex"'
check "Codex 👍 answers"                      '! has "#10: @codex"'
check "under an hour is quiet"                '! has "#30:"'
check "one review answers the whole batch (v0.8.16)" '! has "#40:"'
check "earlier 👍 not counted (M3)"            'has "codex-retry	#41: 1 @codex"'
check "fix task is codex-task (M4)"           'has "codex-task	#42:"'
check "completed summary is no answer (r2 M1)" 'has "codex-retry	#43:"'
check "answers match their kind (r2 M2)"      'has "codex-retry	#44: 1 @codex"'
check "issue-body build task (r2 M3)"         'has "codex-task	#45:"'
check "fresh retry waits its hour (r2 S1)"    '! has "#46:"'
check "edited body is no task (r3 M3)"        '! has "#47:"'
check "one result answers the retry too (v0.8.16)" '! has "#48:"'
check "no blind"                              '! has "	blind	"'

check "board: ready"             'row 001-ready | grep -q "| ready | Coordinator |"'
check "board: planned"           'row 002-planned | grep -q "| planned | Coordinator |"'
check "board: needs-split"       'row 003-split | grep -q "| needs-split | Coordinator |"'
check "board: superseded absent" '! row 004-superseded'
check "board: superseded with a PR absent" '! row 016-superseded-pr'
check "board: parked absent"     '! grep -q "005-parked" "$T/board.md"'
check "board: branch → building, age" 'row 006-building | grep -q "| building | Builder | 2 d ago |"'
check "board: draft → building"  'row 007-draft | grep -q "| building | Builder |"'
check "board: judging"           'row 008-judging | grep -q "| judging | Judge |"'
check "board: approved, card open → human" 'row 009-approved | grep -q "| approved | human (card open 20 h) |"'
check "board: Vänta → human"     'row 010-changes | grep -q "| changes-requested | human (Vänta 19 h) |"'
check "board: escalated"         'row 011-escalated | grep -q "| escalated | human |"'
check "board: stale verdict → judging (r3 M1)" 'row 015-stale | grep -q "| judging | Judge |"'
check "board: done this week"    'row 012-done | grep -q "| done |"'
check "board: old done absent"   '! row 013-done-old'
check "board: PR without story"  'grep -q "| 014 (story not on main) | building |" "$T/board.md"'
check "board: escalated sorts first" '[ "$(grep -m1 "^| r |" "$T/board.md" | cut -d"|" -f3 | tr -d " ")" = 011-escalated ]'

# ---- quiet repo: nothing to say
put repos/o/q <<< '{"default_branch":"main"}'
run o/q
check "quiet: exit 0"          '[ "$(cat "$T/rc")" = 0 ]'
check "quiet: no output"       '[ ! -s "$T/out" ]'
check "quiet: board written"   'grep -q "^| Repo |" "$T/board.md"'

# ---- blind: an unreadable repo and an endpoint that fails twice
touch "$FIX/$(printf '%s' repos/o/gone | tr -c 'A-Za-z0-9' '_').404"
put repos/o/f <<< '{"default_branch":"main"}'
touch "$FIX/$(printf '%s' 'repos/o/f/actions/runs?status=queued&per_page=100' | tr -c 'A-Za-z0-9' '_').502"
run o/gone o/f
check "blind: exit 2"                 '[ "$(cat "$T/rc")" = 2 ]'
check "blind: missing repo"           'has "^o/gone	blind	"'
check "blind: failing endpoint"       'has "^o/f	blind	cannot read repos/o/f/actions/runs?status=queued"'
check "blind: retried once"           '[ "$(grep -c "status=queued" "$FIX/calls")" = 2 ]'
check "blind: a 404 on a required read (M1)" 'touch "$FIX/$(printf "%s" "repos/o/f/branches?per_page=100" | tr -c "A-Za-z0-9" "_").404"; run o/f; has "^o/f	blind	cannot read repos/o/f/branches"'
run o/gone o/f
check "blind: named on the board"     'grep -q "^\*\*Blind:\*\* o/gone" "$T/board.md"'

# ---- the board cannot be written (S1)
: > "$FIX/calls"; PATH="$T/bin:$PATH" bash "$SKILL/bin/watch" --now "$NOW_ISO" --board "$T/no/such/dir/b.md" o/q > "$T/out" 2> "$T/err"; echo $? > "$T/rc"
check "unwritable board: exit 2 (S1)" '[ "$(cat "$T/rc")" = 2 ] && grep -q "cannot write the board" "$T/err"'

# ---- estimates (story D): merged stories with an Estimate against their Outcome
put repos/o/e <<< '{"default_branch":"main"}'
printf '%s\n' .team/backlog/008-parts.md .team/plans/008-parts.md .team/reviews/008-parts.response.md .team/backlog/007-norounds.md .team/plans/007-norounds.md .team/reviews/007-norounds.response.md .team/backlog/001-held.md .team/backlog/002-rounds.md .team/backlog/003-switch.md .team/backlog/004-nooutcome.md .team/backlog/005-noest.md .team/backlog/006-open.md \
  .team/plans/001-held.md .team/plans/002-rounds.md .team/plans/003-switch.md .team/plans/004-nooutcome.md .team/plans/005-noest.md .team/plans/006-open.md \
  .team/reviews/001-held.response.md .team/reviews/002-rounds.response.md .team/reviews/003-switch.response.md \
  | jq -R '{path: .}' | jq -s '{tree: .}' | put "repos/o/e/git/trees/main?recursive=1"
plan() { put "repos/o/e/contents/.team/plans/$1.md?ref=main" <<< "{\"content\":\"$(b64 "---"$'\n'"verdict: plan"$'\n'"---"$'\n\n'"## Approach"$'\n'"builder: claude in prose"$'\n\n'"$2")\"}"; }
est() { printf '## Estimate\nsize: %s\nrisk: %s\nfiles: 3\ncodex-rounds: %s\nbuilder: %s — reason\n\n## Files\n' "$@"; }
plan 001-held "$(printf '## Estimate\nsize: S\nrisk: plain\nfiles: 3\ncodex-rounds: 2\nbuilder: codex — reason\nmodel: light — a small plain story\n\n## Files\n')"
plan 002-rounds "$(printf '## Estimate\nsize: M\nrisk: plain\nfiles: 3\ncodex-rounds: 1\nbuilder: codex — reason\nmodel: standard — M plain\n\n## Files\nmodel: prose outside the Estimate\n')"
plan 003-switch "$(est S plain 2 codex)"
plan 004-nooutcome "$(est L adversarial 3 claude)"
plan 005-noest $'## Files\n- x'
plan 006-open "$(est S plain 1 codex)"
plan 007-norounds "$(est S plain '<n>' codex)"
plan 008-parts "$(est S plain 2 codex)"$'- `src/api.ts` — spine\n\n## Parts\n<!-- Optional (team/PARTS.md [P1]). -->\n- p1 — files: `tests/a.test.ts` — check: `true` — model: light\n- p2 — files: `docs/a.md` — check: `true` — model: light\n\n## Steps\n- not a part\n'
resp() { put "repos/o/e/contents/.team/reviews/$1.response.md?ref=main" <<< "{\"content\":\"$(b64 "$2")\"}"; }
resp 001-held $'## Codex round 1 — 2026-11-01\n- M1 fixed in a\n\n## Codex round 2 — 2026-11-01\n- none\n\n## Outcome\nbuilt-by: codex\nmodel: claude-sonnet-5-5\nmissed: nothing'
resp 002-rounds $'## Codex round 1 — 2026-11-01\n## Codex round 2 — 2026-11-01\n## Codex round 3 — 2026-11-02\n## Judge round 1 — 2026-11-02\n\n## Outcome\nbuilt-by: codex\nmissed: the parser'
resp 008-parts $'## Codex round 1 — 2026-11-01\n\n## Outcome\nbuilt-by: codex\nparts: 1 taken, 1 rebuilt — p2: header | name not in the plan\nmissed: nothing'
resp 007-norounds $'## Codex round 1 — 2026-11-01\n\n## Outcome\nbuilt-by: codex'
resp 003-switch $'## Codex round 1 — 2026-11-01\n\n## Outcome\nbuilt-by: codex->claude\nmissed: Codex failed twice'
epr() { # number title merged_ago opened_ago
  printf '{"number":%s,"title":"%s","state":"closed","draft":false,"merged_at":"%s","updated_at":"%s","created_at":"%s","head":{"ref":"feat/x","sha":"s%s"},"html_url":"https://github.com/o/e/pull/%s"},' \
    "$1" "$2" "$(t "$3")" "$(t "$3")" "$(t "$4")" "$1" "$1"; }
{ printf '['
  epr 1 "001: held" $((20*D)) $((20*D+4*H))
  epr 2 "002: rounds" $((2*D)) $((2*D+10*H))
  epr 3 "003: switch" $((3*D)) $((3*D+6*H))
  epr 4 "004: no outcome" $((1*D)) $((1*D+30*H))
  epr 5 "005: no estimate" $((1*D)) $((1*D+2*H))
  epr 7 "007: no rounds" $((1*D)) $((1*D+1*H))
  epr 8 "008: parts" $((1*D)) $((1*D+3*H))
  printf '{"number":6,"title":"006: open","state":"open","draft":true,"merged_at":null,"updated_at":"%s","created_at":"%s","head":{"ref":"feat/006-open","sha":"s6"},"html_url":"u6"}]' "$(t H)" "$(t H)"
} | put "repos/o/e/pulls?state=all&per_page=100"

run o/e
check "estimates: no flag, no plan reads" '! grep -q "plans/001-held" "$FIX/calls" && [ ! -e "$T/est.md" ]'
: > "$FIX/calls"; PATH="$T/bin:$PATH" bash "$SKILL/bin/watch" --now "$NOW_ISO" --estimates "$T/est.md" o/e > "$T/out" 2> "$T/err"; echo $? > "$T/rc"
erow() { grep -F "[$1](" "$T/est.md"; }
check "estimates: written, exit 0"     '[ "$(cat "$T/rc")" = 0 ] && grep -q "^| Repo | Story | Size |" "$T/est.md"'
check "estimates: held"                'erow 001-held | grep -q "| S | plain | codex | codex | 2/2 | 4 | yes |"'
check "estimates: rounds over"         'erow 002-rounds | grep -q "| M | plain | codex | codex | 1/3 | 10 | no (rounds) |"'
check "estimates: builder switched"    'erow 003-switch | grep -q "| codex | codex→claude | 2/1 | 6 | no (builder) |"'
check "estimates: no outcome → —"      'erow 004-nooutcome | grep -q "| L | adversarial | claude | — | 3/0 | 30 | — |"'
check "estimates: no Estimate absent"  '! erow 005-noest'
check "estimates: unmerged absent"     '! erow 006-open'
check "estimates: prose builder: ignored" '! grep -q "| claude in" "$T/est.md"'
check "estimates: no numeric rounds → unknown (r1 S1)" 'erow 007-norounds | grep -q "| ? (no codex-rounds) |"'
check "estimates: Model column (v0.8.6)"  'grep -q "| Held | Model planned → actual | Parts |$" "$T/est.md"'
check "estimates: model planned → actual" 'erow 001-held | grep -q "| yes | light → claude-sonnet-5-5 | - |$"'
check "estimates: model planned, none recorded" 'erow 002-rounds | grep -q "| no (rounds) | standard → — | - |$"'
check "estimates: no model on either side → —" 'erow 004-nooutcome | grep -q "| — | — | - |$"'
check "estimates: footer S codex"      'grep -q "^| S | codex | no | 2 | 1 | 2.5 |" "$T/est.md"'
check "estimates: footer median"       'grep -q "^| M | codex | no | 1 | 0 | 10 |" "$T/est.md"'
check "estimates: Parts column, plan lines and Outcome (v0.8.11)" 'erow 008-parts | grep -q "| 2/1 | 3 | yes | — | 2: 1 taken, 1 rebuilt — p2: header / name not in the plan |$"'
check "estimates: footer counts parts stories apart" 'grep -q "^| S | codex | yes | 1 | 1 | 3 |" "$T/est.md"'

# ---- codex-quota (v0.8.6): Codex's latest reply says its usage limit is reached (wording from agent-team #24, #25)
put repos/o/k <<< '{"default_branch":"main"}'
# PR 2 has been quiet for 30 h and waits only on the quota; PR 3 is quiet too, its quota wait over (#27 r3 M1)
printf '[{"number":2,"title":"002: quota","state":"open","draft":true,"merged_at":null,"updated_at":"%s","head":{"ref":"feat/002-quota","sha":"k2"},"html_url":"https://github.com/o/k/pull/2"},{"number":3,"title":"003: idle","state":"open","draft":true,"merged_at":null,"updated_at":"%s","head":{"ref":"feat/003-idle","sha":"k3"},"html_url":"https://github.com/o/k/pull/3"}]' "$(t $((30*H)))" "$(t $((30*H)))" | put "repos/o/k/pulls?state=all&per_page=100"
QUOTA='You have reached your Codex usage limits for code reviews. You can see your limits in the [Codex usage dashboard](https://chatgpt.com/codex/cloud/settings/usage).'
put "repos/o/k/issues?state=all&per_page=100&since=$(t $((7*D)))" <<< "[$(iss 1 ',"pull_request":{}')$(iss 2 ',"pull_request":{}')$(iss 3 ',"pull_request":{}')$(iss 4 ',"pull_request":{}')$(iss 5 '')$(iss 6 ',"pull_request":{}')$(iss 7 ',"pull_request":{}')$(iss 8 ',"pull_request":{}')$(iss 9 ',"pull_request":{}' | sed 's/,$//')]"
sed -i 's#github.com/o/r/issues#github.com/o/k/issues#g' "$FIX/$(printf '%s' "repos/o/k/issues?state=all&per_page=100&since=$(t $((7*D)))" | tr -c 'A-Za-z0-9' '_')"
# 1: asked 3 h ago, the only answer is a usage-limit reply (and the summary) → codex-quota, not codex-retry
jq -n --arg bot "$BOT" --arg q "$QUOTA" --arg t1 "$(t $((3*H)))" --arg t2 "$(t $((3*H-10)))" '[{id:11,user:{login:"conwad-lab"},created_at:$t1,body:"@codex review"},
  {id:12,user:{login:$bot},created_at:$t2,body:"<!-- codex-pull-request-review-summary -->\n<!-- codex-review-state:v1 {\"status\":\"failed\"} -->"},
  {id:13,user:{login:$bot},created_at:$t2,body:$q}]' | put "repos/o/k/issues/1/comments?per_page=100"
# 2: usage limit 30 h ago, re-asked, usage limit again 5 h ago → one streak, since the first reply
put "repos/o/k/issues/2/comments?per_page=100" <<< "[$(cm 21 conwad-lab $((30*H+60)) '@codex review')$(cm 22 "$BOT" $((30*H)) 'You have reached your Codex usage limits for code reviews.')$(cm 23 conwad-lab $((5*H+60)) '@codex review')$(cm 24 "$BOT" $((5*H)) 'You have reached your Codex usage limits.' | sed 's/,$//')]"
# 3: usage limit, re-asked, then a finished review (receipt) → the quota is back, nothing to say
put "repos/o/k/issues/3/comments?per_page=100" <<< "[$(cm 31 conwad-lab $((5*H+60)) '@codex review')$(cm 32 "$BOT" $((5*H)) 'You have reached your Codex usage limits for code reviews.')$(cm 33 conwad-lab $((2*H)) '@codex review')$(cm 34 "$BOT" $H '<!-- codex-review-receipt:v1 --> Codex Review: no major issues, usage limit rule and codex-pull-request-review-summary filter included.' | sed 's/,$//')]"
# 4: usage limit, then a re-request Codex has not answered for 2 h → still codex-quota, never codex-retry
put "repos/o/k/issues/4/comments?per_page=100" <<< "[$(cm 41 conwad-lab $((5*H+60)) '@codex review')$(cm 42 "$BOT" $((5*H)) 'You have reached your Codex usage limits for code reviews.')$(cm 43 conwad-lab $((2*H)) '@codex review' | sed 's/,$//')]"
# 5: a fix task on an issue stopped by the quota → codex-quota, not codex-task
put "repos/o/k/issues/5/comments?per_page=100" <<< "[$(cm 51 conwad-lab $((2*H)) '@codex fix M1')$(cm 52 "$BOT" $((2*H-30)) 'You have reached your Codex usage limits.' | sed 's/,$//')]"
# 6: usage limit, then a re-request Codex answered with 👍 an hour ago → the quota is back (Codex M1 on #27)
put "repos/o/k/issues/6/comments?per_page=100" <<< "[$(cm 61 conwad-lab $((5*H+60)) '@codex review')$(cm 62 "$BOT" $((5*H)) 'You have reached your Codex usage limits for code reviews.')$(cm 63 conwad-lab $((2*H)) '@codex review' | sed 's/,$//')]"
put "repos/o/k/issues/comments/63/reactions" <<< "[{\"user\":{\"login\":\"$BOT\"},\"content\":\"+1\",\"created_at\":\"$(t $H)\"}]"
# 7: an early request got its 👍 before the usage-limit reply to a later one → still codex-quota
put "repos/o/k/issues/7/comments?per_page=100" <<< "[$(cm 71 conwad-lab $((9*H)) '@codex review')$(cm 72 conwad-lab $((5*H+60)) '@codex review')$(cm 73 "$BOT" $((5*H)) 'You have reached your Codex usage limits for code reviews.' | sed 's/,$//')]"
put "repos/o/k/issues/comments/71/reactions" <<< "[{\"user\":{\"login\":\"$BOT\"},\"content\":\"+1\",\"created_at\":\"$(t $((8*H)))\"}]"
# 8: as 6, but the 👍 carries no date: the request's own time (after the usage-limit reply) dates it
put "repos/o/k/issues/8/comments?per_page=100" <<< "[$(cm 81 conwad-lab $((5*H+60)) '@codex review')$(cm 82 "$BOT" $((5*H)) 'You have reached your Codex usage limits for code reviews.')$(cm 83 conwad-lab $((2*H)) '@codex review' | sed 's/,$//')]"
put "repos/o/k/issues/comments/83/reactions" <<< "[{\"user\":{\"login\":\"$BOT\"},\"content\":\"+1\"}]"
# 9: usage limit 80 h ago, a retry got its 👍 1 h ago, then a new request got a usage-limit reply: a new streak (#27 r2 M1)
put "repos/o/k/issues/9/comments?per_page=100" <<< "[$(cm 91 conwad-lab $((80*H+60)) '@codex review')$(cm 92 "$BOT" $((80*H)) 'You have reached your Codex usage limits for code reviews.')$(cm 93 conwad-lab $((2*H)) '@codex review')$(cm 94 conwad-lab 1200 '@codex review')$(cm 95 "$BOT" 600 'You have reached your Codex usage limits for code reviews.' | sed 's/,$//')]"
put "repos/o/k/issues/comments/93/reactions" <<< "[{\"user\":{\"login\":\"$BOT\"},\"content\":\"+1\",\"created_at\":\"$(t $H)\"}]"
run o/k
check "quota: no pr-idle for a PR that waits on the quota (#27 r3 M1)" '! has "pr-idle	#2 " && has "pr-idle	#3 "'
check "quota: a 👍 between two usage-limit replies starts a new streak (#27 r2 M1)" 'has "codex-quota	#9: Codex usage limit reached, last reply 10 min ago	$(t 600)	"'
check "quota: a 👍 on a later request ends the streak (#27 M1)" '! has "#6:" && ! has "#8:"'
check "quota: a 👍 older than the usage-limit reply does not" 'has "codex-quota	#7:"'
check "quota: a usage-limit reply is codex-quota, exit 1" 'has "^o/k	codex-quota	#1: Codex usage limit reached" && [ "$(cat "$T/rc")" = 1 ]'
check "quota: streak dated from its first reply"  'has "codex-quota	#2: Codex usage limit reached, last reply 5 h ago	$(t $((30*H)))	"'
check "quota: a finished review ends the streak, a receipt naming the summary markers too (#27 ready review)"  '! has "#3:"'
check "quota: wins over an unanswered re-request" 'has "codex-quota	#4:"'
check "quota: a task stopped by the quota"        'has "codex-quota	#5:"'
check "quota: no other codex kind on those"       '! has "codex-retry" && ! has "codex-silent" && ! has "codex-task"'

# ---- more than 100 PRs (v0.8.4): pages are asked for by &page=N, never by following Link headers
put repos/o/p <<< '{"default_branch":"main"}'
{ printf '['; for i in $(seq 101 200); do printf '{"number":%s,"title":"old","state":"closed","draft":false,"merged_at":null,"updated_at":"%s","head":{"ref":"x","sha":"s"},"html_url":"u"}' "$i" "$(t $((20*D)))"; [ "$i" -lt 200 ] && printf ','; done; printf ']'; } \
  | put "repos/o/p/pulls?state=all&per_page=100"
printf '[{"number":5,"title":"005: idle","state":"open","draft":false,"merged_at":null,"updated_at":"%s","head":{"ref":"feat/005-idle","sha":"s5"},"html_url":"https://github.com/o/p/pull/5"}]' "$(t $((3*D)))" \
  | put "repos/o/p/pulls?state=all&per_page=100&page=2"
run o/p
check "pages: an idle PR on page 2 is seen" 'has "^o/p	pr-idle	#5 005: idle"'
check "pages: page 2 asked for by number"   'grep -qx "repos/o/p/pulls?state=all&per_page=100&page=2" "$FIX/calls"'
check "pages: stops at the short page"      '! grep -q "page=3" "$FIX/calls" && [ "$(cat "$T/rc")" = 1 ]'
touch "$FIX/$(printf '%s' 'repos/o/p/pulls?state=all&per_page=100&page=2' | tr -c 'A-Za-z0-9' '_').502"
run o/p
check "pages: a failing page 2 is blind and named" 'has "^o/p	blind	cannot read repos/o/p/pulls?state=all&per_page=100&page=2" && [ "$(cat "$T/rc")" = 2 ]'
rm -f "$FIX/$(printf '%s' 'repos/o/p/pulls?state=all&per_page=100&page=2' | tr -c 'A-Za-z0-9' '_').502"
WATCH_MAX_PAGES=1 run o/p
check "pages: past the cap is blind, not cut"   'has "^o/p	blind	cannot read repos/o/p/pulls?state=all&per_page=100: more than 1 pages" && ! grep -q "page=2" "$FIX/calls"'

# ---- parked PRs and branches already in main (v0.8.7, CLOUD.md [R8])
put repos/o/z <<< '{"default_branch":"main"}'
printf '%s\n' .team/backlog/006-parked-story.md | jq -R '{path: .}' | jq -s '{tree: .}' | put "repos/o/z/git/trees/main?recursive=1"
{ printf '['
  for i in 1 2 3 4 5 6 7 8 9; do
    title="00$i: pr $i"
    printf '{"number":%s,"title":"%s","state":"open","draft":false,"merged_at":null,"updated_at":"%s","head":{"ref":"feat/00%s-pr","sha":"z%s"},"html_url":"https://github.com/o/z/pull/%s"}' "$i" "$title" "$(t $((30*H)))" "$i" "$i" "$i"
    [ "$i" -lt 9 ] && printf ','
  done; printf ']'; } | put "repos/o/z/pulls?state=all&per_page=100"
pc() { jq -n --arg u "$1" --arg t "$(t "$2")" --arg b "$3" --argjson id "${4:-1}" '{id:$id,user:{login:$u},created_at:$t,body:$b}'; }
# 1: parked by the owner, date ahead, CRLF body as GitHub stores it → no stall, on the board
pc o $((20*H)) $'Parkerad.\r\nParked until 2026-12-01: no Actions minutes\r\nmore' | jq -s . | put "repos/o/z/issues/1/comments?per_page=100"
# 2: parked by the owner, date past → stall
pc o $((20*H)) 'Parked until 2026-11-09: waited' | jq -s . | put "repos/o/z/issues/2/comments?per_page=100"
# 3: a stranger's park line → stall
pc stranger $((20*H)) 'Parked until 2026-12-01: let me park it' | jq -s . | put "repos/o/z/issues/3/comments?per_page=100"
# 4: parked, then a later card line → the card line decides (answered Merga: none) → stall
{ pc o $((20*H)) 'Parked until 2026-12-01: x' 1; pc o $((10*H)) 'Card answered 2026-11-10T02:00Z: Merga' 2; } | jq -s . | put "repos/o/z/issues/4/comments?per_page=100"
# 5: parked by the agent account → no stall
pc agent-bot $((20*H)) 'Parked until 2026-12-01: by the agent account' | jq -s . | put "repos/o/z/issues/5/comments?per_page=100"
# 6: a story PR, parked → the story row is the Coordinator's
pc o $((20*H)) 'Parked until 2026-12-01: story waits' | jq -s . | put "repos/o/z/issues/6/comments?per_page=100"
# 7: a card line, then a park line → the park line decides → no stall
{ pc o $((20*H)) 'Card posted 2026-11-09T16:00Z: x, recommended Merga' 1; pc o $((10*H)) 'Parked until 2026-12-01: later' 2; } | jq -s . | put "repos/o/z/issues/7/comments?per_page=100"
# 8: parked until today: holds through the end of the UTC day
pc o $((20*H)) 'Parked until 2026-11-10: today' | jq -s . | put "repos/o/z/issues/8/comments?per_page=100"
# 9: a date that does not exist (jq rolls it over to 12-01) parks nothing → stall (#28 Codex M1)
pc o $((20*H)) 'Parked until 2026-11-31: typo' | jq -s . | put "repos/o/z/issues/9/comments?per_page=100"
put "repos/o/z/branches?per_page=100" <<< '[{"name":"main","commit":{"sha":"m"}},{"name":"feat/020-inmain","commit":{"sha":"c20"}},{"name":"feat/021-ahead","commit":{"sha":"c21"}}]'
put "repos/o/z/compare/main...feat/020-inmain" <<< '{"ahead_by":0,"behind_by":4}'
put "repos/o/z/compare/main...feat/021-ahead" <<< '{"ahead_by":2}'
put repos/o/z/commits/c20 <<< "{\"commit\":{\"committer\":{\"date\":\"$(t $((5*D)))\"}}}"
put repos/o/z/commits/c21 <<< "{\"commit\":{\"committer\":{\"date\":\"$(t $((5*D)))\"}}}"
AGENT_ACCOUNT=agent-bot run o/z
check "parked: future date, owner's line → no pr-idle"   '! has "pr-idle	#1 "'
check "parked: past date → pr-idle"                      'has "pr-idle	#2 "'
check "parked: a stranger's line → pr-idle"              'has "pr-idle	#3 "'
check "parked: a later card line wins → pr-idle"         'has "pr-idle	#4 "'
check "parked: the agent account's line → no pr-idle"   '! has "pr-idle	#5 "'
check "parked: a later park line wins over a card line"  '! has "pr-idle	#7 "'
check "parked: holds through its own day"                '! has "pr-idle	#8 "'
check "parked: a nonexistent date parks nothing (#28 M1)" 'has "pr-idle	#9 "'
check "parked: board row → Coordinator"                  'row 006-parked-story | grep -q "| Coordinator (parked until 2026-12-01) |"'
check "parked: board lists it with its reason"           'grep -qF "| z | #1 001: pr 1 | parked until 2026-12-01: no Actions minutes | Coordinator | [#1](https://github.com/o/z/pull/1) |" "$T/board.md"'
check "parked: past or stranger lines not on the board"  '! grep -qF "#2 002" "$T/board.md" && ! grep -qF "#3 003" "$T/board.md"'
check "in main: ahead_by 0 → no branch-idle"             '! has "feat/020-inmain"'
check "in main: listed for deletion"                     'grep -qF "| z | feat/020-inmain | in main, delete | Operatör |" "$T/board.md"'
check "in main: own commits ahead → branch-idle"         'has "branch-idle	feat/021-ahead"'
check "in main: no commit read for it"                   '! grep -qx "repos/o/z/commits/c20" "$FIX/calls"'
check "parked: exit 1, no blind"                         '[ "$(cat "$T/rc")" = 1 ] && ! has "	blind	"'
run o/z
check "parked: without AGENT_ACCOUNT only the owner parks" 'has "pr-idle	#5 " && ! has "pr-idle	#1 "'
touch "$FIX/$(printf '%s' 'repos/o/z/compare/main...feat/020-inmain' | tr -c 'A-Za-z0-9' '_').502"
run o/z
check "in main: a failed compare is blind, never a skip" 'has "^o/z	blind	cannot read repos/o/z/compare/main...feat/020-inmain" && [ "$(cat "$T/rc")" = 2 ] && ! grep -qF "feat/020-inmain | in main" "$T/board.md"'
rm -f "$FIX/$(printf '%s' 'repos/o/z/compare/main...feat/020-inmain' | tr -c 'A-Za-z0-9' '_').502"
put "repos/o/z/compare/main...feat/020-inmain" <<< '{"message":"odd"}'
run o/z
check "in main: a compare without ahead_by is blind"     'has "^o/z	blind	cannot read repos/o/z/compare/main...feat/020-inmain: no ahead_by"'
put "repos/o/z/compare/main...feat/020-inmain" <<< '{"ahead_by":"0"}'
run o/z
check "in main: ahead_by as a string is blind (#28 M2)"  'has "^o/z	blind	cannot read repos/o/z/compare/main...feat/020-inmain: no ahead_by"'
put "repos/o/z/compare/main...feat/020-inmain" <<< '{"ahead_by":0} trailing junk'
run o/z
check "in main: invalid JSON after a zero is blind (#28 M2)" 'has "^o/z	blind	cannot read repos/o/z/compare/main...feat/020-inmain: no ahead_by" && [ "$(cat "$T/rc")" = 2 ]'
touch "$FIX/$(printf '%s' 'repos/o/z/issues/1/comments?per_page=100' | tr -c 'A-Za-z0-9' '_').502"
run o/z
check "parked: a failed comment read is blind"           'has "^o/z	blind	cannot read repos/o/z/issues/1/comments" && [ "$(cat "$T/rc")" = 2 ]'

# ---- v0.8.16: Codex CLI review branches and one receipt for every earlier review request
put repos/o/u <<< '{"default_branch":"main"}'
put "repos/o/u/branches?per_page=100" <<< '[{"name":"main","commit":{"sha":"m"}},{"name":"feat/900-designgranskning","commit":{"sha":"u900"}},{"name":"feat/901-own-work","commit":{"sha":"u901"}},{"name":"feat/902-review","commit":{"sha":"u902"}}]'
for b in 900-designgranskning 901-own-work 902-review; do put "repos/o/u/compare/main...feat/$b" <<< '{"ahead_by":1}'; done
cmt() { jq -n --arg d "$(t "$1")" --arg m "$2" '{commit:{committer:{date:$d},message:$m}}'; }
cmt $((2*D)) $'900: design review\n\nHinder: granskning klar i docs/motkritik-astra.md, ingen PR ska öppnas' | put repos/o/u/commits/u900
cmt $((2*D)) $'901: half a build\n\nHinder: inga' | put repos/o/u/commits/u901
cmt $((2*D)) $'902: review\n\nThe review is in docs/r.md; no PR is to be opened.' | put repos/o/u/commits/u902
# 5: review + security review together, one receipt; a retry 55 min later, one receipt (mondmodel #927)
put "repos/o/u/issues/5/comments?per_page=100" <<< "[$(cm 51 conwad-lab $((4*H)) '@codex review')$(cm 52 conwad-lab $((4*H-30)) '@codex security review')$(cm 53 "$BOT" $((4*H-360)) '<!-- codex-review-receipt:v1 --> Codex Review: no major issues')$(cm 54 conwad-lab $((3*H)) '@codex review')$(cm 55 "$BOT" $((3*H-300)) '<!-- codex-review-receipt:v1 --> Codex Review: no major issues' | sed 's/,$//')]"
# 6: a review request after the last receipt stays open
put "repos/o/u/issues/6/comments?per_page=100" <<< "[$(cm 61 conwad-lab $((5*H)) '@codex review')$(cm 62 "$BOT" $((4*H)) '<!-- codex-review-receipt:v1 --> no issues')$(cm 63 conwad-lab $((2*H)) '@codex review' | sed 's/,$//')]"
# 7: two tasks, one Codex comment: a task is still answered one at a time
put "repos/o/u/issues/7/comments?per_page=100" <<< "[$(cm 71 conwad-lab $((3*H)) '@codex fix M1')$(cm 72 conwad-lab $((3*H-60)) '@codex fix M2')$(cm 73 "$BOT" $((2*H)) 'Pushed a fix for M1.' | sed 's/,$//')]"
# 8: a receipt with no review open still answers a task
put "repos/o/u/issues/8/comments?per_page=100" <<< "[$(cm 81 conwad-lab $((3*H)) '@codex fix M1')$(cm 82 "$BOT" $((2*H)) '<!-- codex-review-receipt:v1 --> done' | sed 's/,$//')]"
put "repos/o/u/issues?state=all&per_page=100&since=$(t $((7*D)))" <<< "[$(iss 5 ',"pull_request":{}')$(iss 6 ',"pull_request":{}')$(iss 7 ',"pull_request":{}')$(iss 8 ',"pull_request":{}' | sed 's/,$//')]"
run o/u
check "review branch: no branch-idle (v0.8.16)"          '! has "feat/900-designgranskning" && ! has "feat/902-review"'
check "review branch: board row, Operatör"               'grep -qF "| u | feat/900-designgranskning | review only, delete when read | Operatör |" "$T/board.md" && grep -qF "| u | feat/902-review | review only, delete when read | Operatör |" "$T/board.md"'
check "Hinder: inga → branch-idle as before"             'has "branch-idle	feat/901-own-work" && ! grep -qF "feat/901-own-work | review only" "$T/board.md"'
check "review branch: no extra API call"                 '[ "$(grep -c "^repos/o/u/commits/" "$FIX/calls")" = 3 ]'
check "one receipt answers review + security review, a retry its own (#927)" '! has "#5:"'
check "a review after the last receipt stays open"       'has "codex-retry	#6: 1 @codex"'
check "tasks still one answer each"                      'has "codex-task	#7: 1 @codex"'
check "a receipt with no review open answers a task"     '! has "#8:"'
check "v0.8.16: no blind"                                '! has "	blind	"'

# ---- v0.8.21: poller-down, a Codex CLI order no host claimed (story Y)
prepo() { # prepo NAME ISSUES-JSON: a repo with nothing else to say
  put "repos/o/$1" <<< '{"default_branch":"main"}'
  put "repos/o/$1/issues?state=all&per_page=100&since=$(t $((7*D)))" <<< "$2"
}
pc() { put "repos/o/$1/issues/$2/comments?per_page=100"; }
ORDER='codex-cli: build\nRepo: o/x\nBranch: feat/033-x'
prepo p1 "[$(iss 1 '' | sed 's/,$//')]"
pc p1 1 <<< "[$(cm 11 conwad-lab 1800 "$ORDER" | sed 's/,$//')]"
run o/p1
check "poller-down: unclaimed after 20 min (Y)"          'has "^o/p1	poller-down	order #1: not claimed after 30 min	$(t 1800)	https://github.com/o/r/issues/1#issuecomment-11$" && [ "$(cat "$T/rc")" = 1 ]'
prepo p2 "[$(iss 1 '' | sed 's/,$//')]"
pc p2 1 <<< "[$(cm 11 conwad-lab $((2*H)) "$ORDER")$(cm 12 conwad-lab $((2*H-60)) 'codex-cli: started 20261123T1200Z-1 on mbp for 11' | sed 's/,$//')]"
run o/p2
check "poller-down: claimed order is quiet (Y)"          '! has "poller-down" && [ "$(cat "$T/rc")" = 0 ]'
prepo p3 "[$(iss 1 '' | sed 's/,$//')]"
pc p3 1 <<< "[$(cm 11 conwad-lab 600 "$ORDER" | sed 's/,$//')]"
run o/p3
check "poller-down: 10 min is within the wait (Y)"       '! has "poller-down"'
run --poller-after 5 o/p3
check "poller-down: --poller-after sets the wait (Y)"    'has "^o/p3	poller-down	order #1: not claimed after 10 min"'
prepo p4 "[$(iss 2 ',"state":"closed"')$(iss 3 ',"state":"closed","pull_request":{}' | sed 's/,$//')]"
pc p4 2 <<< "[$(cm 21 conwad-lab $((40*60)) "$ORDER")$(cm 22 conwad-lab $((23*60)) '@codex build .team/plans/033-x.md' | sed 's/,$//')]"
run o/p4
check "poller-down: closed issue, label gone (Y)"        'has "^o/p4	poller-down	order #2: not claimed after 40 min"'
check "poller-down: closed issue is not a codex request" '! has "codex-task"'
check "poller-down: closed PRs are not read (Y)"         '! grep -q "issues/3/comments" "$FIX/calls"'
prepo p5 "[$(iss 1 '')$(iss 2 '')$(iss 3 ',"state":"closed"' | sed 's/,$//')]"
pc p5 1 <<< "[$(cm 11 conwad-lab $((3*H)) "$ORDER" | sed 's/,$//')]"
pc p5 2 <<< "[$(cm 21 conwad-lab $((2*H)) "$ORDER" | sed 's/,$//')]"
pc p5 3 <<< "[$(cm 31 conwad-lab 1800 'codex-cli: started 20261123T1330Z-2 on mbp for 99' | sed 's/,$//')]"
run o/p5
check "poller-down: one later claim clears both (Y)"     '! has "poller-down"'
prepo p6 "[$(iss 1 '' | sed 's/,$//')]"
pc p6 1 <<< "[$(cm 11 conwad-lab $((2*H)) "$ORDER")$(cm 12 conwad-lab $((H)) 'codex-cli: blocked\nHinder: the plan needs a design choice' | sed 's/,$//')]"
run o/p6
check "poller-down: blocked counts as a claim (Y)"       '! has "poller-down"'
prepo p7 "[$(iss 1 '')$(iss 2 '')$(iss 4 '' | sed 's/,$//')]"
pc p7 1 <<< "[$(cm 11 conwad-lab $((3*H)) "$ORDER")$(cm 12 mallory $((2*H)) 'codex-cli: started x on y for 11' | sed 's/,$//')]"
pc p7 2 <<< "[$(cm 21 conwad-lab $((2*H)) "$ORDER" | sed 's/,$//')]"
pc p7 4 <<< "[$(cm 41 conwad-lab $((8*D)) "$ORDER")$(cm 42 conwad-lab $((H)) 'codex-cli: build please' | sed 's/,$//')]"
run o/p7
check "poller-down: one stall per repo, newest order, earlier named" '[ "$(grep -c "poller-down" "$T/out")" = 1 ] && has "^o/p7	poller-down	order #2: not claimed after 2 h (also #1)	$(t $((2*H)))"'
check "poller-down: a stranger claim, an order older than 7 d and a non-exact first line count for nothing" '! has "#4"'
prepo p8 "[$(iss 1 '')$(iss 2 '' | sed 's/,$//')]"
pc p8 1 <<< "[$(cm 11 builder $((2*H)) "$ORDER")$(cm 12 macbot $((2*H-60)) 'codex-cli: started r on mbp for 11')$(cm 13 macbot $((H)) 'codex-cli: done' | sed 's/,$//')]"
pc p8 2 <<< "[$(cm 21 builder $((H)) "$ORDER")$(cm 22 o $((H-60)) 'codex-cli: started r on mbp for 21' | sed 's/,$//')]"
AGENT_ACCOUNT=MacBot run o/p8
check "poller-down: claims by the agent account or the repo owner count (r1 Codex P2)" '! has "poller-down"'
prepo p9 "[$(iss 1 '' | sed 's/,$//')]"
pc p9 1 <<< "[$(cm 11 conwad-lab 1800 "$ORDER")$(cm 12 conwad-lab 1800 'codex-cli: started r on mbp for 11' | sed 's/,$//')]"
run o/p9
check "poller-down: a claim in the same second counts, by comment id (r1 Codex P2)" '! has "poller-down"'
check "v0.8.21: no blind"                                '! has "	blind	"'

echo "1..$n"
exit $fail
