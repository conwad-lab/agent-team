#!/usr/bin/env bash
# tests for bin/models with fake codex, agy, claude and gh on PATH (no real tool, network or GitHub call).
# Run: bash tests/models.test.sh
set -u
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; n=0
ok()  { n=$((n+1)); echo "ok $n - $1"; }
nok() { n=$((n+1)); fail=1; echo "not ok $n - $1"; }
check() { if eval "$2"; then ok "$1"; else nok "$1"; fi; }

ST="$T/state"; mkdir -p "$T/bin" "$ST"
export ST
P="$T/bin:/usr/bin:/bin"

# fake codex: `--version`, `debug models` prints the catalogue in $ST/codex.json; $ST/codex_hang makes it hang
cat > "$T/bin/codex" <<'C'
#!/usr/bin/env bash
case "$1" in
  --version) echo "codex-cli 0.171.0" ;;
  debug)
    # hang: a child that ignores TERM keeps stdout open after the wrapper itself dies (Codex M1 on #39)
    [ -f "$ST/codex_hang" ] && { ( trap '' TERM; sleep 30 ) & sleep 30; }
    # leave: the wrapper answers and exits, but leaves that child behind holding stdout
    [ -f "$ST/codex_leave" ] && ( trap '' TERM; sleep 30 ) &
    cat "$ST/codex.json" ;;
  *) exit 1 ;;
esac
C
# fake agy: `models` prints $ST/agy.txt
cat > "$T/bin/agy" <<'A'
#!/usr/bin/env bash
case "$1" in --version) echo "agy 1.6.2" ;; models) cat "$ST/agy.txt" ;; *) exit 1 ;; esac
A
cat > "$T/bin/claude" <<'L'
#!/usr/bin/env bash
case "$1" in --version) echo "2.1.330 (Claude Code)" ;; *) exit 1 ;; esac
L
# fake gh api: issues and comments in files, every call logged
cat > "$T/bin/gh" <<'G'
#!/usr/bin/env bash
set -u
[ "$1" = api ] || exit 1; shift
url=""; method=GET; jqf=""; body=""; title=""
while [ $# -gt 0 ]; do
  case "$1" in
    -X) method="$2"; shift 2 ;;
    -f) case "$2" in body=*) body="${2#body=}" ;; title=*) title="${2#title=}" ;; esac; shift 2 ;;
    --jq) jqf="$2"; shift 2 ;;
    --paginate) echo "paginate" >> "$ST/paginated"; shift ;;
    *) url="$1"; shift ;;
  esac
done
echo "$method $url" >> "$ST/calls"
[ -n "${GH_TOKEN:-}" ] || echo "NO-TOKEN" >> "$ST/calls"
out() { if [ -n "$jqf" ]; then jq -r "$jqf"; else cat; fi; }
case "$method $url" in
  "GET user") [ -f "$ST/gh_hang" ] && sleep 30; echo '{"login":"poller"}' | out ;;
  "GET repos/o/r/issues?"*) cat "$ST/issues.json" | out ;;
  "POST repos/o/r/issues") jq -n --arg t "$title" '[{number: 9, title: $t}]' > "$ST/issues.json"; echo '[]' > "$ST/comments.json"; echo '{"number":9}' | out ;;
  "GET repos/o/r/issues/9/comments"*) cat "$ST/comments.json" | out ;;
  "POST repos/o/r/issues/9/comments") jq --arg b "$body" '. + [{id: 501, user: {login: "poller"}, body: $b}]' "$ST/comments.json" > "$ST/c" && mv "$ST/c" "$ST/comments.json" ;;
  "PATCH repos/o/r/issues/comments/501") jq --arg b "$body" 'map(if .id == 501 then .body = $b else . end)' "$ST/comments.json" > "$ST/c" && mv "$ST/c" "$ST/comments.json" ;;
  *) echo "fake gh: unhandled $method $url" >&2; exit 1 ;;
esac
G
chmod +x "$T/bin/"*

catalogue() { # catalogue "slug:visibility" ...
  local a; for a in "$@"; do printf '{"slug":"%s","visibility":"%s"}\n' "${a%%:*}" "${a#*:}"; done | jq -s '{models: .}' > "$ST/codex.json"
}
cat > "$T/conf.env" <<'E'
HOST=testmac
MODELS="astra=gpt-6-astra sol=gpt-6-sol"
KEYCHAIN_ITEM=agent-team-codex-cli
E
cat > "$T/map.md" <<'M'
# Model map (team/MODELS.md)
- light: claude-sonnet-5-5 — since 2026-11-16 — Conny
- standard: `claude-opus-5-5` — since 2026-11-16 — Conny
- strongest: claude-fable-5-2 — since 2026-11-16 — Conny
- reserve: Gemini 4 Argon — since 2026-11-22 — Conny
M
run() { PATH="$P" CODEX_CLI_ENV="$T/conf.env" MODELS_LIMIT="${LIM:-60}" bash "$SKILL/bin/models" "$@" > "$T/out" 2> "$T/err"; rc=$?; }
newers() { grep -c '^newer ' "$T/out"; }

