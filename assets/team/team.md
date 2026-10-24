# Team config

human: {{HUMAN}}
project: {{PROJECT_NAME}}

models:
  product-owner: claude-fable-5-1
  architect: claude-fable-5-1
  coder: codex (GPT)
  reviewer: claude-fable-5-1

# One seat = one human's subscriptions; every commit carries `Seat: <name>`.
seats:
  {{HUMAN_SEAT}}: { claude: max, codex: plus }
auth: max-only — ingen API-nyckel i rollernas miljö (bin/check-auth stoppar starten)

merge: human
# mode: local (four clones, bin/wait-for) or cloud (Claude Code Projects + Codex on GitHub, see team/CLOUD.md)
mode: local
# cloud only: who builds. claude = a Claude thread; codex = an @codex task comment (only once that works)
builder: claude

team: .claude/skills/agent-team @ {{SKILL_VERSION}}
<!-- upgrade with /agent-team upgrade, or: git submodule update --remote .claude/skills/agent-team -->

Project specifics go in AGENTS.md § Team settings, not in role overrides: a file in `.team/roles/<role>.md` replaces the whole role and cuts the project off from team upgrades.
