#!/usr/bin/env bash
# tests for bin/hits. Run: bash tests/hits.test.sh
set -u
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; n=0
ok()  { n=$((n+1)); echo "ok $n - $1"; }
nok() { n=$((n+1)); fail=1; echo "not ok $n - $1"; }

git init -q --bare "$T/origin.git"
git clone -q "$T/origin.git" "$T/po" 2>/dev/null
R="$T/po/.team/reviews"; mkdir -p "$R"

# 001: two rounds; M1 fixed and closed, S1 disputed and the reason accepted, S2 claimed fixed only
cat > "$R/001-two-rounds.md" <<'R1'
---
verdict: approve
---
## Must fix
- **M1** `a.sh:3` — breaks on spaces.
## Should fix
- **S1** `a.sh:9` — rename the flag.
- **S2:** `b.sh:1` — add a test.
## Nits
- Nit: typo.
- N1 `a.sh:1` — header comment.
## Round 2 — 2026-10-01
- M1 — fixed. Quoted now.
- S1 — dispute accepted, the flag name is the upstream one.
R1
cat > "$R/001-two-rounds.response.md" <<'R2'
- M1: fixed in abc123 — quoted.
- S1: disputed — upstream name.
- S2: fixed in abc123 — test added.
R2
# 002: approved in one round with a Should fix nobody answered; second reviewer gave nothing
cat > "$R/002-one-round.md" <<'R3'
---
verdict: approve
---
## Must fix
None.
## Should fix
- S1 `c.ts:4` — the error path is untested.
## Second reviewer
`nvidia-review.sh 7` ran out of time; the output file stayed empty.
R3
# 003: a list line closes two at once; plain "accepted" means the fix was accepted
cat > "$R/003-list.md" <<'R4'
---
verdict: approve
---
## Must fix
- M1 `d.go:1` — race.
- M2 `d.go:9` — leak.
## Re-review
- M1, M2 — closed in round 2.
## Codex findings
- valid — fixed: missing nil check.
R4
echo x > "$R/.gitkeep"
git -C "$T/po" add -A && git -C "$T/po" -c user.name=t -c user.email=t@t commit -qm reviews && git -C "$T/po" push -q origin HEAD:main 2>/dev/null
git -C "$T/po" remote set-head origin main >/dev/null 2>&1 || git -C "$T/po" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

J="$(python3 "$SKILL/bin/hits" "$T/po" --json)" || nok "hits runs"
get() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)" <<<"$J"; }
outcome() { get "[f['outcome'] for s in d['stories'] if s['story']=='$1' for f in s['findings'] if f['id']=='$2'][0]"; }

[ "$(get 'len(d["stories"])')" = 3 ] && ok "three stories, .gitkeep skipped" || nok "three stories (got $(get 'len(d["stories"])'))"
[ "$(outcome 001-two-rounds M1)" = verified ] && ok "fixed + closed = verified" || nok "M1 verified (got $(outcome 001-two-rounds M1))"
[ "$(outcome 001-two-rounds S1)" = dropped ] && ok "dispute accepted = dropped" || nok "S1 dropped (got $(outcome 001-two-rounds S1))"
[ "$(outcome 001-two-rounds S2)" = claimed ] && ok "**S2:** parsed; Coder's word only = claimed" || nok "S2 claimed (got $(outcome 001-two-rounds S2))"
[ "$(outcome 001-two-rounds N1)" = open ] && ok "unanswered numbered nit = open" || nok "N1 open"
[ "$(outcome 002-one-round S1)" = open ] && ok "approved with an unanswered Should fix = open" || nok "002 S1 open"
[ "$(outcome 003-list M2)" = verified ] && ok "\"M1, M2 — closed\" closes both" || nok "003 M2 verified (got $(outcome 003-list M2))"
[ "$(get 'd["stories"][0]["unnumbered_nits"]')" = 1 ] && ok "Nit: lines counted apart" || nok "unnumbered nits"
[ "$(get 'd["second_reviewer"]')" = "{'sections': 2, 'with_findings': 1}" ] && ok "empty second reviewer told apart from one with findings" || nok "second reviewer (got $(get 'd["second_reviewer"]'))"
out="$(python3 "$SKILL/bin/hits" "$T/po")"
grep -q "002-one-round S1 \[open\]" <<<"$out" && ok "report lists the finding that was not applied" || nok "report lists 002 S1"
grep -q "001-two-rounds S1" <<<"$out" && nok "dropped finding not listed" || ok "dropped finding not listed"
python3 "$SKILL/bin/hits" "$T/nope" 2>/dev/null && nok "non-clone refused" || ok "non-clone refused"

exit $fail
