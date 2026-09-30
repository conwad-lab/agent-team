---
name: verify-docs
description: Check the documentation that steers the agent team against the code it describes, and report each claim as CONFIRMED, CONTRADICTED or NOT FOUND. Use when the operator says "verify docs", "verifiera dokumentationen", "kör verify-docs", or on the monthly schedule. Reports only; never fixes.
---

# Verify the team's documentation against the source

The files that steer the agents drift from the code: a command that was renamed, a path that moved, a CI job that no longer exists. An agent follows the stale line anyway. This skill finds those lines. It changes nothing but its report.

## Scope

Read these, in this order, and extract every checkable claim (a command, a path, a file name, a CI job, a function or table name, a rule of the form "X is done by Y", a number that is stated as current):

1. `AGENTS.md` — all sections, in particular **Team settings**
2. `REVIEW.md`, if it exists
3. `.team/team.md`
4. `.team/roles/*.md`, if any exist (project overrides)
5. `.claude/skills/agent-team/team/TEAM.md` and `.claude/skills/agent-team/team/roles/*.md` — only for claims about this repository (commands, paths)
6. Any further file listed under **Docs to verify** in `AGENTS.md` § Team settings

Opinions, principles and instructions without a factual claim ("keep it short") are out of scope.

## For each claim

Look it up in the repository — the file, the script, the workflow, the package manifest, the migration — and mark it:

- **CONFIRMED** — the source says the same. Give `file:line` of the evidence.
- **CONTRADICTED** — the source says something else. Give `file:line` of the doc line and of the evidence, and what the source actually says.
- **NOT FOUND** — nothing in the repository supports or refutes it (a path that does not exist is CONTRADICTED, not NOT FOUND).

Run a command only when running it is read-only and cheap (`--help`, `ls`, `git ls-files`, a test listing). Never run anything that writes, deploys, migrates or spends.

## Report

Write `.team/reviews/docs-YYYY-MM-DD.md`:

```
# Docs verification YYYY-MM-DD
Checked: <n> claims in <files>. CONFIRMED <a> · CONTRADICTED <b> · NOT FOUND <c>

## CONTRADICTED
| Doc line | Claim | Source says | Evidence |

## NOT FOUND
| Doc line | Claim | Where I looked |

## CONFIRMED
| Doc line | Claim | Evidence |
```

Commit it on a branch `docs/verify-YYYY-MM-DD` and open a PR titled `Docs verification YYYY-MM-DD`. For every CONTRADICTED row, add one line under **Operatör** in `.team/ORDER.md` in the same PR: which doc line is wrong and what the source says. Do not edit the docs themselves: the rulebook changes only on the human's order, and each correction becomes its own ORDER row once the human has read the report.
