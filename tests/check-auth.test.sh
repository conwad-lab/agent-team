#!/usr/bin/env bash
# tests for bin/check-auth and the max-only preamble in bin/_start. Run: bash tests/check-auth.test.sh
set -u
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; n=0
ok()  { n=$((n+1)); echo "ok $n - $1"; }
nok() { n=$((n+1)); fail=1; echo "not ok $n - $1"; }
clean_env() { env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN -u CLAUDE_CODE_USE_BEDROCK -u CLAUDE_CODE_USE_VERTEX -u CLAUDE_CODE_USE_FOUNDRY HOME="$T/home" "$@"; }

mkdir -p "$T/home/.claude" "$T/clone/.claude" "$T/bin"
git -C "$T/clone" init -q

# check-auth
clean_env "$SKILL/bin/check-auth" "$T/clone" 2>/dev/null && ok "clean environment passes" || nok "clean environment passes"
clean_env ANTHROPIC_API_KEY=sk-test "$SKILL/bin/check-auth" "$T/clone" 2>/dev/null && nok "ANTHROPIC_API_KEY blocks" || ok "ANTHROPIC_API_KEY blocks"
clean_env ANTHROPIC_AUTH_TOKEN=t "$SKILL/bin/check-auth" "$T/clone" 2>/dev/null && nok "ANTHROPIC_AUTH_TOKEN blocks" || ok "ANTHROPIC_AUTH_TOKEN blocks"
clean_env CLAUDE_CODE_USE_VERTEX=1 "$SKILL/bin/check-auth" "$T/clone" 2>/dev/null && nok "cloud provider switch blocks" || ok "cloud provider switch blocks"
echo '{ "apiKeyHelper": "echo k" }' > "$T/home/.claude/settings.json"
clean_env "$SKILL/bin/check-auth" "$T/clone" 2>/dev/null && nok "apiKeyHelper in ~/.claude blocks" || ok "apiKeyHelper in ~/.claude blocks"
echo '{}' > "$T/home/.claude/settings.json"
echo '{"env":{},"apiKeyHelper":"x"}' > "$T/clone/.claude/settings.local.json"
clean_env "$SKILL/bin/check-auth" "$T/clone" 2>/dev/null && nok "apiKeyHelper in the clone blocks" || ok "apiKeyHelper in the clone blocks"
rm "$T/clone/.claude/settings.local.json"

# _start: a fake `claude` and `codex` print whether the key reached them
for c in claude codex; do printf '#!/bin/sh\necho "%s key=${ANTHROPIC_API_KEY:-none}"\n' "$c" > "$T/bin/$c"; chmod +x "$T/bin/$c"; done
run_start() { (cd "$T/clone" && clean_env PATH="$T/bin:$PATH" "$@" bash "$SKILL/bin/_start" coder coder.md "${CMD[@]}" 2>/dev/null); }
CMD=(claude); out="$(run_start ANTHROPIC_API_KEY=sk-test)"
[ "$out" = "claude key=none" ] && ok "_start strips the key before claude" || nok "_start strips the key before claude (got: $out)"
CMD=(codex); out="$(run_start ANTHROPIC_API_KEY=sk-test)"
[ "$out" = "codex key=none" ] && ok "_start strips the key before codex" || nok "_start strips the key before codex (got: $out)"
echo '{"apiKeyHelper":"x"}' > "$T/clone/.claude/settings.json"
CMD=(claude); out="$(run_start)"; [ -z "$out" ] && ok "_start refuses claude with apiKeyHelper" || nok "_start refuses claude with apiKeyHelper (got: $out)"
CMD=(codex);  out="$(run_start)"; [ "$out" = "codex key=none" ] && ok "_start leaves codex alone with apiKeyHelper" || nok "_start leaves codex alone (got: $out)"

exit $fail
