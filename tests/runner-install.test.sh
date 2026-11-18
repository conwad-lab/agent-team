#!/usr/bin/env bash
# tests for bin/runner-install with a fake gh (repo, runner and variable state in files), a fake orb that runs each
# machine's `bash -s` script locally in its own HOME with fake sudo, curl and tar, and a fake config.sh/svc.sh that
# the fake tar "unpacks". No real machine, network or GitHub call.
# Run: bash tests/runner-install.test.sh
set -u
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; n=0
ok()  { n=$((n+1)); echo "ok $n - $1"; }
nok() { n=$((n+1)); fail=1; echo "not ok $n - $1"; }
check() { if eval "$2"; then ok "$1"; else nok "$1"; fi; }

FAKE_TOKEN="ghs_TESTTOKEN123"
ST="$T/state"; M="$T/machines"; OUT="$T/out"
mkdir -p "$T/bin" "$T/mbin" "$T/home" "$ST/secret" "$M" "$OUT"
export T ST M FAKE_TOKEN
printf 'FAKE RUNNER TARBALL\n' > "$ST/tarball"
GOOD_SHA="$(sha256sum "$ST/tarball" | awk '{print $1}')"
echo "$GOOD_SHA" > "$ST/release_sha"

# ---------------------------------------------------------------- fake gh (Mac side)
cat > "$T/bin/gh" <<'G'
#!/usr/bin/env bash
set -u
[ "$1" = api ] || { echo "fake gh: only api" >&2; exit 1; }
shift
url=""; method=GET; jqf=""
while [ $# -gt 0 ]; do
  case "$1" in
    -X|--method) method="$2"; shift 2 ;;
    --jq|-q) jqf="$2"; shift 2 ;;
    *) [ -z "$url" ] && url="$1"; shift ;;
  esac
done
echo "$method $url" >> "$ST/gh_calls"
out() { if [ -n "$jqf" ]; then jq -r "$jqf"; else cat; fi; }
repo="$(printf '%s' "$url" | sed -nE 's#^repos/[^/]+/([^/?]+).*#\1#p')"
rf="$ST/runners_$repo.json"; [ -f "$rf" ] || echo '[]' > "$rf"
case "$method $url" in
  "GET user") echo '{"login":"conwad-lab"}' | out ;;
  "GET repos/actions/runner/releases/latest")
    sha="$(cat "$ST/release_sha")"
    jq -n --arg s "$sha" '{tag_name: "v2.999.0", body: ("## SHA-256 Checksums\n- actions-runner-linux-x64-2.999.0.tar.gz <!-- BEGIN SHA linux-x64 -->" + $s + "<!-- END SHA linux-x64 -->\n- actions-runner-linux-arm64-2.999.0.tar.gz <!-- BEGIN SHA linux-arm64 -->" + $s + "<!-- END SHA linux-arm64 -->\n")}' | out ;;
  "GET repos/"*"/actions/runners?"*) if [ -f "$ST/hook_list_fails" ]; then echo "gh: HTTP 502" >&2; exit 1; fi; jq '{runners: .}' "$rf" | out ;;
  "POST repos/"*"/actions/runners/registration-token")
    [ -z "${GH_DEBUG:-}${DEBUG:-}" ] || echo "* debug: {\"token\":\"$FAKE_TOKEN\"}" >&2
    if [ -f "$ST/hook_no_token" ]; then echo '{"message":"Resource not accessible"}' | out; echo "gh: HTTP 403" >&2; exit 1; fi
    echo "{\"token\":\"$FAKE_TOKEN\"}" | out ;;
  "DELETE repos/"*"/actions/runners/"*)
    if [ -f "$ST/hook_delete_fails" ]; then echo "gh: HTTP 422" >&2; exit 1; fi
    id="${url##*/}"; jq --argjson id "$id" 'map(select(.id != $id))' "$rf" > "$rf.n" && mv "$rf.n" "$rf" ;;
  "GET repos/"*"/actions/variables/RUNS_ON")
    if [ -f "$ST/var_$repo" ]; then jq -n --arg v "$(cat "$ST/var_$repo")" '{name: "RUNS_ON", value: $v}' | out
    else echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi ;;
  "DELETE repos/"*"/actions/variables/RUNS_ON") rm -f "$ST/var_$repo" ;;
  "GET repos/"*)
    if [ -f "$ST/repo_$repo.json" ]; then out < "$ST/repo_$repo.json"; else echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi ;;
  *) echo "fake gh: unhandled $method $url" >&2; exit 1 ;;
