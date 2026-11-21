---
id: NNN
verdict: plan
---

# Plan NNN — <title>

Story: `.team/backlog/NNN-slug.md`

## Approach
Two to five sentences. What and, where it matters, how.

## Estimate
<!-- Cloud mode (CLOUD.md [T2]). One value per line; bin/watch --estimates reads them. Rule of thumb, by exclusion:
     codex-cli where the host poller lists the repo (team/CODEX-CLI.md), else codex where the repo has a Codex
     environment; claude only for a `Rulebook story.`, a data change, a story whose steps need a design choice this plan
     cannot settle, or a repo whose Team settings say `builder: claude` with a reason. Size and risk do not decide.
     codex-model (the order's `Model:` line): sol for S plain, bumps, papercuts and fix orders on S stories; astra for M,
     adversarial or human-merge risk; `—` when Claude builds.
     model is the Claude thread that builds or drives Codex: light when Codex builds; when Claude builds, standard for
     plain and strongest for adversarial, human-merge, a data change or a `Rulebook story.`; an ORDER row wins.
     The Judge runs standard, or strongest for adversarial and human-merge risk, whoever built.
     Parts (team/PARTS.md) when two or more pieces share no file and each has its own check.
     A ten-second diagram below helps when the shape is not obvious. -->
size: S | M | L
risk: plain | adversarial | human-merge
files: <n>
codex-rounds: <n>
builder: codex-cli | codex | claude — <one-line reason>
codex-model: sol | astra — <one-line reason>
model: light | standard | strongest — <one-line reason>

## Files
- `path/to/file` — what changes

## Work order
<!-- When the builder is codex-cli or codex (team/CODEX-CLI.md [K2], [K7]); omit the section when Claude builds. The
     Coordinator writes it while planning; the Builder thread posts it unchanged under the header in templates/codex.md.
     No choice is left to Codex: a step that would need one is settled here, or the story is Claude's. Proof names the
     one new or changed test file that shows the story was built and the command that runs it; the poller reads this
     line from the plan on the default branch, checks the diff holds the file and runs the command. Keep `Proof:` at
     the start of its line, with ` — ` between the file and the command. -->
```
Goal: <one sentence>
May touch: <the Files above, one path per line>
Steps:
1. <exact change, file by file>
Proof: <test file> — <command>
Must not: commit or push; touch any file not under May touch; add dependencies; change tests to make them pass; <story-specific>
```

## Parts
<!-- Optional (team/PARTS.md [P1]). One line per part, at most three; omit the section when the story has no independent parts.
     Never a part: data changes, migrations, the rulebook, Human-merge or Adversarial paths, workflows, the file that wires the parts together. -->
- p1 — files: `a`, `b` — check: `<command>` — model: light | standard

## Steps
1.
2.

## Tests
-

## Risks / watch out for
-

## Out of scope
-

## Suggestions for PO
-
