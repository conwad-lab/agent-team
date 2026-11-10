# {{PROJECT_NAME}}

This repo is worked on by an agent team. The team's rulebook, roles and templates are a pinned git submodule at `.claude/skills/agent-team/`.

**Read `.claude/skills/agent-team/team/TEAM.md` now.** It tells you which role you are, what you own, and how handoffs work. Who the human is and which models run which role: `.team/team.md`.

## Project conventions

<!-- Everything the whole team must know about this codebase, and nothing else. -->

- Stack:
<!-- tip: keep this section the only project-specific knowledge; the rest lives in the submodule -->
- Run tests:
- Lint / format:
- Default branch: main

## Hard rails (no role reasons around these)

<!-- Things no role may do or reason around: live writes, secrets, spend, frozen contracts… -->
- Cloud mode: `main` takes changes only by PR, board files too (`.claude/skills/agent-team/team/CLOUD.md` § Walls). Never push to `main`, never force-push, never `gh pr merge --admin`, never change branch protection or rulesets.
-

## Team settings

<!-- The roles in the submodule read these by name. Keep them exact: a stale command here is followed anyway. -->

- **Test before commit:** <!-- commands the Coder and Reviewer run; must be green -->
- **Baseline:** <!-- the command the Architect runs once before planning -->
- **CI-only checks:** <!-- checks that run only in CI, and the paths that trigger them; the Reviewer waits for them -->
- **A plan must name:** <!-- e.g. which CI jobs the change triggers, whether it touches a contract -->
- **Review checks:** <!-- path-specific checks for the Reviewer; name a file here (e.g. REVIEW.md) if it wins over the role -->
- **Operator triggers:** <!-- what in a merged PR needs a line under Operatör: migrations, deploys, secrets… -->
- **Coder extras:** <!-- files to update in the same PR, files to edit with particular care -->
- **Docs to verify:** <!-- extra files verify-docs should check -->
- **Adversarial paths:** none <!-- cloud mode: paths whose PRs get three focused Codex reviews (security, failure paths, story fit) -->
- **Data changes:** <!-- cloud mode (CLOUD.md § Data changes): what writes to production data here (tables, stores, packages) and where packages and their review files live; exported content paths (e.g. src/data/**); the audit files the fact angle checks against -->
- **Builder:** <!-- cloud mode: codex or claude, the fallback for a plan without `## Estimate`; each plan's Estimate names its own builder (CLOUD.md [T2], § Builder) -->
- **Stories in flight:** 1 <!-- cloud mode: 1 or 2; 2 needs the main ruleset to require up-to-date branches (strict required status checks); a second story starts only when its plan's Files and the Coder extras do not overlap the first's, neither is a rulebook story or a data change, and the repo's open-PR cap allows (CLOUD.md § Flow 3) -->
- **Runner offline after:** 30 minutes <!-- cloud mode, runner: mini: how long a required check may sit queued before the Builder reports an offline runner (CLOUD.md § Quota, Runner offline); the daily watch uses the same limit (`bin/watch --queued-after`, CLOUD.md § Routines) -->
- **Human-merge paths:** <!-- cloud mode: paths that get a plan attack and that the Judge merges only on agreement with Codex, never on its word alone (CLOUD.md § Judge 5) — money, legal text, migrations, auth, secrets, the rulebook, `.claude/settings.json` (its deny list, CLOUD.md § Walls), `.github/workflows/agent-team-merge.yml` (the merge workflow, CLOUD.md § Walls) -->
- **Human-only paths:** none <!-- cloud mode: paths where law, a contract or this repo's own rules require a named human's yes before merge, e.g. live-migration files; always a decision card (CLOUD.md § Human approval) -->
- **Auto-queue:** none <!-- cloud mode: kinds of routine proposal that go straight to Kö, e.g. Dependabot patch updates, broken links -->
- **Signal sources:** <!-- cloud mode: what the routine's first run each week reads — e.g. Vercel runtime errors, failed Actions runs, Actions minutes, the self-hosted runner's status, Dependabot, analytics. The weekly retro always reads the team's own review files and `.team/PAPERCUTS.md` (CLOUD.md § Routines) -->

## Papercuts

When you build (as Coder or Builder, including Codex from a build task) and a step fails or needs a workaround (a tool error, a blocked command, a retry, a rule that did not fit the case), append one line to `.team/PAPERCUTS.md` in the same commit as the work: `YYYY-MM-DD | role | what failed | workaround | open`. The weekly retro turns repeated papercuts into proposals; never edit or remove other lines. As an attacker (a GitHub review) you write no files: say in the review which check you could not run and why. The Judge logs its papercuts in its review file (`roles/reviewer.md`).

## Code Review Rules

<!-- Codex reads this section for its GitHub reviews (automatic and @codex review). Keep it. -->

When you review a pull request on GitHub (automatic review or an `@codex review` comment), you are the attacker in this team's review: try to prove the change wrong. When you are started as the Coder or Builder (the local launcher, or a task that asks you to build), you are the Coder per `TEAM.md` and this section does not apply. Your findings go to the Builder, who answers each one, and to the Judge, who rules on them. You do not give the verdict.

- Number findings `M1…` (Must fix: correctness, security, a hard rail above, the rulebook, a missing test for a stated behavior), `S1…` (Should fix), `N1…` (nit), each with `file:line`, what, and why it matters. Keep P0/P1 labels too if you use them.
- Check the diff against the story in `.team/backlog/NNN-*.md`: an acceptance criterion the diff does not meet, or a change the story did not ask for, is a finding.
- Check every claim in the PR body against the diff.
- Run the **Test before commit** commands if your environment can; say which ran and which did not. Never report a check as passed that you did not run.
- When you review a PR you built yourself (`builder: codex`), review it as if someone else wrote it.
- A request comment may name a focus ("security", "failure paths", "story fit"): stay on it.
- Flag any change to `AGENTS.md`, `.team/team.md`, `REVIEW.md` or `.team/roles/*` when the story's first line is not `Rulebook story.`
- Data packages and content exports (**Data changes** in Team settings): check each changed value against its cited source, against the record's other fields and against open findings in the project's audit files. A claim that contradicts a source or an open finding is a Must fix, also when the value already sits in production.