esac
G

# ---------------------------------------------------------------- fake orb: a machine is a directory under $M
cat > "$T/bin/orb" <<'O'
#!/usr/bin/env bash
set -u
case "$1" in
  create) for a in "$@"; do name="$a"; done; echo "$*" >> "$ST/orb_calls"; mkdir -p "$M/$name" ;;
  info)   [ -d "$M/$2" ] ;;
  start)  [ -d "$M/$2" ] ;;
  list)   echo "NAME STATE DISTRO VERSION ARCH"; for d in "$M"/*/; do [ -d "$d" ] && echo "$(basename "$d") running ubuntu noble arm64"; done ;;
  delete) for a in "$@"; do name="$a"; done; echo "$*" >> "$ST/orb_calls"
          [ -f "$ST/hook_orb_delete_fails" ] && exit 1
          rm -rf "${M:?}/$name" ;;
  -m)     m="$2"; shift 2
          [ "$*" = "bash -s" ] || { echo "fake orb: expected 'bash -s', got: $*" >&2; exit 1; }
          [ -d "$M/$m" ] || { echo "fake orb: no machine $m" >&2; exit 1; }
          cd "$M/$m" && HOME="$M/$m" PATH="$T/mbin:$PATH" bash -s ;;
  *) echo "fake orb: unhandled $*" >&2; exit 1 ;;
esac
O

cat > "$T/bin/uname" <<'U'
#!/bin/sh
if [ "${1:-}" = -s ]; then echo Darwin; else exec /usr/bin/uname "$@"; fi
U
printf '#!/bin/sh\nexit 0\n' > "$T/bin/sleep"

# ---------------------------------------------------------------- inside the machine
cat > "$T/mbin/sudo" <<'S'
#!/usr/bin/env bash
case "${1:-}" in
  -n) exit 0 ;;
  ./*) exec "$@" ;;
  *) cat >/dev/null 2>&1 || true; echo "sudo $*" >> "$ST/sudo_calls"; exit 0 ;;
esac
S
cat > "$T/mbin/curl" <<'C'
#!/usr/bin/env bash
o=""; prev=""
for a in "$@"; do [ "$prev" = -o ] && o="$a"; prev="$a"; done
echo "$*" >> "$ST/mcurl_calls"
[ -n "$o" ] && cp "$ST/tarball" "$o"
exit 0
C
cat > "$T/mbin/tar" <<'X'
#!/usr/bin/env bash
d=""; prev=""
for a in "$@"; do [ "$prev" = -C ] && d="$a"; prev="$a"; done
mkdir -p "$d/bin"
printf '#!/bin/sh\nexit 0\n' > "$d/bin/installdependencies.sh"
cat > "$d/config.sh" <<'CFG'
#!/usr/bin/env bash
# fake config.sh: its argv (with the token) is logged outside every directory the token test scans
echo "config $*" >> "$ST/secret/config_calls"
url=""; name=""; tok=""; prev=""
for a in "$@"; do
  case "$prev" in --url) url="$a" ;; --name) name="$a" ;; --token) tok="$a" ;; esac
  prev="$a"
done
[ "$tok" = "$FAKE_TOKEN" ] || { echo "Http response code: NotFound from 'POST https://api.github.com/actions/runner-registration' token=$tok"; exit 1; }
repo="${url##*/}"; rf="$ST/runners_$repo.json"; [ -f "$rf" ] || echo '[]' > "$rf"
id=$(( $(jq '[.[].id] | max // 0' "$rf") + 1 ))
jq --arg n "$name" --argjson id "$id" 'map(select(.name != $n)) + [{id: $id, name: $n, status: "offline", busy: false}]' "$rf" > "$rf.n" && mv "$rf.n" "$rf"
echo "$repo $name" > .runner; echo key > .credentials; echo key > .credentials_rsaparams
echo "Runner successfully added"
CFG
cat > "$d/svc.sh" <<'SVC'
#!/usr/bin/env bash
echo "$(basename "$HOME") svc $*" >> "$ST/svc_calls"
case "$1" in
  install) echo "actions.runner.fake.service" > .service ;;
  uninstall) rm -f .service ;;
  start)
    [ -f "$ST/hook_stay_offline" ] && exit 0
    read -r repo name < .runner; rf="$ST/runners_$repo.json"
    jq --arg n "$name" 'map(if .name == $n then .status = "online" else . end)' "$rf" > "$rf.n" && mv "$rf.n" "$rf" ;;
