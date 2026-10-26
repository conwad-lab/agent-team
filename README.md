# agent-team

A Claude Code skill that runs a multi-model agent team on a GitHub repo:
Product Owner, Architect and Reviewer on Claude (Fable 5.1), Coder on Codex (GPT).

This is Conny Wadbro's fork of [fltman/agent-team](https://github.com/fltman/agent-team): unattended roles under a tmux supervisor, a work order (`.team/ORDER.md`), project settings in `AGENTS.md` § Team settings, review as a numbered dialogue with escalation, seats, and a watchdog.
The team lives **in the project** as a pinned git submodule. One clone per role, one terminal per clone, all communication through git. Status is derived, never written. The human merges.

See [SKILL.md](SKILL.md) for the design and [team/TEAM.md](team/TEAM.md) for the rulebook the agents get.

## New project

One command, from nothing to a running workspace:

```bash
curl -sL https://raw.githubusercontent.com/conwad-lab/agent-team/main/new-project.sh | bash -s -- myproj
```

It creates the GitHub repo if needed (private by default, `--public` to change), makes `./myproj-team/`, clones `po/`, pins the newest tagged team version as a submodule, scaffolds, pushes, clones `architect/`, `coder/`, `reviewer/`, writes `./team` — and opens the four roles, each in its own window: a 2×2 grid of Terminal windows on macOS, a 2×2 tmux session elsewhere (`--no-open` to skip). From a clone of this repo, `./new-project.sh myproj` does the same.

```
cd myproj-team
./team open        # (again) PO top-left, Architect top-right, Coder and Reviewer below; --tmux for tmux anywhere
                   # every role starts working on launch; Architect/Coder/Reviewer wait on the board and wake up when it's their turn
./team board       # the board, refreshed every 30 s — park it in a corner
./team monitor     # live page in the browser: who is working on what, stories by phase, timeline — switch between all your teams
./team po          # or start any single role by hand — PO is the one you talk to; ask it to fill in Project conventions first
./team status      # the board, once
./team log         # who did what
./team hits        # what became of the Reviewer's findings: fixed, disputed, or merged without the fix
./team add coder   # more throughput: coder-2/, started with ./team coder 2
```

`./team` is a three-line shim; the launcher itself lives in the submodule, so it upgrades with the team.

By hand, the same thing is: `gh repo create`, `git clone … po`, `git submodule add … .claude/skills/agent-team`, then `/agent-team init` inside `po/`.

## Cloud mode (v0.7)

`mode: cloud` in `.team/team.md` runs the same team without clones, terminals or hand-offs by the human: the Claude Code Projects coordinator is PO + Architect, a Claude thread per story builds, Codex attacks every round on GitHub (automatic review and `@codex review`, three focused angles on **Adversarial paths**), and a separate Claude thread without the planning context judges with evidence per acceptance criterion and merges when `merge: auto` allows. A weekly routine reads the project's **Signal sources** and proposes ORDER rows under **Förslag**. See [team/CLOUD.md](team/CLOUD.md); paste [assets/cloud/project-instructions.md](assets/cloud/project-instructions.md) as the project's instructions. `skills/distill-feedback/` writes the human's principles into `REVIEW.md` for the Judge.

Local mode is unchanged.

## Vercel

Board commits can otherwise create full deployments of unchanged application code.
`bin/vercel-ignore-build` skips a build only when a non-empty, verified diff from
`VERCEL_GIT_PREVIOUS_SHA` to `VERCEL_GIT_COMMIT_SHA` changes paths under the root
`.team/` directory alone. It checks the whole interval, including deletions and
both sides of renames. Production and preview use the same rule. Code changes,
missing revisions, empty diffs, unknown environments and failed checks build.
Vercel's exit contract is 0 to skip, 1 to build.

Set this in the Vercel project dashboard:

```text
Settings → Build and Deployment → Ignored Build Step: bash .claude/skills/agent-team/bin/vercel-ignore-build
```

Vercel must clone the public agent-team submodule. A missing submodule makes the
command fail, so Vercel builds. Init prints the setting when it finds `vercel.json`
or `.vercel/`; it never creates or edits `vercel.json` or changes live settings.

E2E jobs that look for a preview at the PR head need a fallback when a board-only
commit skips that preview. They may use the latest built preview only after
verifying that the **entire diff from its revision to the PR head** changes only
root `.team/` paths. If that proof fails, do not use the old preview. See
mondmodel's `sovereign-deploy.yml`, step “Get Vercel preview URL”, for this pattern.
This filter does not install an E2E fallback in existing projects.

## Upgrading a project's team

Inside any clone: `/agent-team upgrade` — or by hand, `git submodule update --remote .claude/skills/agent-team`, commit, push. Every project records its pinned version in `.team/team.md` and in the scaffold commit.

## Layout

```
SKILL.md          what Claude reads when you run /agent-team
bin/              po architect coder reviewer  — launchers (pull, pick role file, start)
                  status                       — the board, derived from git + GitHub
                  hits                         — review findings on merged stories and what became of them
                  vercel-ignore-build          — skip proven board-only Vercel builds
                  check-auth                   — max-only: no role starts on an API key (run by _start)
team/TEAM.md      the rulebook every agent reads
team/roles/       product-owner architect coder reviewer
team/templates/   story plan note review
assets/           per-project files init writes: AGENTS.md, CLAUDE.md, .team/
scripts/          init.sh, scaffold.sh, vercel-hint.sh
tests/            check-auth.test.sh, vercel-ignore-build.test.sh, init-vercel.test.sh, hits.test.sh
                  run each with bash tests/<name>.test.sh
workspace/team    the ./team launcher
```

## Changing the team

For every project: edit `team/roles/*.md` here, commit, tag, then upgrade each project's submodule. What differs per project (test commands, review checks, second-reviewer paths, operator triggers) goes in that project's `AGENTS.md` § Team settings — not in `.team/roles/`, because an override replaces the whole role file and the project stops receiving upgrades.

`./open-team.sh` starts all four roles unattended in one tmux session with a restart supervisor; `./stop-team.sh` stops them. `tools/agent-team-watchdog.sh` (see `tools/README.md`) restarts missing sessions, answers known dialogs and nudges idle roles across every workspace. `skills/verify-docs/` checks the rulebook against the code; link it into a project with `ln -s agent-team/skills/verify-docs .claude/skills/verify-docs`. Keep roles short — if an agent misbehaves, the fix is usually fewer instructions, not more.
