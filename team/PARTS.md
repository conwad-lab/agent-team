# Parts: a story's independent pieces as parallel subagents

For plans with a `## Parts` section (`templates/plan.md`): the Builder thread runs each part as a subagent on a cheaper model, at the same time, and builds the rest itself. Still one story, one plan, one PR. `CLOUD.md` § Builder [B14] points here: that is this skill asking the Builder to use its Agent tool. Rule ids: `team/WHY.md`.

## Rules

- **[P1] When.** A plan may have `## Parts` when at least two pieces of work share no file and each can be checked alone by one command (a test file, a lint of one path). At most three parts, each S-sized. Never a part: a data change, a migration, the rulebook (`team/**`, `.claude/skills/agent-team`), a path under **Human-merge paths** or **Adversarial paths**, a workflow file, or the file that wires the parts together. Those are the spine: the Builder writes them. The Builder never adds parts the plan does not name.
- **[P2] Work order.** Before starting any part the Builder writes every part's order from `templates/workorder.md`: the goal in one sentence, the files it may touch (exactly the plan's list for that part), the interfaces it must keep (names, signatures, data shapes: copied from the spine or the plan, never described), the check command, what it must not do, and the report's last line `Hinder: inga` or `Hinder: <short list>` (`team/CODEX-CLI.md` [K3]). A design choice the order does not settle is a Hinder item, never the subagent's call.
- **[P3] Start.** All parts in one message, one Agent call each: `model` from the part's line (light → `sonnet`, standard → `opus`; never above the Builder's own), `isolation: "worktree"`, in the background. Note the commit each part starts from. The Builder builds the spine while they run and does not poll. A part not back when the spine is done gets one more wait of the same length, then counts as failed. One level only: a subagent starts no subagents. An Agent tool without `model` or `isolation`: build serially and say so in the response file.
- **[P4] Cheap check before taking a part in.** Save the part's report to a file outside its worktree and run, from your own checkout:
  `bin/part-check --dir <the part's worktree> --base <the commit the part started from> --files "<its files>" --report <file> --check "<its check>"`
  The files and the check are the plan's, never the report's; add `--ignored-ok "node_modules/"` for what installing the lockfile made. Exit 0 (every committed path on the list, nothing uncommitted or ignored left beside it, check green, `Hinder: inga`): merge the `Head:` sha it printed, never the branch name, into the story branch. Anything else, a merge conflict included: narrow the order once and run that part again, or build it yourself. A part never runs a third time, and a conflict is never hand-merged from a guess. Then **Test before commit** on the whole branch before the first push. A part's own check is not a review.
- **[P5] One PR, one owner.** Parts never push, open a PR, comment on GitHub, or talk to Codex or the Judge. The Builder answers every Codex and Judge finding, on part code too, and fixes it itself or by a new order for that part's files under [P2]–[P4]. The response file's **Outcome** says `parts: <n> taken, <n> rebuilt — <reason per rebuilt part>`. The Judge reads the PR as any other; the plan's `## Parts` tells it where the seams are.

## Example

Story 042 adds an endpoint. The handler and the route table are the spine; the tests and the docs page share no file with it or each other.

```
## Parts
- p1 — files: `tests/api/quota.test.ts` — check: `npx vitest run tests/api/quota.test.ts` — model: light
- p2 — files: `docs/api/quota.md` — check: `npx markdownlint docs/api/quota.md` — model: light
```

The order for p1, started in the same message as p2's:

```
Goal: unit tests for GET /api/quota covering the three cases in the plan's Tests.
Files you may touch: tests/api/quota.test.ts
Interfaces to keep: export async function getQuota(req: Request): Promise<Response>
  200 → { used: number, limit: number, resetsAt: string }; 401 → { error: "unauthorized" }
Check: npx vitest run tests/api/quota.test.ts
Do not: touch any other file; push; open a PR; comment on GitHub; add dependencies; start subagents.
Report: what you wrote, the check's output, then as the very last line Hinder: inga or Hinder: <short list>
```

p1 ends `Hinder: inga` and `bin/part-check` exits 0: merged. p2 ends `Hinder: the plan names no rate-limit header`: exit 3, and the Builder writes the page itself. Outcome: `parts: 1 taken, 1 rebuilt — p2: header name not in the plan`.
