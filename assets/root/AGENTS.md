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