esac
exit 0
SVC
chmod +x "$d/config.sh" "$d/svc.sh" "$d/bin/installdependencies.sh"
X
cat > "$T/mbin/uname" <<'U'
#!/bin/sh
if [ "${1:-}" = -m ]; then echo aarch64; else exec /usr/bin/uname "$@"; fi
U
cat > "$T/mbin/mac" <<'A'
#!/bin/sh
# a machine that is not isolated can run commands on the Mac
[ -f "$ST/hook_not_isolated" ]
A
printf '#!/bin/sh\necho arm64\n' > "$T/mbin/dpkg"
printf '#!/bin/sh\necho active\n' > "$T/mbin/systemctl"
chmod +x "$T/bin/"* "$T/mbin/"*

repo_json() { # repo_json NAME PRIVATE OWNER
  jq -n --argjson p "$2" --arg o "$3" '{private: $p, owner: {login: $o}, permissions: {admin: true}}' > "$ST/repo_$1.json"
}
repo_json dignami-aos true conwad-lab
repo_json mondmodel true conwad-lab
repo_json unghud-site true conwad-lab
repo_json pub false conwad-lab
repo_json tb-site true conwad-lab        # even if it were private: on the never-list
repo_json theirs true someone-else

RUNS=0
run() { # run "<stdin lines>" [args…] -> exit code in $RC, output in $OUT/last (and kept for the token scan)
  RUNS=$((RUNS+1))
  local input="$1"; shift
  printf '%b' "$input" | GH_DEBUG=api DEBUG=1 HOME="$T/home" PATH="$T/bin:$PATH" bash "$SKILL/bin/runner-install" "$@" > "$OUT/run$RUNS" 2>&1
  RC=$?
  cp "$OUT/run$RUNS" "$OUT/last"
}
calls() { grep -c -- "$1" "$2" 2>/dev/null || true; }
CONF="$T/home/.config/agent-team/runner.env"; STATE="$T/home/.config/agent-team/runner.machines"

# ---- (a) public, never-listed and foreign repos are refused before anything is created
run 'conwad-lab\ntesthost\npub tb-site theirs\n'
check "refused repos exit non-zero" '[ "$RC" != 0 ]'
check "public repo named as not private" 'grep -q "pub: repot är inte privat" "$OUT/last"'
check "tb-site refused by the never-list" 'grep -q "tb-site: publikt team-repo" "$OUT/last"'
check "foreign owner refused" 'grep -q "theirs: ägs av someone-else" "$OUT/last"'
check "no machine created for refused repos" '[ ! -f "$ST/orb_calls" ] && [ -z "$(ls -A "$M")" ]'
check "no registration token asked for refused repos" '[ "$(calls registration-token "$ST/gh_calls")" = 0 ]'

# ---- (g) a machine that can reach the Mac is deleted and never registered
touch "$ST/hook_not_isolated"
run 'conwad-lab\ntesthost\nunghud-site\n'
check "isolation failure exits non-zero" '[ "$RC" != 0 ]'
check "isolation failure deletes the machine" '[ ! -d "$M/runner-unghud-site" ] && grep -q "delete -f runner-unghud-site" "$ST/orb_calls"'
check "isolation failure asks no token and runs no config.sh" '[ "$(calls registration-token "$ST/gh_calls")" = 0 ] && [ ! -f "$ST/secret/config_calls" ]'
check "isolation failure leaves no state line" '! grep -q unghud-site "$STATE" 2>/dev/null'
rm -f "$ST/hook_not_isolated"

# ---- (d) a download that does not match GitHub's SHA-256 is not installed
echo "0000000000000000000000000000000000000000000000000000000000000000" > "$ST/release_sha"
run 'conwad-lab\ntesthost\nunghud-site\n'
check "checksum mismatch exits non-zero" '[ "$RC" != 0 ] && grep -q "checksum mismatch" "$OUT/last"'
check "checksum mismatch: nothing unpacked, no config.sh, no token" '[ ! -e "$M/runner-unghud-site/actions-runner/config.sh" ] && [ ! -f "$ST/secret/config_calls" ] && [ "$(calls registration-token "$ST/gh_calls")" = 0 ]'
echo "$GOOD_SHA" > "$ST/release_sha"

