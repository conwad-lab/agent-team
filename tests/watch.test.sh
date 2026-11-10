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
{ for s in 001-ready 002-planned 003-split 004-superseded _005-parked 006-building 007-draft 008-judging 009-approved 010-changes 011-escalated 012-done 013-done-old; do
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
  pr 14 "014: no story"   open   true  -           $((1*H))  feat/014-x
  pr 20 "board: tidy"     open   false -           $((1*H))  board/2026-11-10-tidy
  printf '{"number":1,"title":"old","state":"closed","draft":false,"merged_at":null,"updated_at":"%s","head":{"ref":"x","sha":"s"},"html_url":"u"}]' "$(t $((20*D)))"
} | put "repos/o/r/pulls?state=all&per_page=100"
put "repos/o/r/branches?per_page=100" <<< '[{"name":"main","commit":{"sha":"m"}},{"name":"feat/006-building","commit":{"sha":"b6"}},{"name":"feat/008-judging","commit":{"sha":"sha8"}},{"name":"feat/099-fresh","commit":{"sha":"b99"}}]'
put repos/o/r/commits/b6  <<< "{\"commit\":{\"committer\":{\"date\":\"$(t $((2*D)))\"}}}"
put repos/o/r/commits/b99 <<< "{\"commit\":{\"committer\":{\"date\":\"$(t $((2*H)))\"}}}"
put "repos/o/r/contents/.team/reviews?ref=sha8" <<< '[{"name":"008-x.response.md"}]'
for p in 009:approve 010:request-changes 011:escalate; do
  id="${p%%:*}"; v="${p#*:}"; s="sha$((10#$id))"
  put "repos/o/r/contents/.team/reviews?ref=$s" <<< "[{\"name\":\"$id-x.md\"},{\"name\":\"$id-x.response.md\"}]"
  put "repos/o/r/contents/.team/reviews/$id-x.md?ref=$s" <<< "{\"content\":\"$(b64 "---"$'\n'"verdict: $v"$'\n'"---"$'\n')\"}"
done

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
put "repos/o/r/issues?state=open&per_page=100&since=$(t $((7*D)))" <<< "[$(iss 7 ',"pull_request":{}')$(iss 8 ',"pull_request":{}')$(iss 9 ',"pull_request":{}')$(iss 10 ',"pull_request":{}')$(iss 40 ',"pull_request":{}')$(iss 41 ',"pull_request":{}')$(iss 42 '')$(iss 30 '' | sed 's/,$//')]"
# 040: two angle requests in one batch, one review answers one of them → one left, not yet retried
put "repos/o/r/issues/40/comments?per_page=100" <<< "[$(cm 401 conwad-lab $((3*H)) '@codex review — security')$(cm 402 conwad-lab $((3*H-120)) '@codex review — failure paths' | sed 's/,$//')]"
put "repos/o/r/pulls/40/reviews?per_page=100" <<< "[{\"id\":1,\"user\":{\"login\":\"$BOT\"},\"submitted_at\":\"$(t $((5*H/2)))\"}]"
# 041: an earlier request answered by 👍, a new one unanswered → retry, not silent
put "repos/o/r/issues/41/comments?per_page=100" <<< "[$(cm 411 conwad-lab $((5*H)) '@codex review')$(cm 412 conwad-lab $((2*H)) '@codex review' | sed 's/,$//')]"
put "repos/o/r/issues/comments/411/reactions" <<< "[{\"user\":{\"login\":\"$BOT\"},\"content\":\"+1\"}]"
# 042: a fix task unanswered → codex-task, never an automatic review retry
put "repos/o/r/issues/42/comments?per_page=100" <<< "[$(cm 421 conwad-lab $((2*H)) '@codex fix M1: quote the path' | sed 's/,$//')]"
put "repos/o/r/actions/runs?status=queued&per_page=100" <<< "{\"workflow_runs\":[{\"id\":100,\"name\":\"ci\",\"created_at\":\"$(t 2700)\",\"html_url\":\"r100\"},{\"id\":101,\"name\":\"ci\",\"created_at\":\"$(t 600)\",\"html_url\":\"r101\"}]}"
put "repos/o/r/actions/runs?status=failure&created=%3E%3D$(t $D)&per_page=100" <<< "{\"workflow_runs\":[{\"id\":200,\"name\":\"ci\",\"created_at\":\"$(t $H)\",\"html_url\":\"r200\"},{\"id\":201,\"name\":\"e2e\",\"created_at\":\"$(t $H)\",\"html_url\":\"r201\"}]}"
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
check "not-started run flagged, started one not" 'has "not-started" && has "r200" && ! has "r201"'
check "codex-retry: asked once, 2 h"          'has "codex-retry	#8:"'
check "codex-silent: asked twice"             'has "codex-silent	#7:"'
check "Codex comment answers"                 '! has "#9: @codex"'
check "Codex 👍 answers"                      '! has "#10: @codex"'
check "under an hour is quiet"                '! has "#30:"'
check "one answer answers one request (M2)"   'has "codex-retry	#40: 1 @codex"'
check "earlier 👍 not counted (M3)"            'has "codex-retry	#41: 1 @codex"'
check "fix task is codex-task (M4)"           'has "codex-task	#42:"'
check "no blind"                              '! has "	blind	"'

check "board: ready"             'row 001-ready | grep -q "| ready | Coordinator |"'
check "board: planned"           'row 002-planned | grep -q "| planned | Coordinator |"'
check "board: needs-split"       'row 003-split | grep -q "| needs-split | Coordinator |"'
check "board: superseded absent" '! row 004-superseded'
check "board: parked absent"     '! grep -q "005-parked" "$T/board.md"'
check "board: branch → building, age" 'row 006-building | grep -q "| building | Builder | 2 d ago |"'
check "board: draft → building"  'row 007-draft | grep -q "| building | Builder |"'
check "board: judging"           'row 008-judging | grep -q "| judging | Judge |"'
check "board: approved, card open → human" 'row 009-approved | grep -q "| approved | human (card open 20 h) |"'
check "board: Vänta → human"     'row 010-changes | grep -q "| changes-requested | human (Vänta 19 h) |"'
check "board: escalated"         'row 011-escalated | grep -q "| escalated | human |"'
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

echo "1..$n"
exit $fail
