#!/usr/bin/env bash
# tests for bin/tools-update with a fake brew (installed formulas and casks in files) and fake codex, agy, claude.
# No real update, network or GitHub call.
# Run: bash tests/tools-update.test.sh
set -u
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; n=0
ok()  { n=$((n+1)); echo "ok $n - $1"; }
nok() { n=$((n+1)); fail=1; echo "not ok $n - $1"; }
check() { if eval "$2"; then ok "$1"; else nok "$1"; fi; }

ST="$T/state"; LOGS="$T/logs"; mkdir -p "$T/bin" "$ST"
export ST
P="$T/bin:/usr/bin:/bin"

# fake brew: $ST/formula/<name> or $ST/cask/<name> holds the installed version, $ST/next/<name> the newer one,
# $ST/fail/<name> makes `upgrade` fail, $ST/hang/<name> makes it hang. Every call logged.
cat > "$T/bin/brew" <<'B'
#!/usr/bin/env bash
echo "brew $*" >> "$ST/calls"
case "$1" in
  list)
    kind=formula; [ "$2" = --cask ] && kind=cask; name="${4:-}"
    [ -f "$ST/$kind/$name" ] || exit 1; echo "$name $(cat "$ST/$kind/$name")" ;;
  upgrade)
    env | grep -E '^HOMEBREW_NO_(INSTALLED_DEPENDENTS_CHECK|INSTALL_CLEANUP)=1$' | sort | tr '\n' ' ' >> "$ST/env"; echo >> "$ST/env"
    kind=formula; name="$3"; [ "$2" = --cask ] || [ "$2" = --formula ] || name="$2"; [ "$2" = --cask ] && kind=cask
    [ -f "$ST/hang/$name" ] && sleep 30
    [ -f "$ST/fail/$name" ] && { echo "==> Upgrading $name"; echo "Error: Download failed for $name" >&2; exit 1; }
    [ -f "$ST/next/$name" ] && cp "$ST/next/$name" "$ST/$kind/$name"; exit 0 ;;
  deps) cat "$ST/deps_${4:-x}" 2>/dev/null ;;
  outdated) cat "$ST/outdated" 2>/dev/null ;;
  *) exit 1 ;;
esac
B
# fake tools: --version from $ST/v_<tool>; agy has its own `update` (version from $ST/next_agy)
for t in codex claude; do
  printf '#!/usr/bin/env bash\necho "%s $*" >> "$ST/calls"\n[ "$1" = --version ] && cat "$ST/v_%s"; exit 0\n' "$t" "$t" > "$T/bin/$t"
done
cat > "$T/bin/agy" <<'A'
#!/usr/bin/env bash
echo "agy $*" >> "$ST/calls"
case "$1" in
  --version) echo "agy $(cat "$ST/v_agy")" ;;
  --help) printf 'Usage: agy [command]\n\nCommands:\n  models   List models\n  update   Update agy\n' ;;
  update) [ -f "$ST/next_agy" ] && cp "$ST/next_agy" "$ST/v_agy" ;;
esac
A
chmod +x "$T/bin/"*

