<!-- .team/reviews/NNN-slug.response.md: the Builder's answers (CLOUD.md § Builder 4). Append a section per round; never edit the Judge's or Codex's text. -->

## Codex round 1 — YYYY-MM-DD
- M1 `file:line` <finding in a few words> — fixed in <sha> | disputed — <reason>

## Judge round 1 — YYYY-MM-DD
- M1 — fixed in <sha> | disputed — <reason>

## Outcome
<!-- Filled before the Judge request (CLOUD.md [B8]). bin/watch --estimates counts the Codex rounds above and the hours from PR to merge itself.
     parts: only when the plan has `## Parts` (team/PARTS.md [P5]); none when the Agent tool could not run them. -->
built-by: codex | codex-cli | claude | codex->claude | codex-cli->claude
model: <the model id the Builder thread ran, e.g. claude-opus-5-5>
parts: <n> taken, <n> rebuilt — <reason per rebuilt part> | none
missed: <one line on what the plan's Estimate missed, or nothing>
