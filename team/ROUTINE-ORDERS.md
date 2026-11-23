# Routine work orders

The **Work orders** step (`CLOUD.md` [R11]). The daily routine runs it in every run, after the watch, acting as the Coordinator for § Flow 1–2 only. The goal: the Codex CLI host always has a narrow order waiting when a team repo has room for a story.

## Rules

1. **Which repos.** A team repo qualifies when (a) fewer stories are in flight than its **Stories in flight** ([F4]): open PRs titled `NNN: …` plus `feat/NNN-*` branches without a PR, review-only branches ([R10]) not counted; (b) no plan waits for its Builder: no plan on the default branch whose `NNN` has neither a PR (open or merged) nor a `feat/NNN-*` branch, parked `_NNN` plans aside; (c) the watch showed no `codex-quota` stall in the repo in 24 hours; (d) Team settings do not say `builder: claude` with a reason.
2. **Which row.** Top down, the first unchecked row under **Kö** that is decided: no story id on it, no `(efter NNN)` whose NNN is unmerged, no open question or card about it, not a `Rulebook story.`, not a data change ([D0]), and steps a plan can settle without a design choice. A row [T2] would give to Claude is skipped, not planned, and the next row is tried. At most one row per repo per run. Never a **Förslag** row: only the human moves a row to **Kö** ([R1]).
3. **Write** as § Flow 1–2 say: the story with `## Signal`, the Baseline run, the plan from `templates/plan.md` with `builder: codex-cli` (`codex` where the host poller does not list the repo), `codex-model:`, `model: light` and a `## Work order` whose `Proof:` names a test file the order adds or changes. An outcome row gets its first story, the rest named in its Log. Too big for one order: split it and plan the first. Tick the row with the story id as `.team/ORDER.md` says.
4. **Board PR.** Story, plan and the ORDER tick go in the run's one `board:` PR for that repo ([W2]), with the week's rows on the week's first run.
5. **Hand over.** Message the Coordinator once per planned row: `NNN planned for Codex: <repo> board PR #<n>, builder <codex-cli|codex>, codex-model <sol|astra>, plan attack <yes|no>`. The Coordinator starts the Judge (§ Judge 0) and, after merge, the Builder (§ Flow 3); a plan on **Adversarial paths** or **Human-merge paths** gets its plan attack first ([F5]).
6. **Nothing to plan.** A repo that qualifies under 1 but has no decided Codex row gets one digest line: `Ordrar: <repo> has room, no decided Codex row in Kö (skipped: <row ids or "none">)`. No card, no **Förslag** row.
7. **Never** the rulebook, `AGENTS.md` or a role file ([R5]), and never a thread: the routine starts none.