# 1 a newer Astra gives one newer line; Sol equal gives none
catalogue gpt-6.2-astra:list gpt-6-astra:list gpt-6-sol:list
printf 'Gemini 4 Argon\n' > "$ST/agy.txt"
run
check "rc 0" '[ "$rc" = 0 ]'
check "header and versions" 'grep -q "^models testmac " $T/out && grep -qx "codex version 0.171.0" $T/out && grep -qx "agy version 1.6.2" $T/out && grep -qx "claude version 2.1.330" $T/out'
check "codex offers listed one per line" 'grep -qx "codex offers gpt-6.2-astra" $T/out && grep -qx "codex offers gpt-6-sol" $T/out'
check "in-use from the poller config" 'grep -qx "in-use astra gpt-6-astra" $T/out && grep -qx "in-use sol gpt-6-sol" $T/out'
check "newer Astra: exactly one newer line" '[ "$(newers)" = 1 ] && grep -qx "newer codex astra gpt-6-astra → gpt-6.2-astra" $T/out'
check "claude has no listing: offers unknown" 'grep -qx "claude offers unknown" $T/out'

# 2 all equal: no newer line
catalogue gpt-6-astra:list gpt-6-sol:list
run
check "equal ids: no newer line" '[ "$(newers)" = 0 ]'

# 3 hidden models and other lines (a -mini, another family) never count; the highest of several wins
catalogue gpt-6-astra:list gpt-6-sol:list gpt-7-astra:hide gpt-6.2-astra-mini:list gpt-6.3-luna:list gpt-6.1-sol:list gpt-6.2-sol:list
run
check "hidden, -mini and other families ignored; highest Sol wins" '[ "$(newers)" = 1 ] && grep -qx "newer codex sol gpt-6-sol → gpt-6.2-sol" $T/out'

# 4 agy: a map's Gemini id, display names with spaces, bullets and notes in the listing
catalogue gpt-6-astra:list gpt-6-sol:list
printf 'Available models:\n  * Gemini 4 Argon (default)\n  - Gemini 4.1 Argon   new\n  - Gemini 4 Carbon\n  - Claude 4.6 Sonnet\n' > "$ST/agy.txt"
run --map "$T/map.md"
check "map in-use lines read (backticks stripped)" 'grep -qx "in-use standard claude-opus-5-5" $T/out && grep -qx "in-use reserve Gemini 4 Argon" $T/out'
check "agy listing parsed" 'grep -qx "agy offers Gemini 4.1 Argon" $T/out && grep -qx "agy offers Gemini 4 Argon" $T/out && ! grep -q "Available" $T/out'
check "newer Argon from agy, Carbon not an Argon" '[ "$(newers)" = 1 ] && grep -qx "newer agy reserve Gemini 4 Argon → Gemini 4.1 Argon" $T/out'

# 5 a declined id is not offered again; a still newer one is
printf -- '- declined: Gemini 4.1 Argon — 2026-11-24 — Conny: Vänta\n' >> "$T/map.md"
run --map "$T/map.md"
check "declined id: no newer line" '[ "$(newers)" = 0 ] && ! grep -q "^declined" $T/out'
printf '  - Gemini 4.1 Argon\n  - Gemini 4.2 Argon\n' > "$ST/agy.txt"
run --map "$T/map.md"
check "an id newer than the declined one still counts" 'grep -qx "newer agy reserve Gemini 4 Argon → Gemini 4.2 Argon" $T/out'

# 6 report mode: the host's comment plus the Coordinator's own list, compared with the map; Claude ids
catalogue gpt-6.2-astra:list gpt-6-astra:list gpt-6-sol:list
printf '' > "$ST/agy.txt"
run; cp "$T/out" "$T/host.txt"
check "agy with an empty listing: offers unknown" 'grep -qx "agy offers unknown" $T/host.txt'
{ echo '<!-- agent-team-models -->'; echo '```'; cat "$T/host.txt"; echo '```'; } > "$T/comment.md"
printf 'coordinator offers claude-sonnet-5-5\ncoordinator offers claude-opus-5-6\ncoordinator offers claude-fable-5-2\n' > "$T/coord.txt"
PATH="/usr/bin:/bin" CODEX_CLI_ENV=/nonexistent bash "$SKILL/bin/models" --report "$T/comment.md" --report "$T/coord.txt" --map "$T/map.md" > "$T/out" 2>"$T/err"; rc=$?
check "report: rc 0 without the tools on PATH" '[ "$rc" = 0 ]'
check "report: keeps the host header and in-use lines" 'grep -q "^models testmac " $T/out && grep -qx "in-use astra gpt-6-astra" $T/out'
check "report: newer Astra and newer Opus, nothing else" '[ "$(newers)" = 2 ] && grep -qx "newer codex astra gpt-6-astra → gpt-6.2-astra" $T/out && grep -qx "newer coordinator standard claude-opus-5-5 → claude-opus-5-6" $T/out'

