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
# 004: M1 disputed but then fixed and verified; S1 still open in round 2, fixed in response round 2
cat > "$R/004-order.md" <<'R5'
---
verdict: approve
---
## Must fix
- M1 `e.py:2` — wrong default.
## Should fix
- S1 `e.py:8` — log the retry.
## Round 2
- M1 — fixed, verified by test.
- S1 — still open, the retry is not logged.
R5
cat > "$R/004-order.response.md" <<'R6'
## Round 1
- M1: disputed — the default is documented.
- S1: fixed in 111aaa — logged.
## Round 2
- S1: fixed in 222bbb — logged on the retry path too.
R6
# 005: numbered first round; the template's empty second-reviewer section is not a finding
cat > "$R/005-numbered.md" <<'R7'
---
verdict: approve
---
## Round 1
### Must fix
- M1 `f.rs:4` — overflow.
## Codex findings
<!-- Cloud mode: every Codex finding, one line each -->
-
## Round 2
- M1 — still open, still overflows.
R7
cat > "$R/005-numbered.response.md" <<'R8'
## Round 1
- M1: disputed — cannot overflow.
## Round 2
- M1: fixed in 333ccc — checked_add.
R8
echo x > "$R/.gitkeep"
git -C "$T/po" add -A && git -C "$T/po" -c user.name=t -c user.email=t@t commit -qm reviews && git -C "$T/po" push -q origin HEAD:main 2>/dev/null
git -C "$T/po" remote set-head origin main >/dev/null 2>&1 || git -C "$T/po" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

J="$(python3 "$SKILL/bin/hits" "$T/po" --json)" || nok "hits runs"
get() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)" <<<"$J"; }
outcome() { get "[f['outcome'] for s in d['stories'] if s['story']=='$1' for f in s['findings'] if f['id']=='$2'][0]"; }

[ "$(get 'len(d["stories"])')" = 5 ] && ok "five stories, .gitkeep skipped" || nok "five stories (got $(get 'len(d["stories"])'))"
[ "$(outcome 001-two-rounds M1)" = verified ] && ok "fixed + closed = verified" || nok "M1 verified (got $(outcome 001-two-rounds M1))"
[ "$(outcome 001-two-rounds S1)" = dropped ] && ok "dispute accepted = dropped" || nok "S1 dropped (got $(outcome 001-two-rounds S1))"
[ "$(outcome 001-two-rounds S2)" = claimed ] && ok "**S2:** parsed; Coder's word only = claimed" || nok "S2 claimed (got $(outcome 001-two-rounds S2))"
[ "$(outcome 001-two-rounds N1)" = open ] && ok "unanswered numbered nit = open" || nok "N1 open"
[ "$(outcome 002-one-round S1)" = open ] && ok "approved with an unanswered Should fix = open" || nok "002 S1 open"
[ "$(outcome 003-list M2)" = verified ] && ok "\"M1, M2 — closed\" closes both" || nok "003 M2 verified (got $(outcome 003-list M2))"
[ "$(get 'd["stories"][0]["unnumbered_nits"]')" = 1 ] && ok "Nit: lines counted apart" || nok "unnumbered nits"
[ "$(get 'd["second_reviewer"]')" = "{'sections': 3, 'with_findings': 1}" ] && ok "empty second reviewer told apart from one with findings" || nok "second reviewer (got $(get 'd["second_reviewer"]'))"
[ "$(outcome 004-order M1)" = verified ] && ok "disputed, then \"fixed, verified\" = verified" || nok "004 M1 verified (got $(outcome 004-order M1))"
[ "$(outcome 004-order S1)" = claimed ] && ok "a fix answered after \"still open\" = claimed" || nok "004 S1 claimed (got $(outcome 004-order S1))"
[ "$(outcome 005-numbered M1)" = claimed ] && ok "\"## Round 1\" first review: later fix answer = claimed" || nok "005 M1 claimed (got $(outcome 005-numbered M1))"
out="$(python3 "$SKILL/bin/hits" "$T/po")"
grep -q "002-one-round S1 \[open\]" <<<"$out" && ok "report lists the finding that was not applied" || nok "report lists 002 S1"
grep -q "001-two-rounds S1" <<<"$out" && nok "dropped finding not listed" || ok "dropped finding not listed"
python3 "$SKILL/bin/hits" "$T/nope" 2>/dev/null && nok "non-clone refused" || ok "non-clone refused"

exit $fail
