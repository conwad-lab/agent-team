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
# cloud only: who builds when a plan's ## Estimate names no builder (each plan names its own, CLOUD.md [T2]). codex = Codex from an @codex task on the story's issue (needs a Codex environment for the repo);
# claude = the Builder thread. A fresh repo has no Codex environment yet, so this starts as claude (SETUP.md § One-time setup per repo).
builder: claude
# cloud only: where CI runs. github = GitHub-hosted minutes; mini = the self-hosted runner on the Mac mini (private repos only, team/RUNNER.md).
runner: github
# cloud only: the GitHub login the agents act as (CLOUD.md § Walls); none = the human's login, signed "on behalf of".
agent-account: none

team: .claude/skills/agent-team @ {{SKILL_VERSION}}
<!-- upgrade with /agent-team upgrade, or: git submodule update --remote .claude/skills/agent-team -->

Project specifics go in AGENTS.md § Team settings, not in role overrides: a file in `.team/roles/<role>.md` replaces the whole role and cuts the project off from team upgrades.