# ---- registration API refused: no config.sh with a made-up token
touch "$ST/hook_no_token"
run 'conwad-lab\ntesthost\nunghud-site\n'
check "refused token call exits non-zero without config.sh" '[ "$RC" != 0 ] && [ ! -f "$ST/secret/config_calls" ]'
rm -f "$ST/hook_no_token"
run '' --uninstall unghud-site
check "uninstall of a never-registered machine deletes it" '[ "$RC" = 0 ] && [ ! -d "$M/runner-unghud-site" ]'

# ---- (b) fresh install: isolated machine, token only through the pipe, hook and service in place
echo '"ubuntu-latest"' > "$ST/var_dignami-aos"
run 'conwad-lab\ntesthost\ndignami-aos\n\n'
check "fresh install exits 0" '[ "$RC" = 0 ]'
check "machine created isolated with isolated network" 'grep -q "^create --isolated --isolate-network ubuntu:noble runner-dignami-aos$" "$ST/orb_calls"'
check "config.sh got the token, name, labels and repo URL" 'grep -q -- "--url https://github.com/conwad-lab/dignami-aos --token $FAKE_TOKEN --name testhost-dignami-aos --labels mini,testhost" "$ST/secret/config_calls"'
check "runner is online on (fake) GitHub" '[ "$(jq -r ".[0].status" "$ST/runners_dignami-aos.json")" = online ]'
check "cleanup hook installed unchanged" 'cmp -s "$SKILL/assets/runner/cleanup.sh" "$M/runner-dignami-aos/actions-runner/cleanup.sh" && [ -x "$M/runner-dignami-aos/actions-runner/cleanup.sh" ]'
check "both hook lines in .env" '[ "$(grep -c "^ACTIONS_RUNNER_HOOK_JOB_\(STARTED\|COMPLETED\)=$M/runner-dignami-aos/actions-runner/cleanup.sh$" "$M/runner-dignami-aos/actions-runner/.env")" = 2 ]'
check "service installed and started" 'grep -q "runner-dignami-aos svc install" "$ST/svc_calls" && grep -q "runner-dignami-aos svc start" "$ST/svc_calls"'
check "config written, mode 600" '[ "$(stat -c %a "$CONF" 2>/dev/null || stat -f %Lp "$CONF")" = 600 ] && grep -q "^HOST=testhost$" "$CONF" && grep -q "^REPOS=\"dignami-aos\"$" "$CONF"'
check "machine recorded in the state file" 'grep -q "^runner-dignami-aos dignami-aos testhost-dignami-aos conwad-lab$" "$STATE"'
# ---- (f) RUNS_ON kept on Enter
check "RUNS_ON shown and kept on Enter" 'grep -q "RUNS_ON i dignami-aos är nu: \"ubuntu-latest\"" "$OUT/last" && [ -f "$ST/var_dignami-aos" ]'

# ---- (c) re-run with the runner online: no new registration, no new machine
before_tok="$(calls registration-token "$ST/gh_calls")"; before_mk="$(calls "^create " "$ST/orb_calls")"; before_cfg="$(wc -l < "$ST/secret/config_calls")"
run '\n\n\ny\n'
check "re-run exits 0 and says no new registration" '[ "$RC" = 0 ] && grep -q "ingen ny registrering" "$OUT/last"'
check "re-run asked no registration token and ran no config.sh" '[ "$(calls registration-token "$ST/gh_calls")" = "$before_tok" ] && [ "$(wc -l < "$ST/secret/config_calls")" = "$before_cfg" ]'
check "re-run created no second machine" '[ "$(calls "^create " "$ST/orb_calls")" = "$before_mk" ]'
# ---- (f) RUNS_ON deleted only on y
check "RUNS_ON deleted on y, old value printed for restoring" '[ ! -f "$ST/var_dignami-aos" ] && grep -q "gh variable set RUNS_ON -R conwad-lab/dignami-aos --body .\"ubuntu-latest\"." "$OUT/last"'
run '\n\n\n'
check "RUNS_ON not set: nothing asked, nothing deleted" '[ "$RC" = 0 ] && grep -q "RUNS_ON är inte satt" "$OUT/last" && [ "$(calls "DELETE repos/conwad-lab/dignami-aos/actions/variables" "$ST/gh_calls")" = 1 ]'