reset() {
  rm -rf "$ST"/* "$LOGS"; mkdir -p "$ST/formula" "$ST/cask" "$ST/next" "$ST/fail" "$ST/hang"
  echo 0.166.0 > "$ST/formula/codex"; echo 0.171.0 > "$ST/next/codex"; echo "codex-cli 0.166.0" > "$ST/v_codex"
  echo 2.1.330 > "$ST/cask/claude-code"; echo 2.1.331 > "$ST/next/claude-code"; echo "2.1.330 (Claude Code)" > "$ST/v_claude"
  echo 1.5.9 > "$ST/v_agy"; echo 1.6.2 > "$ST/next_agy"
  : > "$ST/calls"
}
run() { PATH="$P" HOME="$T/home" AGENT_TEAM_LOGS="$LOGS" CODEX_CLI_ENV="$T/none.env" bash "$SKILL/bin/tools-update" "$@" > "$T/out" 2>&1; rc=$?; }
L="$LOGS/tools-update.log"

# 1 every tool updated its own way, one line each
reset; run
check "rc 0" '[ "$rc" = 0 ]'
check "codex via brew formula: old → new" 'grep -qE "^[0-9TZ:-]+ codex 0\.166\.0 → 0\.171\.0$" $L && grep -q "^brew upgrade --formula codex$" $ST/calls'
check "claude via brew cask claude-code" 'grep -qE " claude 2\.1\.330 → 2\.1\.331$" $L && grep -q "^brew upgrade --cask claude-code$" $ST/calls'
check "agy not from brew: its own update command" 'grep -qE " agy 1\.5\.9 → 1\.6\.2$" $L && grep -q "^agy update$" $ST/calls'
check "exactly one line per tool" '[ "$(grep -c "" $L)" = 3 ]'
check "nothing else upgraded, no sudo" '[ "$(grep -c "^brew upgrade" $ST/calls)" = 2 ] && ! grep -q sudo $ST/calls'
check "brew runs without dependents' upgrade and global cleanup" '[ "$(grep -c "HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1 HOMEBREW_NO_INSTALL_CLEANUP=1" $ST/env)" = 2 ]'
check "models.txt written afterwards" 'grep -q "^codex offers\|^codex version" $LOGS/models.txt'

# 1b a formula whose own dependencies are outdated is skipped, so no other package changes (Codex M2 on #39)
reset; printf 'openssl@3\nripgrep\n' > "$ST/deps_codex"; printf 'openssl@3\nnode\n' > "$ST/outdated"; run
check "outdated dependency: codex skipped and logged, nothing upgraded for it" 'grep -qE " codex skipped: would also upgrade openssl@3$" $L && ! grep -q "upgrade --formula codex" $ST/calls && grep -qE " claude 2\.1\.330 → 2\.1\.331$" $L'

# 2 nothing newer: the same version twice
reset; rm "$ST/next/codex"; run
check "no newer version: same version logged" 'grep -qE " codex 0\.166\.0 → 0\.166\.0$" $L'

# 3 a failing update keeps the old version, logs the error, and the next tools still update
reset; touch "$ST/fail/codex"; run
check "failure: old version kept, error logged" 'grep -qE " codex 0\.166\.0 → 0\.166\.0 error: Error: Download failed for codex$" $L'
check "failure: the run goes on to agy and claude" 'grep -qE " agy 1\.5\.9 → 1\.6\.2$" $L && grep -qE " claude 2\.1\.330 → 2\.1\.331$" $L && [ "$rc" = 0 ]'

# 4 a hanging update is stopped at the limit
reset; touch "$ST/hang/codex"
s=$(date +%s); PATH="$P" HOME="$T/home" AGENT_TEAM_LOGS="$LOGS" CODEX_CLI_ENV="$T/none.env" TOOLS_UPDATE_LIMIT=2 bash "$SKILL/bin/tools-update" >/dev/null 2>&1; e=$(( $(date +%s) - s ))
check "hang: stopped after the limit and logged" '[ "$e" -lt 15 ] && grep -qE " codex 0\.166\.0 → 0\.166\.0 error: stopped after 2s$" $L'

# 5 not installed, and installed without brew or an update command
reset; mv "$T/bin/agy" "$T/agy.off"; rm "$ST/cask/claude-code"; run
check "missing tool: one 'not installed' line" 'grep -qE " agy not installed$" $L'
check "no brew, no update command: skipped" 'grep -qE " claude skipped: not from Homebrew and no update command$" $L'
mv "$T/agy.off" "$T/bin/agy"

# 6 lock: a live run blocks a second; a stale lock is taken over; a takeover in progress blocks; a lock naming
#   another run is never removed by this run's exit (Codex M3 on #39)
reset; mkdir -p "$LOGS"; sleep 30 & live=$!; ln -s "$live" "$LOGS/tools-update.lock"
run
check "live lock: second run stops, upgrades nothing" 'grep -q "already running (pid $live)" $L && ! grep -q "^brew upgrade" $ST/calls && [ "$(readlink $LOGS/tools-update.lock)" = "$live" ]'
kill "$live" 2>/dev/null; wait "$live" 2>/dev/null
run
check "stale lock: taken over and released" 'grep -qE " codex 0\.166\.0 → 0\.171\.0$" $L && [ ! -L "$LOGS/tools-update.lock" ]'
reset; mkdir -p "$LOGS"; ln -s 999999 "$LOGS/tools-update.lock"; mkdir "$LOGS/tools-update.lock.takeover"
run
check "takeover in progress: this run stops, lock untouched" 'grep -q "being taken over" $L && ! grep -q "^brew upgrade" $ST/calls && [ "$(readlink $LOGS/tools-update.lock)" = 999999 ]'
rmdir "$LOGS/tools-update.lock.takeover"; rm -f "$LOGS/tools-update.lock"

# 7 dry run changes nothing
reset; run --dry-run
check "dry run: says what it would run" 'grep -q "codex: would run brew upgrade --formula codex" $T/out && grep -q "agy: would run agy update" $T/out && grep -q "claude: would run brew upgrade --cask claude-code" $T/out'
check "dry run: no upgrade, no log" '! grep -q "upgrade\|agy update" $ST/calls && [ ! -e $L ]'

# 8 syntax: bash -n on the new scripts
check "bash -n" 'bash -n "$SKILL/bin/tools-update" && bash -n "$SKILL/bin/models" && bash -n "$SKILL/bin/codex-cli-install"'

echo
if [ "$fail" = 0 ]; then echo "all $n passed"; else echo "FAILED"; exit 1; fi
