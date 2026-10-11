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
./team add coder   # more throughput: coder-2/, started with ./team coder 2
```

`./team` is a three-line shim; the launcher itself lives in the submodule, so it upgrades with the team.

By hand, the same thing is: `gh repo create`, `git clone … po`, `git submodule add … .claude/skills/agent-team`, then `/agent-team init` inside `po/`.

## Upgrading a project's team

Inside any clone: `/agent-team upgrade` — or by hand, `git submodule update --remote .claude/skills/agent-team`, commit, push. Every project records its pinned version in `.team/team.md` and in the scaffold commit.

## Layout

```
SKILL.md          what Claude reads when you run /agent-team
bin/              po architect coder reviewer  — launchers (pull, pick role file, start)
                  status                       — the board, derived from git + GitHub
                  check-auth                   — max-only: no role starts on an API key (run by _start)
team/TEAM.md      the rulebook every agent reads
team/roles/       product-owner architect coder reviewer
team/templates/   story plan note review
assets/           per-project files init writes: AGENTS.md, CLAUDE.md, .team/
scripts/          init.sh, scaffold.sh
tests/            check-auth.test.sh  (bash tests/check-auth.test.sh)
workspace/team    the ./team launcher
```

## Changing the team

For every project: edit `team/roles/*.md` here, commit, tag, then upgrade each project's submodule. What differs per project (test commands, review checks, second-reviewer paths, operator triggers) goes in that project's `AGENTS.md` § Team settings — not in `.team/roles/`, because an override replaces the whole role file and the project stops receiving upgrades.

`./open-team.sh` starts all four roles unattended in one tmux session with a restart supervisor; `./stop-team.sh` stops them. `tools/agent-team-watchdog.sh` (see `tools/README.md`) restarts missing sessions, answers known dialogs and nudges idle roles across every workspace. `skills/verify-docs/` checks the rulebook against the code; link it into a project with `ln -s agent-team/skills/verify-docs .claude/skills/verify-docs`. Keep roles short — if an agent misbehaves, the fix is usually fewer instructions, not more.
