---
id: NNN
verdict: plan
---

# Plan NNN — <title>

Story: `.team/backlog/NNN-slug.md`

## Approach
Two to five sentences. What and, where it matters, how.

## Estimate
<!-- Cloud mode (CLOUD.md [T2]). One value per line; bin/watch --estimates reads them. Rule of thumb: S or M, risk plain,
     and the repo has a Codex environment → codex; codex-cli where the host Mac is installed and the order can be
     written without design choices (team/CODEX-CLI.md); otherwise claude. model is the Claude thread that builds (or drives Codex):
     light for an S plain story and board or bump work; standard for M or L plain; strongest for adversarial, human-merge,
     a data change or a `Rulebook story.`; an ORDER row wins. The Judge runs standard, or strongest when this line says so.
     Parts (team/PARTS.md) when two or more pieces share no file and each has its own check.
     A ten-second diagram below helps when the shape is not obvious. -->
size: S | M | L
risk: plain | adversarial | human-merge
files: <n>
codex-rounds: <n>
builder: codex | codex-cli | claude — <one-line reason>
model: light | standard | strongest — <one-line reason>

## Files
- `path/to/file` — what changes

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