# 6b the map wins over the poller config for a role; lines under ## History are not in use
{ cat "$T/map.md"; printf -- '- astra: gpt-6.2-astra — since 2026-11-24 — Conny on card\n\n## History\n- astra: gpt-5.6-astra — since 2026-10-01\n- haiku: claude-haiku-4-5 — since 2026-10-01\n'; } > "$T/map2.md"
PATH="/usr/bin:/bin" CODEX_CLI_ENV=/nonexistent bash "$SKILL/bin/models" --report "$T/comment.md" --report "$T/coord.txt" --map "$T/map2.md" > "$T/out" 2>"$T/err"
check "map wins per role: one in-use astra, the map's, and no Astra card" '[ "$(grep -c "^in-use astra " $T/out)" = 1 ] && grep -qx "in-use astra gpt-6.2-astra" $T/out && ! grep -q "^newer codex astra" $T/out'
check "History lines are not in use" '! grep -q "in-use haiku" $T/out && ! grep -q "gpt-5.6-astra" $T/out'

# 6c with two maps the last one wins for a role, even when it repeats the config's id (Codex M5 on #39)
printf -- '- astra: gpt-6.2-astra — since 2026-11-24\n' > "$T/mapA.md"; printf -- '- astra: gpt-6-astra — since 2026-11-25\n' > "$T/mapB.md"
PATH="/usr/bin:/bin" CODEX_CLI_ENV=/nonexistent bash "$SKILL/bin/models" --report "$T/comment.md" --map "$T/mapA.md" --map "$T/mapB.md" > "$T/out" 2>"$T/err"
check "last map wins before duplicates are dropped" 'grep -qx "in-use astra gpt-6-astra" $T/out && grep -qx "newer codex astra gpt-6-astra → gpt-6.2-astra" $T/out'

# 7 a hanging tool is stopped and says unknown; stdin is closed
catalogue gpt-6-astra:list; touch "$ST/codex_hang"
s=$(date +%s); LIM=2 run; e=$(( $(date +%s) - s ))
rm -f "$ST/codex_hang"
check "hanging codex stopped within the limit, offers unknown" '[ "$e" -lt 10 ] && grep -qx "codex offers unknown" $T/out'
touch "$ST/codex_leave"; catalogue gpt-6-astra:list
s=$(date +%s); LIM=20 run; e=$(( $(date +%s) - s ))
rm -f "$ST/codex_leave"
check "a child left behind holding stdout is stopped when the wrapper exits" '[ "$e" -lt 10 ] && grep -qx "codex offers gpt-6-astra" $T/out'

# 8 a tool not installed
rm "$T/bin/agy"; run
check "missing tool: version not-installed" 'grep -qx "agy version not-installed" $T/out && [ "$rc" = 0 ]'

# 9 --post: creates the issue once, posts one comment, then edits it in place
catalogue gpt-6.2-astra:list gpt-6-astra:list gpt-6-sol:list
echo '[]' > "$ST/issues.json"; : > "$ST/calls"
GH_TOKEN=fake run --post o/r
check "post: issue created with the host's title" 'jq -e ".[0].title == \"agent-team: models on testmac\"" $ST/issues.json >/dev/null'
check "post: one comment with the marker and the newer line" '[ "$(jq length $ST/comments.json)" = 1 ] && jq -r ".[0].body" $ST/comments.json | grep -q "^<!-- agent-team-models -->" && jq -r ".[0].body" $ST/comments.json | grep -q "newer codex astra"'
catalogue gpt-6.2-astra:list gpt-6-astra:list gpt-6-sol:list gpt-6.2-sol:list
GH_TOKEN=fake run --post o/r
check "post again: same comment edited, no new issue or comment" '[ "$(jq length $ST/comments.json)" = 1 ] && grep -q "^PATCH repos/o/r/issues/comments/501" $ST/calls && [ "$(grep -c "^POST repos/o/r/issues$" $ST/calls)" = 1 ] && jq -r ".[0].body" $ST/comments.json | grep -q "newer codex sol"'
check "post: issue and comment lookups paginate (Codex S1 on ab92e3c)" '[ "$(grep -c paginate $ST/paginated)" -ge 4 ]'
check "post: every gh call had the token" '! grep -q NO-TOKEN $ST/calls'

# 9b a hanging gh is stopped too, so the nightly job cannot hold its lock (Codex M4 on #39)
touch "$ST/gh_hang"; s=$(date +%s); GH_TOKEN=fake LIM=2 run --post o/r; e=$(( $(date +%s) - s )); rm -f "$ST/gh_hang"
check "post: hanging gh stopped within the limit, exit 0" '[ "$e" -lt 15 ] && [ "$rc" = 0 ]'

# 10 usage
PATH="$P" bash "$SKILL/bin/models" --bogus > /dev/null 2>&1; rc=$?
check "unknown flag: exit 2" '[ "$rc" = 2 ]'

echo
if [ "$fail" = 0 ]; then echo "all $n passed"; else echo "FAILED"; exit 1; fi