# ---- offline but still configured (the Mac slept, the service stopped): start it, do not re-register
jq 'map(.status = "offline")' "$ST/runners_dignami-aos.json" > "$ST/x" && mv "$ST/x" "$ST/runners_dignami-aos.json"
run '\n\n\n'
check "offline configured runner comes back without a new token" '[ "$RC" = 0 ] && grep -q "utan ny registrering" "$OUT/last" && [ "$(calls registration-token "$ST/gh_calls")" = "$before_tok" ]'

# ---- Codex M1: a hook line missing while the runner is busy is not done until the service has restarted
AR="$M/runner-dignami-aos/actions-runner"
grep -v JOB_STARTED "$AR/.env" > "$AR/.env.x" && mv "$AR/.env.x" "$AR/.env"
jq 'map(.busy = true)' "$ST/runners_dignami-aos.json" > "$ST/x" && mv "$ST/x" "$ST/runners_dignami-aos.json"
: > "$ST/svc_calls"
run '\n\n\n'
check "busy runner with a missing hook line: not reported as done, no restart under the job" '[ "$RC" != 0 ] && grep -q "inte laddad av tjänsten" "$OUT/last" && ! grep -q "svc st" "$ST/svc_calls" && [ -f "$AR/.restart-pending" ]'
jq 'map(.busy = false)' "$ST/runners_dignami-aos.json" > "$ST/x" && mv "$ST/x" "$ST/runners_dignami-aos.json"
run '\n\n\n'
check "idle re-run restarts the service so it loads the hook" '[ "$RC" = 0 ] && grep -q "svc stop" "$ST/svc_calls" && grep -q "svc start" "$ST/svc_calls" && [ ! -f "$AR/.restart-pending" ] && [ "$(grep -c "^ACTIONS_RUNNER_HOOK_JOB_" "$AR/.env")" = 2 ]'

# ---- a machine the installer did not make is never used
mkdir -p "$M/runner-mondmodel"
run 'conwad-lab\ntesthost\nmondmodel\n'
check "foreign machine with the runner's name is refused" '[ "$RC" != 0 ] && grep -q "skapades inte av den här installern" "$OUT/last" && [ ! -e "$M/runner-mondmodel/actions-runner" ]'
rm -rf "$M/runner-mondmodel"

# ---- two runners for one repo: two machines, two names, never a shared machine
printf 'RUNNERS_mondmodel=2\n' >> "$CONF"
run 'conwad-lab\ntesthost\ndignami-aos mondmodel\n'
check "two runners: two isolated machines" '[ "$RC" = 0 ] && [ -d "$M/runner-mondmodel" ] && [ -d "$M/runner-mondmodel-2" ]'
check "two runners: both online under their own names" '[ "$(jq -r "[.[] | select(.status == \"online\") | .name] | sort | join(\" \")" "$ST/runners_mondmodel.json")" = "testhost-mondmodel testhost-mondmodel-2" ]'
check "per-repo override survives the rewrite of the config" 'grep -q "^RUNNERS_mondmodel=2$" "$CONF"'

# ---- Codex S1: a registered machine that stops being isolated is deleted AND its runner revoked on GitHub
touch "$ST/hook_not_isolated" "$ST/hook_orb_delete_fails"
run 'conwad-lab\ntesthost\nmondmodel\n'
check "isolation lost, machine not deletable: state line kept for --uninstall" '[ "$RC" != 0 ] && grep -q "^runner-mondmodel " "$STATE"'
rm -f "$ST/hook_orb_delete_fails"; touch "$ST/hook_delete_fails"
run 'conwad-lab\ntesthost\nmondmodel\n'
check "isolation lost, runner not removable: state line kept" '[ "$RC" != 0 ] && [ ! -d "$M/runner-mondmodel" ] && grep -q "^runner-mondmodel " "$STATE"'
rm -f "$ST/hook_delete_fails"
run 'conwad-lab\ntesthost\nmondmodel\n'
check "isolation lost on a registered runner: runner removed on GitHub, then the state line" '[ "$RC" != 0 ] && [ "$(jq -r "[.[].name] | join(\" \")" "$ST/runners_mondmodel.json")" = "" ] && ! grep -q "mondmodel" "$STATE"'
rm -f "$ST/hook_not_isolated"
run 'conwad-lab\ntesthost\ndignami-aos mondmodel\n'
check "after the fault is gone both runners install again" '[ "$RC" = 0 ] && [ -d "$M/runner-mondmodel-2" ]'

