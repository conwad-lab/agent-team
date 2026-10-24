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
-

## Team settings

<!-- The roles in the submodule read these by name. Keep them exact: a stale command here is followed anyway. -->

- **Test before commit:** <!-- commands the Coder and Reviewer run; must be green -->
- **Baseline:** <!-- the command the Architect runs once before planning -->
- **CI-only checks:** <!-- checks that run only in CI, and the paths that trigger them; the Reviewer waits for them -->
- **A plan must name:** <!-- e.g. which CI jobs the change triggers, whether it touches a contract -->
- **Review checks:** <!-- path-specific checks for the Reviewer; name a file here (e.g. REVIEW.md) if it wins over the role -->
- **Second-reviewer paths:** none <!-- paths whose diffs go to the open-weight second reviewer; never client data or infrastructure secrets -->
- **Operator triggers:** <!-- what in a merged PR needs a line under Operatör: migrations, deploys, secrets… -->
- **Coder extras:** <!-- files to update in the same PR, files to edit with particular care -->
- **Docs to verify:** <!-- extra files verify-docs should check -->
- **Adversarial paths:** none <!-- cloud mode: paths whose PRs get three focused Codex reviews (security, failure paths, story fit) -->
- **Human-merge paths:** <!-- cloud mode: paths the Judge never merges even with merge: auto — money, legal text, migrations, auth, the rulebook -->
- **Auto-queue:** none <!-- cloud mode: kinds of routine proposal that go straight to Kö, e.g. Dependabot patch updates, broken links -->
- **Signal sources:** <!-- cloud mode: what the weekly routine reads — e.g. Vercel runtime errors, failed Actions runs, Actions minutes, Dependabot, analytics -->

## Code Review Rules

<!-- Codex reads this section for its GitHub reviews (automatic and @codex review). Keep it. -->

When you review a pull request on GitHub (automatic review or an `@codex review` comment), you are the attacker in this team's review: try to prove the change wrong. When you are started as the Coder (the local launcher, or a task that asks you to build), you are the Coder per `TEAM.md` and this section does not apply. Your findings go to the Builder, who answers each one, and to the Judge, who rules on them. You do not give the verdict.

- Number findings `M1…` (Must fix: correctness, security, a hard rail above, the rulebook, a missing test for a stated behavior), `S1…` (Should fix), `N1…` (nit), each with `file:line`, what, and why it matters. Keep P0/P1 labels too if you use them.
- Check the diff against the story in `.team/backlog/NNN-*.md`: an acceptance criterion the diff does not meet, or a change the story did not ask for, is a finding.
- Check every claim in the PR body against the diff.
- Run the **Test before commit** commands if your environment can; say which ran and which did not. Never report a check as passed that you did not run.
- A request comment may name a focus ("security", "failure paths", "story fit"): stay on it.
- Flag any change to `AGENTS.md`, `.team/team.md`, `REVIEW.md` or `.team/roles/*` when the story's first line is not `Rulebook story.`
