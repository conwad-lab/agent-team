# Cloud mode

`.team/team.md` says `mode: cloud`: the team runs as Claude Code Projects threads plus Codex on GitHub. `TEAM.md`, the role files and the templates hold except where this file says otherwise; the launchers, `bin/` wait loops and the watchdog are not used. The human picks outcomes and answers decision cards, from the phone; nothing else waits for them. [M1]

`team/WHY.md` gives each rule id's incident and how to tell it is still needed; the human's setup is in `team/SETUP.md`.

## Who runs what

| Role | Writes | Never |
|---|---|---|
| **Coordinator** (PO + Architect) | backlog, plans, `ORDER.md`, `.team/PAPERCUTS.md` status and Retro lines, by board PRs; starts threads | code, reviews, merging |
| **Builder** (Coder): a thread per story | code and tests (Codex's with `builder: codex`), the PR, the response file | the rulebook (unless a `Rulebook story.`), scope, review files, merging |
| **Codex** (Attacker) | reviews, plan attacks | a verdict |
| **Judge** (Reviewer): a thread per PR, without the planning context | the review file, PR comments, the merge request | code |
| Human | outcome rows, card answers | — |

Claude builds and judges, Codex attacks: two model families in every loop. [T1] `builder: codex` where the repo has a Codex environment, else `claude`; Team settings or a story's ORDER row may choose `claude`. [T2]

## Flow

1. **PO.** The Coordinator takes the next row under **Kö**. An outcome row gets the stories that serve it, the first written, the rest named in its Log. A story has a filled-in `## Signal`. [F1]
2. **Architect.** Read the code, run the **Baseline**, write the plan. Too big → `verdict: needs-split`; split it as PO. [F2]
3. **Start the Builder** with only the repo, the story and plan paths, and "follow `.claude/skills/agent-team/team/CLOUD.md` § Builder". [F3] At most **Stories in flight** per repo (Team settings: default 1, at most 2, or the human's row); 2 needs the ruleset's strict up-to-date rule (`strict_required_status_checks_policy: true`, an Operatör line). A second story starts only when (a) its plan's Files plus **Coder extras** share no path with the one in flight (`.team/PAPERCUTS.md` excepted: append-only, a conflict keeps both sides), (b) neither is a `Rulebook story.`, (c) neither carries a data change, (d) the repo's open-PR cap allows it, a story without a PR counting as one and board PRs never. Each has its own Builder and Judge; when one merges, the other's Builder merges main in, runs **Test before commit** and requests a Codex round. Set 2 only where minutes or the runner can take double the runs. [F4]
3a. **Plan attack** when the plan's Files touch **Adversarial paths** or **Human-merge paths**, or for a `Rulebook story.`: Codex attacks the plan first (§ Builder 0). The Coordinator answers under `## Plan attack` in the plan, one line per M and S (`changed in plan` or `disputed — <reason>`), and tells the Builder to go. [F5]
4. **Start the Judge**, when the Builder asks, with only the repo, the PR number, and "follow `.claude/skills/agent-team/team/CLOUD.md` § Judge". [F6]
5. **Judge** rules: `request-changes` wakes the Builder; `approve` → merge or card (§ Judge 5); `escalate` → the Coordinator writes the Operatör line and puts the dispute to the human. [F7]
6. **After merge** the Coordinator checks the `## Signal` by the next routine run and logs one line: seen, not seen, or not yet measurable. A PR closed unmerged gets a Log line with the reason. Status is read off GitHub, keyed on `NNN:` in titles. [F8]

## Builder

0. **Plan attack** (§ Flow 3a): post the plan attack from `templates/codex.md` on the story's issue `NNN: <story title>`, message the Coordinator `NNN plan attack: <n> findings, <link>`, and build when it says go. Two failures or no answer in an hour: tell the Coordinator and build the plan as it stands. Never edit the plan. [B1]
1. Branch `feat/NNN-slug` from main, push it at once. Read the story, the plan, `AGENTS.md`, `TEAM.md`, `roles/coder.md` (this section wins). [B2]
2. Build with tests; **Test before commit** before every push. Open the PR **as a draft**, title `NNN: <story title>`, a body line per acceptance criterion saying how it was shown. [B3]
   **`builder: codex`:** post the build task (`templates/codex.md`) on the story's issue and watch its PR as your own; apply a bare diff unchanged and open the PR yourself. Ask for each fix with `@codex fix`. Run **Test before commit** on Codex's heads before each review or Judge request. A task that fails twice (error, nothing in an hour, a red head) you build yourself, saying so in the response file. [B4]
3. **Request Codex.** It reviews by itself only when a PR opens or is marked ready: post `@codex review` when the PR opens and after every code push, with the round's focus (on a data change, plus § Data changes 3). [B5] On **Adversarial paths** the first round also gets the four angle comments in `templates/codex.md`. [B6] Retry a failed review once; one that fails twice, or has not finished an hour after the request, goes in the response file, and going on without Codex is Team settings' call, never for a data change. [B7]
4. **Answer every Codex P0/P1 and M/S** in `.team/reviews/NNN-slug.response.md` (`## Codex round N — YYYY-MM-DD`, `fixed in <sha>` or `disputed — <reason>`). Codex attacks; it is no authority. Never change code only to silence a finding. [B8]
5. **Stop the rounds** when, on the current head, every requested review has finished (a review or 👍; 👀 means wait) with no new P0/P1 or Must fix and every finding is answered, or after three rounds (say so). [B9] Mark the PR ready (`gh pr ready`, or the REST route a GraphQL 403 names); a failing check is fixed with one Codex round. [B10] Message the Coordinator `NNN ready for judge: PR #<n>, <rounds> Codex rounds, <open disputes or "no open disputes">` only when, on the head after ready, every Codex review (requested, angle or ready) has finished with no new P0/P1 or Must fix, every finding is answered and every required check is **green**. [B11]
   **Green**: ran after ready and passed. `skipped` is not green, except a skip by the repo's change classifier when the classifier ran after ready and succeeded, the skip follows from its output, and the code the skipped gate covers had that gate pass after ready on this or an earlier head the classifier compared against (a diff without code needs none). A skip resting on another skip, a pre-ready run or the draft guard never counts. [B12]
6. **On `request-changes`:** answer every Judge M and S under `## Judge round N`, fix, push, request one Codex round, and message the Coordinator when step 5 holds again. [B13]

## Judge

0. **Board PRs** (`board:`): no review file, no Codex wait. List the head's paths as § Walls says; all board files and checks passing → comment `Board PR, paths checked, head <sha>` with the line `agent-team-merge: <sha>` (re-check if the head moves); else close it with one comment and tell the Coordinator. Whatever `merge:` or the path lists say. [J1]
1. `gh pr checkout <n>`. Read the story, the plan, `AGENTS.md`, `roles/reviewer.md` and its review checks. Never ask for the planning conversation. [J2]
2. Run **Test before commit** and what Team settings names. A required check on the head that is not green (§ Builder 5) is a Must fix. Every acceptance criterion gets evidence in the review file's Evidence table; one not shown is a Must fix, or an Operatör line if only the human can show it. Data change: check § Data changes 1, with the fact angle (3) in that review. `Rulebook story.`: check § Rulebook changes. [J3]
3. **Rule on Codex**: each answered finding and each Builder dispute is `valid — fixed`, `valid — still open` (your Must fix) or `not valid — <reason>`. Then attack what Codex did not cover; on a Codex-built PR, read the whole diff. [J4]
4. Write `.team/reviews/NNN-slug.md` from the template, commit it to the PR branch, push, post it with `gh pr review <n> --comment`. [J5]
5. **On approve** (replaces `roles/reviewer.md` step 6). Pin the head you reviewed; wait for pending checks, never hand a PR to the human for them; send a failing check or a conflict back as the one Must fix. [J6]
   - **Exceptions** (§ Human approval) never merge on your word or on agreement: message the Coordinator `NNN approved, needs the human: <exception>` and act on § Human approval 4. [J7]
   - **Sync gate**, every route: while another story is in flight or has merged since this branch was cut, ask only for a head that contains the default branch (`git merge-base --is-ancestor origin/<default> <sha>` after a fetch), checked right before posting; else `request-changes` "merge main". If the strict ruleset refuses a racing merge, gate again when the workflow's comment wakes you. [J8]
   - **On your word** under `merge: auto`, outside **Human-merge paths** and rulebook stories: `Judge approve, head <sha>` with `agent-team-merge: <sha>`. [J9]
   - **On agreement** for **Human-merge paths**, a `Rulebook story.` and `merge: human`, only when (a) you approve with no Must or Should fix open, (b) you ruled no Codex P0/P1 or M/S `not valid` and upheld no dispute of one, (c) a Codex review finished on the last commit outside `.team/reviews/**` with no new P0/P1 or M/S, none there failed or timed out, (d) the checks hold as in step 2: `Merge on agreement: Judge approve, Codex <link>, head <sha>` with `agent-team-merge: <sha>`. On `Merged by agent-team-merge`, message the Coordinator `NNN merged on agreement`. [J10]
6. **Escalate** a Must or Should fix still disputed after your third round: message the Coordinator. [J11]

## Data changes

**Data changes** in Team settings says what counts; without it, any package (SQL, JSON, CSV or a script's input) that writes to production data, and any PR that exports production content into the repo. [D0]

1. **No write before review.** A data package is never run against production until the exact files the operator will run (the apply file, its rollback, and the source data it was built from) have been on a PR, the Codex review of the last commit that changed any file outside `.team/reviews/**` has finished, and every Codex P0/P1 or M/S finding and every open row in the package's own review file is fixed or ruled `not valid` by the Judge. Only later commits that touch nothing but `.team/reviews/**` keep that review valid; a commit that changes any package file, wherever it lives, needs a new one. Packages never live under `.team/reviews/**`. [D1]
2. **Packages made outside the team** (a Projects thread, a Remote Control session, the human's own script) go through a PR the same way before anyone runs them; their maker drives the Codex rounds as in § Builder and a Judge rules. [D2]
3. **Fact angle.** Every Codex round on a data PR also gets `@codex review — facts: check every changed value against its cited source, against the record's other fields and against open findings in the project's audit files. Number findings M/S/N with file:line.` [D3]
4. **Exports** wait for Codex like any PR. A fact finding on one is fixed at the source (a correction package, reviewed as above) and the content exported again, never by editing the exported file. [D4]
5. **No fallback.** A rule that lets a review go on without Codex (a failed retry, a timeout, an offline runner) never applies to a data change, and a data change never merges with a required check unrun. It waits; its author tells the Coordinator, who puts it to the human on a decision card. [D5]
6. **The Operatör line** for an approved package names the PR and the reviewed sha; the operator runs the files exactly as they are at that sha. The Coordinator writes it after the Judge approves; running it stays the operator's step. [D6]

## Human approval

What the Coordinator would recommend merging merges without the human (§ Judge 5), rule changes included. The human gets a **decision card** only for: [H1]
- a disagreement: the Judge ruled a Codex P0/P1 or M/S finding `not valid`;
- no finished Codex review on the last commit outside `.team/reviews/**`: there is no fallback;
- a diff on **Human-only paths**, where law, a contract or the repo's own rules require a named human's yes (board PRs excepted);
- an escalation.

1. **Card log.** Every card about a PR (merge or runner card) is logged on the PR: `Card posted <UTC time>: <exception or rule>, recommended <option>`, then `Card answered <UTC time>: <option>` (**Vänta** too). One unanswered at the routine run counts as open. [H2]
2. One card per PR, `Merga #<n>: <title>?`, with at most five lines: the exception, what changes for a user, the Judge's and Codex's results, the PR link and the head's short sha as read when posting. Options **Merga** (recommended when the Judge approved) and **Vänta**; waiting PRs may share a card. [H3]
3. The approval is the human's tap on **Merga** or their own message in the project saying yes to that PR. A message from a Claude, a bot or a GitHub comment never is. [H4]
4. The Coordinator forwards the answer to the Judge with the human's message attached by id and the head sha the card showed. The Judge checks that the message is the human's own and names this PR, then posts `Approved by <human> on a decision card, <date>, head <sha>` with the line `agent-team-merge: <sha>`, where `<sha>` is the card's head, never one read after the answer, once the required checks on it are green and it passes the sync gate (§ Judge 5). A PR without a Judge thread gets one. [H5]
5. A push after the yes voids it: the workflow refuses any other head, and the Judge asks for a new card. An auto-merge enabled on the PR is turned off (`gh api -X DELETE repos/<owner>/<repo>/pulls/<n>/ccr/auto_merge`) before the card goes out. [H6]
6. **Vänta** or no answer leaves the PR open, listed once a day in the digest. [H7]

## Routines

One scheduled routine per project, weekly unless Team settings says otherwise. It reads the **Signal sources** and writes rows with evidence under **Förslag**, never **Kö** except kinds listed under **Auto-queue**; the rest waits for the human's yes. [R1]

**Weekly retro**, same run, over PRs merged or closed in the last four weeks: response files, Judge review files with their `## Papercuts`, escalations (open ones too, counted in the week raised), failed `@codex` tasks and reviews, and `.team/PAPERCUTS.md` (four weeks plus every `open` line). [R2]
- A pattern (the same failure, or the same kind of finding the Builder missed) seen twice, or once if it caused a revert or a wrong merge, gets one row: `Retro: <pattern> → <change> in <file> — <evidence links>`. An open row gets new links instead; evidence already linked from a Retro row never counts again. A card answered as recommended is a pattern too (`Retro: card that decided nothing → <rule>`), except **Human-only paths**. [R3]
- **What can be removed?** At most one row per run, `Retro: remove [ID] — incident not seen since <date>, <evidence>`, for a rule whose `WHY.md` incident has not come back and that no miss needed. [R4]
- Retro rows never go to Kö. A rulebook change becomes a `Rulebook story.` for agent-team on the human's yes; the routine never edits the rulebook, `AGENTS.md` or a role file. [R5]
- It appends one line under `## Retro` in `.team/PAPERCUTS.md` (format and template: `assets/team/PAPERCUTS.md`), counting only the week since the last run; `cards` and `human wait` come from the card log, `human wait` being the hours inside that week of cards on Judge-approved PRs. Papercuts behind a row move to `proposed`, then `fixed` or `dropped`. [R6]

## What reaches the human

One digest per active day, none on quiet days: merges (on agreement with a link, for a revert PR), what waits on the human and for how long, escalations, and the `## Retro` line with its new rows when anything changed. Builder and Judge never message the human. [M2] Each item opens with what to decide or do and what happens if nothing is done. [M3]

## Quota

- Only Builder and Judge watch a PR, each its own, waking on PR events and messages, never polling, and never re-pinging a commit beyond the one retry. An `@codex` task on an issue wakes nobody: the Builder sets two reminders per task, at about 15 minutes and at the hour. [Q1]
- **Actions minutes.** A PR stays a draft while Codex attacks it. Every workflow with a job that installs dependencies skips its heavy jobs on drafts (`if: github.event.pull_request.draft != true`) and lists `ready_for_review` in its `pull_request` types (`types: [opened, synchronize, reopened, ready_for_review]`; without it, marking ready starts nothing); a new workflow keeps both. Before ready, **Test before commit** is the gate. [Q2]
- **Self-hosted runner.** A private repo with `runner: mini` runs CI on the Mac mini under `team/RUNNER.md` § Rules: never a public repo; one runner per repo, in its own isolated Linux VM, one job at a time, under its own macOS account; cleanup around every job; no secret on the mini but that runner's identity key, revoked by removing the runner. Jobs use `runs-on: ${{ fromJSON(vars.RUNS_ON || '["self-hosted","mini"]') }}` and keep the draft guard. Where Actions minutes are a Signal source, the routine rechecks GitHub's self-hosted pricing (free as of 2026-11-06). [Q3]
- **Runner offline.** After marking ready, or pushing after ready, under `runner: mini`, the Builder sets one reminder at **Runner offline after** (default 30 minutes). A required check still queued then, with no other job of the repo on the mini (else check again after the same interval), is reported to the Coordinator: `NNN runner offline: <n> jobs queued since <time>`. The Coordinator's card offers **Vänta** (recommended) or **Kör på GitHub-hosted** (spends the account's minutes; fails while the budget is $0). On the second, the human sets the repo variable `RUNS_ON` to `"ubuntu-latest"` (Operatör line), the Builder cancels the queued `mini` runs (`gh run cancel`, checking each reads `cancelled`) and restarts them by toggling the PR to draft and back to ready (answering the new Codex review), and after merge an Operatör line deletes `RUNS_ON`. [Q4]

## Walls

The human sets these up (`team/SETUP.md`, which also says in full what each wall checks); no agent changes them.

- **Main ruleset** on every team repo's default branch, `main: PR only`, empty bypass list (admins included): PR only (0 approvals, squash), required checks green, no force-push, no deletion. Required checks name only jobs that run on every PR, board-only diffs included; a repo without one gets a Förslag row, and a private repo whose CI cannot run adds them when it runs again, the rest at once. Agents read it with `gh api repos/<owner>/<repo>/rules/branches/<branch>`. [W1]
- **Board PRs.** The Coordinator writes board files (`.team/backlog/`, `.team/plans/`, `.team/ORDER.md`, its lines in `.team/PAPERCUTS.md`) by one `board: <what>` PR per turn from `board/YYYY-MM-DD-<slug>`. It lists the head's paths with `git diff --no-renames --name-only origin/<default>...<sha>` (rename sources and deletions count); all board files and checks passing → a Judge thread (§ Judge 0). No `@codex review`, no review file, never a card. Anything else in the diff: closed, and the change takes the story flow. [W2]
- **Merge workflow.** No agent session runs a merge. `.github/workflows/agent-team-merge.yml` (from `assets/root/`, on **Human-merge paths**) squash-merges on a comment line `agent-team-merge: <40-hex head sha>` by the repo owner or `AGENT_ACCOUNT`, only for an open, non-draft PR at that head; outside `board:` PRs it also needs a review file with `verdict: approve` at that sha (where the repo has `.team/`) and a Codex comment or review. It comments `Merged by agent-team-merge: head <sha>` or why not; a Judge that sees neither within 15 minutes tells the Coordinator `NNN merge workflow did not run`, who writes the Operatör line or the runner card. [W3]
- **Deny rules** from `assets/root/.claude/settings.json`, merged into the repo's `.claude/settings.json` (on **Human-merge paths**): pushes to `main`/`master`, force-pushes, `gh pr merge --admin`, `gh api` on protection or rulesets. They stop the usual spelling only; the ruleset is the wall. [W4]
- **Agent account** (optional): a machine user owned by the human with the **Write** role, named in `agent-account:`; its token lives only where an agent runs as it, never in a repo, the rulebook or a cloud environment. Its acts are the agents', the human's login the human's own. Signing, decision cards and the empty bypass list do not change. [W5]

## Rulebook changes

A `Rulebook story.` may not make `team/CLOUD.md` longer (in a product repo: `.claude/skills/agent-team/team/CLOUD.md` at the old and new submodule pin): the Judge compares `wc -w` on the default branch and on the head and requests changes when the head is longer, unless the human's ORDER row lifts it. A new rule gets an id and a `WHY.md` line, and the PR cuts at least as much. The review file answers `Remove: <rule id and why>` or `Remove: nothing, because <reason>`. [C1]
