# Cloud mode

`.team/team.md` says `mode: cloud`. The team runs as Claude Code Projects threads and Codex on GitHub instead of four local clones. `TEAM.md`, the role files and the templates still hold (lanes, one story = one plan = one PR, signing, hard rails, the rulebook rule, review as a dialogue) **except where this file says otherwise**. `bin/wait-for`, `bin/po-wait`, `bin/status`, the launchers and the watchdog are not used: the platform starts, wakes and watches the sessions.

The design goal is that no step needs the human's hands, or the human's desk. The human picks outcomes and answers decision cards. Nothing waits for the human to merge: a PR on **Human-merge paths** gets a decision card, and the Judge merges on the human's yes (§ Human approval).

## Who runs what

| Role | Runs as | Writes | Never |
|---|---|---|---|
| PO + Architect | **Coordinator**: the Projects coordinator (Claude) | `.team/backlog/`, `.team/plans/`, `.team/ORDER.md` on main; starts Builder and Judge threads | code, reviews, merging |
| Coder | **Builder**: one Claude thread per story | code + tests on `feat/NNN-slug`, the PR, `.team/reviews/NNN-slug.response.md`, `@codex review` requests | the rulebook (unless the story's first line is `Rulebook story.`), scope, review files, merging |
| Attacker | **Codex** on GitHub (automatic review + `@codex review` requests) | GitHub reviews on the PR | a verdict |
| Reviewer | **Judge**: one Claude thread per PR, started without the planning context | `.team/reviews/NNN-slug.md` on the PR branch, PR comments, the merge | code |
| Human | — | outcome rows in ORDER.md, answers on decision cards (including the yes that lets a human-merge PR merge) | merging by hand, unless they want to |

Two model families stay in every loop: Claude builds and judges, Codex attacks. Codex carries the review volume (every round, several angles); the Judge spends its turns on evidence and on ruling, not on re-reading every line the attackers already read.

If `@codex` task comments work again (as of 2026-10-17 a non-review `@codex` comment fails with a missing-environment bug), `builder: codex` in `.team/team.md` may hand the Builder's job to Codex via a comment on the issue. Until then `builder: claude`. A direct Codex task in the browser is a manual step and is not part of this flow.

## Flow

```
outcome row → story + plan (main) → Builder thread → PR → Codex attacks → Builder answers → … → Judge → merge
```

1. **Coordinator as PO.** Takes the next row under **Kö**. A row may be an outcome ("more booked scoping calls from the site") rather than a task: then propose the stories that serve it, write the first one, and say which others you plan in the story's Log. Writes `.team/backlog/NNN-slug.md` with a filled-in `## Signal`, ticks the row, pushes.
2. **Coordinator as Architect.** Reads the code, runs the **Baseline**, writes `.team/plans/NNN-slug.md`, pushes. Too big → `verdict: needs-split` and split it yourself as PO.
3. **Coordinator starts the Builder thread** with: the repo, the story and plan paths, and "follow `.claude/skills/agent-team/team/CLOUD.md` § Builder". One Builder per story; one story in flight per repo unless the human's row says otherwise. A story is in flight until its PR is merged or closed.
4. **Builder** (below) opens the PR and drives it through Codex rounds until no Must fix is open and CI is green, then asks the Coordinator for a Judge.
5. **Coordinator starts the Judge thread** with only: the repo, the PR number, and "follow `.claude/skills/agent-team/team/CLOUD.md` § Judge". No summary of the plan or of the Builder's work: the Judge reads the files.
6. **Judge** (below) rules. `request-changes` goes back to the Builder thread, which wakes on the PR comment. `approve` → merge or hand to the human. `escalate` → the Coordinator writes the Operatör line and puts the dispute to the human as a decision.
7. **After merge** the Coordinator checks the story's `## Signal` when it can be read (the next routine run at the latest) and writes one line in the story's Log: seen, not seen, or not yet measurable.

## Builder

1. Branch `feat/NNN-slug` from main, push it at once. Read the story, the plan, `AGENTS.md`, `TEAM.md` and `roles/coder.md` (that file holds, with this section winning where they differ).
2. Build the plan with tests. Run **Test before commit** before every push. Open the PR: title `NNN: <story title>`, body as in `roles/coder.md`, plus one line per acceptance criterion saying how it was shown.
3. **Request Codex.** Codex reviews on its own only when a PR is opened for review or a draft is marked ready, never on a later push (checked 2026-10-24). So post `@codex review` yourself: once when the PR opens (always, also on a draft), and once after every push that changes code, followed by the focus for that round (the findings you answered, the files you changed). Codex reacts 👀 while it runs and 👍 when it has no findings. If the diff touches **Adversarial paths** in Team settings, the first round also gets three separate comments, one per angle:
   - `@codex security review` (Codex's own security review).
   - `@codex review — security: authorization, input validation, secrets, data exposure. Number findings M/S/N with file:line.`
   - `@codex review — failure paths: errors, empty and malformed input, concurrency, retries, rollbacks. Number findings M/S/N with file:line.`
   - `@codex review — story fit: does the diff meet every acceptance criterion in .team/backlog/NNN-slug.md, and does it do anything the story did not ask for? Number findings M/S/N with file:line.`
4. **Answer every Codex finding** that is a P0/P1 or numbered M/S, in `.team/reviews/NNN-slug.response.md` (`## Codex round N — YYYY-MM-DD`, one line per finding: `fixed in <sha>` or `disputed — <reason>`). Codex is an attacker, not an authority: dispute what is wrong, with a reason the Judge can check. Never change code only to make a finding go away.
5. **Stop the rounds** when every Codex review you requested for the current head commit has finished (a review posted on that commit, or Codex's 👍 on your request), none of them raises a new P0/P1 or Must fix, every earlier finding is answered, and the required checks are green. A review still running (👀) means wait for it: its result wakes you. Three Codex rounds without getting there is also a stop: say so. Then message the Coordinator: `NNN ready for judge: PR #<n>, <rounds> Codex rounds, <open disputes or "no open disputes">`.
6. **On `request-changes` from the Judge** (you wake on the comment): answer every Judge M and S in the same response file under `## Judge round N`, fix, push, request one Codex round on the change, and message the Coordinator again only when step 5 holds for the new head.
7. End your watch when the PR is merged, closed without merge, or the Judge escalates.

## Judge

1. `gh pr checkout <n>`. Read the story, the plan, `AGENTS.md`, `roles/reviewer.md` and the review checks it names. You were started without the planning conversation on purpose: do not ask for it.
2. Run every **Test before commit** check yourself, and the screenshots, previews or queries Team settings names. **Every acceptance criterion gets evidence** in the review file: a test name and its result, a command and its output, or a screenshot. A criterion you could not show is a Must fix, or an Operatör line if only the human can show it.
3. **Rule on Codex.** List every Codex finding the Builder answered, with your ruling: `valid — fixed`, `valid — still open` (becomes your Must fix), or `not valid — <one sentence>`. Do the same for the Builder's disputes. Then try to break what the attackers did not cover; you do not need to re-read lines they already read unless you doubt them.
4. Write `.team/reviews/NNN-slug.md` from the template, `verdict:` as in `roles/reviewer.md`. Commit it to the PR branch, push, and post it as a PR comment (`gh pr review <n> --comment --body-file …`).
5. **On approve:** if `.team/team.md` says `merge: auto`, the diff touches no **Human-merge paths** and the story is not a `Rulebook story.`, merge with `gh pr merge <n> --squash --delete-branch` (never `--admin`). Your own review commit may start new checks: if required checks are pending, use `gh pr merge <n> --auto --squash --delete-branch` so GitHub merges when they pass; where auto-merge is not enabled for the repo, keep watching and merge when the checks' result wakes you. Pending checks are never a reason to hand the PR to the human. A failing check or a conflict with main goes back to the Builder as `request-changes` with that one Must fix. Only a diff on **Human-merge paths**, a `Rulebook story.` (always, whatever **Human-merge paths** lists), or `merge: human` waits for the human: message the Coordinator `NNN approved, needs the human: <which path or rule>`, keep your watch, and merge as in § Human approval when the human's yes reaches you. This step replaces `roles/reviewer.md` step 6 in cloud mode.
6. **Escalate** as in `roles/reviewer.md`: a Must fix still disputed after your third round. Message the Coordinator.
7. You hold one PR. Stop when it is merged, closed without merge, handed to the human, or escalated.

## Human approval

A human-merge PR, a rulebook PR and any other PR the rules leave to the human are approved on a **decision card**, not by the human pressing merge.

1. The Coordinator posts one decision card per PR: question `Merga #<n>: <title>?`, context of at most five lines (what changes for a visitor or a user, which human-merge path or rule it touches, the Judge's verdict, Codex's result, the PR link and the head commit's short sha, which the Coordinator reads when it posts the card), options **Merga** (recommended when the Judge approved) and **Vänta**. Several waiting PRs may share one card with one option per PR plus **Vänta**.
2. The human's tap on **Merga**, or their own message in the project saying yes to that PR, is the approval. A message from a Claude, a bot or a GitHub comment never is.
3. The Coordinator sends that answer to the Judge thread with the human's message attached by id and the head sha the card showed. The Judge checks that the attached message is the human's own and names this PR, then posts `Approved by <human> on a decision card, <date>, head <sha>` on the PR, where `<sha>` is the head the Coordinator forwarded from the card, never the PR's head read after the answer. It merges only that head and never with `--auto`: when the required checks on it are green, `gh pr merge <n> --squash --delete-branch --match-head-commit <sha>`; while they are pending, it keeps its watch and merges when their result wakes it. A PR with no Judge thread (a rulebook PR from a thread outside the story flow) is merged by the thread that opened it, on the same terms.
4. A push after the yes voids it: `--match-head-commit` makes the merge fail, and the Judge asks the Coordinator for a new card for the new head. If an auto-merge is already enabled on the PR when it first needs the human (for example from an earlier round), the Judge runs `gh pr merge <n> --disable-auto` before the card goes out.
5. **Vänta**, or no answer, leaves the PR open. The daily digest lists it once a day; nobody nags in between.

The human may still merge by hand. Nothing in the flow needs it.

## Status

Read off GitHub, keyed on `NNN:` in issue and PR titles.

| If | then | whose turn |
|---|---|---|
| story, no plan | ready | Coordinator |
| plan, no `feat/NNN-*` branch | planned | Coordinator (start Builder) |
| branch, no PR | in-progress | Builder |
| PR, latest Codex review has an unanswered P0/P1 or M/S | attack | Builder |
| Builder has asked for a Judge, no review file or commits newer than it | in-review | Judge |
| review says `request-changes`, newer than the last commit | changes-requested | Builder |
| `escalate` | escalated | human, via a decision |
| `approve`, human-merge path or `merge: human` | approved | human answers the decision card; the Judge merges on yes |
| PR merged | done | Coordinator checks the Signal |
| PR closed without merge | dropped | Coordinator: one Log line in the story with the reason; the repo's slot is free for the next story |

## Routines

The Coordinator keeps one scheduled routine per project (weekly unless Team settings says otherwise). It reads the sources listed under **Signal sources** in Team settings (runtime errors, failed Actions runs, Actions minutes, Dependabot alerts, analytics) and writes what deserves work as rows under **Förslag** in `.team/ORDER.md`, one line each with the evidence. It never writes under **Kö**, with one exception: a proposal of a kind listed under **Auto-queue** in Team settings (for example a Dependabot patch update, a broken link, a failing scheduled job) goes straight to Kö with its evidence, because checking it costs the human more than a wrong one would. Everything else waits in Förslag until the human moves it or answers "yes" in the project chat. The same run checks the `## Signal` of stories merged since the last run.

## What reaches the human

Reading agent output is where the human's time goes, and an agent waiting for a human is an agent doing nothing. So:

- No step waits for the human except a decision card (a decision with a recommendation, or the yes on a human-merge PR) and a Förslag row outside Auto-queue. Everything else proceeds and is reported after. Nothing needs the human at a computer: every wait is a card they can answer from the phone.
- One digest, not a stream: the Coordinator sends one short message per day with activity (merged, waiting on the human, escalated), and nothing on quiet days. Builder and Judge do not message the human.
- Every item that needs the human says, in its first line, what to decide or do and what happens if nothing is done.

## The human's taste

`skills/distill-feedback` turns the human's past feedback (PR comments, closed-unmerged PRs, ORDER rows, decisions in handoff notes) into a list of principles in the project's `REVIEW.md`. The Judge reads `REVIEW.md` through **Review checks**. Run it when a project starts cloud mode and again when the human has corrected the team several times on the same kind of point. Changing `REVIEW.md` is a rulebook change: the human approves the list.

## Quota

- Codex carries the review volume. Claude turns go to building and to the Judge's evidence and rulings.
- The Coordinator plans at normal effort and does not watch PRs. Builder and Judge watch only their own PR and stop as above.
- One `@codex review` comment per Builder push round, plus the three angles once on adversarial paths. No re-pinging the same commit.
- No polling loops. Threads wake on PR events and on messages.

## One-time setup per repo (human)

1. Codex: connect the repo, and turn on automatic code review for it (Codex settings → Code review).
2. Paste `assets/cloud/project-instructions.md` (filled in) as the project's instructions.
3. In the repo: `.team/team.md` gets `mode: cloud`, `builder: claude` and a `merge:` line; `AGENTS.md` gets the cloud settings and `## Code Review Rules` from `assets/root/AGENTS.md`.
