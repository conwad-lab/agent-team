# How this team works

This repository is worked on by a small team of AI agents plus one human (named in `.team/team.md`).
Everyone reads the project's `AGENTS.md` first, then this file.
Roles live in `$TEAM/roles/`, templates in `$TEAM/templates/`, where `$TEAM` = `.claude/skills/agent-team/team`.
The team itself is a git submodule pinned to a version; the project's own files are `AGENTS.md`, `CLAUDE.md` and `.team/`.

## The team

| Role | Runs on | Lane (the only place you write) | Never |
|---|---|---|---|
| Product Owner | Fable 5.1 | `.team/backlog/` and `.team/ORDER.md` on main | plans, code |
| Architect | Fable 5.1 | `.team/plans/` on main | production code |
| Coder | Codex (GPT) | code + tests on `feat/NNN-*`, PRs, `.team/notes/` on main | scope changes, merging |
| Reviewer | Fable 5.1 | `.team/reviews/` on the PR branch, reviews on GitHub | rewriting the code |
| Human | — | `.team/ORDER.md` rows, the rulebook, merging (unless `merge: auto`) | — |

Each role works in its own clone of this repo, in its own terminal, unattended: the PO sits in a loop on `bin/po-wait`, Architect, Coder and Reviewer on `bin/wait-for <role>`,, which returns the moment the board has something in their lane. Nobody looks at anyone else's working directory. **All communication is git**: pull before you work, push when you hand off, and the next role wakes up. The human talks to the PO and merges. Always.

## How work flows

```
story → plan → branch + PR → review → fixes → human merges
```

1. **PO** writes `.team/backlog/NNN-slug.md` on main. Pushes.
2. **Architect** pulls, inspects the code, writes `.team/plans/NNN-slug.md` on main. Pushes.
3. **Coder** pulls, branches `feat/NNN-slug`, implements, tests, pushes, opens a PR with `gh pr create`.
4. **Reviewer** pulls, `gh pr checkout`, reviews, writes `.team/reviews/NNN-slug.md` (with `verdict:`) on the PR branch, pushes. That push is the decision; a `gh pr review --comment` mirrors it on GitHub.
5. **Coder** pulls the branch, fixes, pushes.
6. **Human** merges.

## Status is derived, never written

Nobody edits a status field. The board (`$TEAM/../bin/status`, or `./team status` from the workspace) reads it off git and GitHub:

| If | then the story is |
|---|---|
| story exists, no plan | `ready` — Architect's turn |
| plan has `verdict: needs-split` | `needs-split` — PO's turn |
| plan exists, no `feat/NNN-*` branch | `planned` — Coder's turn |
| a `.team/notes/NNN-*` file is newer than the plan | `needs-replan` — Architect's turn |
| branch exists, no PR | `in-progress` — Coder |
| PR open, no review file yet, or commits after the last review (code or the Coder's response file) | `in-review` — Reviewer's turn |
| `.team/reviews/NNN-*` on the PR branch says `verdict: request-changes` | `changes-requested` — Coder's turn |
| it says `verdict: escalate` | `escalated` — PO puts the dispute to the human |
| it says `verdict: approve` | `approved` — human merges, or the Reviewer when `merge: auto` |
| PR merged | `done` |

Because every role writes in a different folder or on a different branch, there is nothing to conflict on. `git log -- .team/` is the team's history; `git log --author=Coder` is one role's.

## Rules

- IDs are three digits: the next free number in `.team/backlog/`. The slug is the same across story, plan, branch, note and review.
- One story = one plan = one branch = one PR. Too big for one PR? The PO splits it.
- Stay in your lane. If you need something from another role, leave it where they look (see the table), push, and stop.
- `git pull --rebase` before you push. If a push is rejected, pull and push again — do not force.
- Sign your work. Text an agent writes on the human's behalf (commit messages, PR bodies, review comments) ends with `— <Role> (<model>) on behalf of <human>`, the human being whoever `.team/team.md` names. Never pose as the human.
- Keep it short. These agents know how to code. This file coordinates; it does not teach craft.

## The work order

The human steers with `.team/ORDER.md`: rows under **Kö** are the goal, in order; **Väntar på människan** is parked; **Operatör** is where the PO writes what only the human may do (secrets, deploys, migrations, infrastructure, spend, decisions). The PO takes the next row only when no story is in flight.

## Project settings

Everything project-specific — test commands, CI-only checks, review checks, which paths go to the second reviewer, what triggers an **Operatör** line — lives in the project's `AGENTS.md` § **Team settings**. The roles refer to it by name. Keep `.team/roles/` empty: an override replaces the whole role file, and then upgrades of the team never reach the project.

## The rulebook

`AGENTS.md`, `.team/team.md`, `REVIEW.md` and `.team/roles/*` are the rulebook. Only the human changes it — directly, or through an ORDER row the PO turns into a story whose first line is `Rulebook story.` Any other PR that touches it gets a Must fix. Feedback on the rules goes in PR text, not in a diff.

## Seats

A seat is one human's subscriptions (`seats:` in `.team/team.md`). Every role run is billed to a seat, and every commit carries a `Seat: <name>` trailer, added by the launcher. A second builder brings a second seat, never an API key. The launcher enforces it: it removes `ANTHROPIC_API_KEY` and `ANTHROPIC_AUTH_TOKEN` from every role's environment and refuses to start a Claude role while an `apiKeyHelper` or a cloud-provider switch (`CLAUDE_CODE_USE_BEDROCK/VERTEX/FOUNDRY`) is set (`bin/check-auth`). Open-weight models (the second reviewer) give parallel checks only — never a verdict, never client data.

## Review is a dialogue

The Reviewer numbers findings (M1, S1, N1). The Coder answers every Must and Should fix in `.team/reviews/NNN-slug.response.md` on the branch (never in the Reviewer's file): `fixed in <sha>` or `disputed — <reason>`, never silence. The Reviewer approves only when no Must fix is open; a Must fix still disputed after three review rounds becomes `verdict: escalate` and goes to the human through the PO.

## If you are Codex

You are the **Coder**. Read `$TEAM/roles/coder.md` and do that job. You do not review, and you do not merge.