# ---- --status
run '' --status
check "--status lists every runner as running, active, online" '[ "$RC" = 0 ] && [ "$(grep -c "running  *active  *online" "$OUT/last")" = 3 ]'

# ---- (e) --uninstall one repo: runner removed on GitHub, machine deleted, the rest untouched
run '' --uninstall dignami-aos
check "--uninstall calls the remove-runner API" '[ "$RC" = 0 ] && grep -q "^DELETE repos/conwad-lab/dignami-aos/actions/runners/[0-9][0-9]*$" "$ST/gh_calls" && [ "$(jq length "$ST/runners_dignami-aos.json")" = 0 ]'
check "--uninstall deletes the machine" 'grep -q "^delete -f runner-dignami-aos$" "$ST/orb_calls" && [ ! -d "$M/runner-dignami-aos" ]'
check "--uninstall leaves the other repo alone" '[ -d "$M/runner-mondmodel" ] && [ -f "$CONF" ] && ! grep -q dignami-aos "$STATE"'
# ---- Codex S2: a runner GitHub would not remove keeps its state line, so --uninstall can be run again
touch "$ST/hook_delete_fails"
run '' --uninstall mondmodel
check "--uninstall with a failing remove API: non-zero, state lines kept" '[ "$RC" != 0 ] && [ "$(grep -c " mondmodel " "$STATE")" = 2 ] && [ "$(jq length "$ST/runners_mondmodel.json")" = 2 ]'
rm -f "$ST/hook_delete_fails"; touch "$ST/hook_list_fails"
run '' --uninstall mondmodel
check "--uninstall with a failing runner lookup: state lines kept" '[ "$RC" != 0 ] && [ "$(grep -c " mondmodel " "$STATE")" = 2 ]'
rm -f "$ST/hook_list_fails"
run '' --uninstall mondmodel
check "--uninstall again removes both runners and their state lines" '[ "$RC" = 0 ] && [ "$(jq length "$ST/runners_mondmodel.json")" = 0 ] && [ ! -f "$STATE" ]'
repo_json unghud-site true conwad-lab
run 'conwad-lab\ntesthost\nunghud-site\n'
run '' --uninstall nope
check "--uninstall of an unknown repo refuses" '[ "$RC" != 0 ]'
run '' --uninstall
check "--uninstall without names removes the rest and the config" '[ "$RC" = 0 ] && [ -z "$(ls -A "$M")" ] && [ ! -f "$CONF" ] && [ ! -f "$STATE" ]'

# ---- (b) the token: used (config.sh got it) but in no output and no file on the Mac side or in any machine
check "token reached config.sh more than once" '[ "$(grep -c -- "--token $FAKE_TOKEN" "$ST/secret/config_calls")" -ge 3 ]'
check "runs had GH_DEBUG=api and DEBUG set (Codex M2): the installer unsets them" 'grep -q "^unset GH_DEBUG DEBUG$" "$SKILL/bin/runner-install"'
check "token in no stdout or stderr of any run" '! grep -rq "$FAKE_TOKEN" "$OUT"'
check "token in no file under HOME or the machines" '! grep -rq "$FAKE_TOKEN" "$T/home" "$M"'

# ---- a failing config.sh prints its error with the token masked
repo_json unghud-site true conwad-lab
sed -i.bak 's/\[ "\$tok" = "\$FAKE_TOKEN" \]/false/' "$T/mbin/tar" && rm -f "$T/mbin/tar.bak"
run 'conwad-lab\ntesthost\nunghud-site\n'
check "failed config.sh: error shown, token masked" '[ "$RC" != 0 ] && grep -q "token=\*\*\*" "$OUT/last" && ! grep -q "$FAKE_TOKEN" "$OUT/last"'

# ---- no token-shaped string and no bash-4-only construct in the installer
check "bash -n passes" 'bash -n "$SKILL/bin/runner-install"'
check "no mapfile, readarray, declare -A or \${var,,} (bash 3.2)" '! grep -nE "mapfile|readarray|declare -A|\\$\\{[A-Za-z_]+(,,|\\^\\^)" "$SKILL/bin/runner-install"'
check "example config and installer agree on the keys" '[ "$(grep -oE "^[A-Z_]+=" "$SKILL/assets/runner/runner.env.example" | sort | tr -d "\n")" = "DISTRO=HOST=LABELS=OWNER=REPOS=RUNNERS_PER_REPO=" ]'

echo "1..$n"
exit "$fail"
