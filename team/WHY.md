# Why each rule exists

One line per rule id in `CLOUD.md`, plus every rule the v0.8.0 rewrite cut or merged, so a reviewer can see what went and why. Not read every turn: read it when you change a rule, when the weekly retro asks "What can be removed?" (`CLOUD.md` § Routines), or when a rule looks pointless.

Format: `[ID] <rule> — prevents: <incident: repo#PR or date> — still needed if: <test> — kept | merged into [ID] | cut`. "design (#n)" means no incident yet: the rule was part of a design decision in that PR and is kept because the reason given still holds; the PR for v0.8.0 counts them.

A rule may be removed by a `Rulebook story.` when its "still needed if" test has been false for four weeks of retros. To bring a cut rule back, copy its old text from `git show 4ca9b21:team/CLOUD.md`.

## Kept

[M1] Human only answers cards, from the phone — prevents: Conny had to sit at the computer to merge, agent-team #7 (2026-10-25) — still needed if: any wait in the flow asks for the human's desk — kept
[M2] One daily digest; Builder and Judge silent — prevents: a stream of agent messages; agents waiting on the human 80 % of the time (Anthropic, 2026-10), #6 — still needed if: the human reads more than one message per day per project — kept
[M3] Each item opens with the ask — prevents: design (#6), kept because the human skims from the phone — still needed if: a card or digest line needed a follow-up question — kept
[T1] Claude builds and judges, Codex attacks — prevents: no session judges its own work (Rieseberg talk, #6); on Codex-built PRs Claude is the second family (#12) — still needed if: always while two model families are available — kept
[T2] The plan's Estimate picks the builder: S/M plain → codex where a Codex environment exists — prevents: scarce Claude turns spent on code Codex delivers in ~10 min (mondmodel #851, #862, #871; agent-team #12); one builder per repo whatever the story (Wonderful: Codex won 7 of 7 simple runs, Claude 62 vs 55 on complex ones; meetup 2026-11-04, story D) — still needed if: Codex build tasks keep succeeding (retro: failed @codex tasks, `bin/watch --estimates`) — kept (per story since v0.8.2)
[F1] Outcome rows become stories with a Signal — prevents: design (#6), kept because the Signal is how the team sees a story worked — still needed if: ORDER rows are outcomes — kept
[F2] Architect runs Baseline; too big → split — prevents: one story = one plan = one PR broken by oversized stories (TEAM.md, local mode) — still needed if: a PR spans more than one story's scope — kept
[F3] Builder started with repo, paths, § Builder only — prevents: planning context leaking into the build thread (#6) — still needed if: always — kept
[F4] Stories in flight ≤ 2, disjoint files, conditions a–d — prevents: one waiting PR stopped the whole repo (R2, #19); Codex M1–M4 on #19: racing merges, PAPERCUTS conflicts, PR-less stories over the cap, busy runner read as offline — still needed if: a repo runs two stories at once — kept
[F5] Plan attack on risky and rulebook stories — prevents: plan errors found only after the build (#12, Conny 2026-11-01) — still needed if: plan attacks still find M/S findings — kept
[F6] Judge started with repo and PR number only — prevents: a Judge anchored on the planner's view (#6) — still needed if: always — kept
[F7] request-changes / approve / escalate routing — prevents: design (#6), kept because it is the flow's only exit — still needed if: always — kept
[F8] Signal check and Log line after merge or close — prevents: merged stories nobody measured (#6); a closed PR left its slot unexplained (#19) — still needed if: always — kept (status key `NNN:` moved to `bin/watch`'s header, v0.8.1)
[B1] Builder posts plan attack, never edits the plan — prevents: see [F5]; Builder rewriting the plan it is judged against (#12) — still needed if: plan attacks run — kept
[B2] Branch pushed at once; read story, plan, roles — prevents: status keyed on the branch (the old § Status table, #6) showed nothing in progress — still needed if: status is read off GitHub — kept
[B3] PR opened as a draft — prevents: full CI on every fix push, mondmodel 2 922 Actions minutes in three days (agent-team #13, 2026-11-04) — still needed if: CI is billed per job — kept
[B4] builder: codex task, fixes by Codex, two failures → build yourself — prevents: Claude writing Codex's fixes; a stuck story when Codex fails (#12) — still needed if: builder: codex is used — kept
[B5] @codex review on open and every code push — prevents: Codex reviews only on open/ready, never later pushes (checked 2026-10-24, #6) — still needed if: Codex still skips later pushes — kept
[B6] Four angle comments on Adversarial paths — prevents: one generic review missing security and failure paths (#6) — still needed if: the angle reviews find findings the plain review did not — kept
[B7] Retry a failed review once; no fallback for data — prevents: Codex quota and error replies silently ending review (#11) — still needed if: Codex reviews fail (retro: failed @codex tasks) — kept
[B8] Answer every finding; never silence one; Outcome before the Judge — prevents: 34 of 90 Should fixes merged without the fix in dignify-your-craft (#10); no record of who built or what the estimate missed (FOSS: E10 planned at 25 tasks, took 55; story D) — still needed if: always — kept (format moved to `templates/response.md`, [X33])
[B9] Stop rounds on a clean head, or after three — prevents: endless Codex rounds (#6) — still needed if: always — kept
[B10] Mark ready; ready review counts — prevents: the ready review left unanswered (#13) — still needed if: [B3] holds — kept
[B11] Ask for a Judge only on a green head — prevents: Judges started on red heads (#13) — still needed if: always — kept
[B12] Green = ran after ready; classifier skip rule — prevents: a skipped job reports success (#13); docs-only PRs could never reach the Judge, dignami-aos#55 (#14) — still needed if: workflows skip on drafts or by classifier — kept
[B13] Answer Judge findings, one Codex round — prevents: design (#6) — still needed if: always — kept
[J1] Board PRs: path check, pinned merge, no review — prevents: ruleset blocks direct board pushes (#17); Coordinator merging its own PRs (Judge N2 on #17, #18) — still needed if: the main ruleset has no bypass — kept
[J2] Judge reads files, never the planning talk — prevents: see [F6] — still needed if: always — kept
[J3] Evidence per criterion; checks green; data and rulebook checks — prevents: approvals without evidence (#6); [D1] and [C1] unchecked — still needed if: always — kept
[J4] Rule on every Codex finding and dispute — prevents: Codex findings neither fixed nor ruled (#6) — still needed if: always — kept
[J5] Review file committed and posted — prevents: verdict invisible to the board and the merge workflow (#20) — still needed if: the workflow reads the review file — kept
[J6] Pin head; pending checks never go to the human — prevents: unnecessary cards while checks ran (#18) — still needed if: always — kept
[J7] Exceptions go to the human — prevents: merging over a real disagreement (#18) — still needed if: always — kept
[J8] Sync gate before every merge request — prevents: a merge of a head without the other story's merge, Codex M1 and Judge M1 on #19 — still needed if: Stories in flight can be 2 — kept
[J9] On your word under merge: auto — prevents: design (#6) — still needed if: a repo uses merge: auto — kept
[J10] Merge on agreement, conditions a–d — prevents: Conny asked to merge what Claude recommended anyway, 2026-11-07 (#18) — still needed if: always — kept
[J11] Escalate after three disputed rounds — prevents: endless disputes (#10) — still needed if: always — kept
[D0] What counts as a data change — prevents: mondmodel#854, fact errors written to production (#11) — still needed if: any repo writes production data — kept
[D1] No write before review of exact files — prevents: mondmodel#854 (#11) — still needed if: see [D0] — kept
[D2] Outside packages go through a PR — prevents: mondmodel#854, a package run from a thread without review (#11) — still needed if: see [D0] — kept
[D3] Fact angle every data round — prevents: mondmodel#854 (#11) — still needed if: fact findings keep appearing — kept
[D4] Export findings fixed at the source — prevents: exported files drifting from the source (#11) — still needed if: a repo exports content — kept
[D5] No fallback; never merge with a check unrun — prevents: a data change merged without Codex or CI (#11, #15) — still needed if: see [D0] — kept
[D6] Operatör line names PR and sha — prevents: an operator running a different version than reviewed (#11) — still needed if: see [D0] — kept
[H1] Card only for a real decision — prevents: cards the human always answered "Merga" (Conny 2026-11-07, #18) — still needed if: always — kept
[H2] Card log on the PR — prevents: retro could not count cards or waits (#18, #16) — still needed if: the retro counts cards — kept
[H3] One card per PR with head sha — prevents: a yes that named no head (#7) — still needed if: always — kept
[H4] Only the human's own message approves — prevents: a Claude or GitHub comment posing as approval (#7) — still needed if: always — kept
[H5] Judge merges the card's head, checks and sync gate — prevents: merging a head pushed after the yes (#7, #20) — still needed if: always — kept
[H6] Push after yes voids it; auto-merge off — prevents: auto-merge merging a later head (#19, #20) — still needed if: always — kept
[H7] Vänta leaves the PR open, in the digest — prevents: nagging (#7) — still needed if: always — kept
[R1] Daily routine; weekly Signal sources to Förslag, Auto-queue only to Kö — prevents: routine work reaching Kö unasked (#6); daily since v0.8.1 so [R7] runs every day (story B) — still needed if: always — kept
[R2] Weekly retro reads the agents' own misses and the estimates table — prevents: Builder misses never summed up (KRING, FOSS, meetup 2026-11-04; #16); estimates never checked against outcomes (story D) — still needed if: retro rows get approved — kept
[R3] Pattern threshold; card that decided nothing — prevents: one-off rows; cards that never change an answer (#16, Judge N2 on #18) — still needed if: see [R2] — kept
[R4] What can be removed? one row per run — prevents: a rulebook that only grows, 2 065 → 7 778 words in 17 days (Mollick 2026-11-09; this story) — still needed if: always — kept
[R5] Retro rows never to Kö; never edits rules — prevents: the routine changing the rules it reports on (#16) — still needed if: always — kept
[R6] Weekly Retro trend line; papercut status — prevents: trend lost between runs (#16) — still needed if: see [R2] — kept (count definitions moved, [X31])
[R7] Watch every run: board and stalls on one card — prevents: Actions minutes ran out 2026-11-04 and PRs stopped merging, seen only when someone looked a day later; FOSS "a merge stalled the factory and the board showed nothing" (meetup 2026-11-04); story B, v0.8.1 — still needed if: a stall reaches a card later than 24 h after it began, or the board is read — kept
[Q1] Watch own PR only; no polling; two reminders — prevents: Claude turns spent polling; issue replies wake nobody (#12) — still needed if: issue tasks do not wake threads — kept
[Q2] Draft guard and ready_for_review on workflows — prevents: mondmodel 2 922 Actions minutes in three days (#13); marking ready started nothing without the type (#13) — still needed if: CI is billed per job — kept
[Q3] Self-hosted runner rules — prevents: Actions minutes gone 2026-11-04, $0 budget (#15); Codex on #15: OrbStack VMs saw each other's files, cleanup hook failed, identity key — still needed if: a repo has runner: mini — kept
[Q4] Runner offline card and RUNS_ON fallback — prevents: jobs queued 24 h then failed with the mini down (#15); busy runner read as offline, Codex M4 on #19 — still needed if: see [Q3] — kept
[W1] Main ruleset without bypass — prevents: "never push to main" was text only (FOSS, meetup 2026-11-04; #17) — still needed if: always — kept
[W2] Board PRs with path check — prevents: see [J1] — still needed if: see [W1] — kept
[W3] Merge workflow on a pinned comment — prevents: cloud sessions blocked the Judge's own merge, agent-team #17, #18, relationsmodellen-site #48 (2026-11-07, #20) — still needed if: cloud sessions still block agent merges — kept
[W4] Deny rules in .claude/settings.json — prevents: see [W1]; early stop before GitHub refuses (#17) — still needed if: always — kept
[W5] Agent account limits — prevents: agent acts indistinguishable from the human's (KRING, #17) — still needed if: an agent account exists — kept
[C1] One in, one out; "What can be removed?" — prevents: 13 rulebook PRs since v0.7.0 added rules, none removed one (this story, 2026-11-10) — still needed if: always — kept

## Cut or merged in v0.8.0

[X1] Design goal paragraph — prevents: design (#6) — still needed if: — — merged into [M1]
[X2] Long-form Who-builds paragraph — prevents: stale "@codex tasks fail" text (#12) — still needed if: — — merged into [T2]
[X3] Direct Codex task in the browser is not the flow — prevents: manual step (#6) — still needed if: anyone uses one — cut
[X4] Judge spends turns on evidence, not re-reading — prevents: design (#6) — still needed if: — — merged into [J4]
[X5] Flow diagram — prevents: nothing; repeats the numbered steps — still needed if: — — cut
[X6] Coordinator ticks the row, pushes — prevents: design (#6) — still needed if: — — merged into [F1] and [W2]
[X7] Builder step 4 restated in Flow — prevents: nothing; repeats § Builder — still needed if: — — cut
[X8] A story in flight until merged or closed — prevents: — still needed if: — — merged into [F4]
[X9] Second story cost note in § Quota — prevents: double minutes (#19) — still needed if: — — merged into [F4]
[X10] Status table (12 rows) — prevents: design (#6); every row repeats a Flow, Builder, Judge or Quota step — still needed if: a thread cannot tell whose turn it is from the flow — merged into [F8]
[X11] Plan attack prompt in CLOUD.md — prevents: — still needed if: — — moved to `team/templates/codex.md`, merged into [B1]
[X12] Build task prompt and fix wording in CLOUD.md — prevents: — still needed if: — — moved to `team/templates/codex.md`, merged into [B4]
[X13] Four angle prompts in CLOUD.md — prevents: — still needed if: — — moved to `team/templates/codex.md`, merged into [B6]
[X14] Codex reacts 👀 / 👍 explanation — prevents: — still needed if: — — merged into [B9]
[X15] Builder step 7, stop watching — prevents: nothing beyond [Q1] — still needed if: — — merged into [Q1]
[X16] Judge step 7, hold one PR — prevents: nothing beyond [Q1] — still needed if: — — merged into [Q1]
[X17] Data changes intro "Codex finds fact errors" — prevents: rationale only — still needed if: — — moved here: see [D0]
[X18] "Such a PR is approved on the card, not by pressing merge" — prevents: — still needed if: — — merged into [H4]
[X19] "The human may still merge by hand" — prevents: rationale only — still needed if: — — cut
[X20] Distill-feedback / REVIEW.md paragraph — prevents: no incident yet; the skill describes itself (`skills/distill-feedback/SKILL.md`) and **Review checks** points the Judge at REVIEW.md — still needed if: the Judge stops reading REVIEW.md — cut
[X21] Quota: Codex carries volume, Claude turns elsewhere — prevents: design (#6) — still needed if: — — merged into [T1]
[X22] Quota: one @codex review per push round — prevents: re-pinging (#6) — still needed if: — — merged into [B5] and [Q1]
[X23] Anthropic 80 % waiting statistic — prevents: rationale only — still needed if: — — moved here, see [M2]
[X24] Walls: ruleset vs classic protection rationale — prevents: rationale only — still needed if: — — moved to `team/SETUP.md` § Walls in full
[X25] Walls: merge workflow internals (default-branch copy, no checkout, branch delete, AFTER_MERGE_WORKFLOWS, "a floor, not the review") — prevents: #20 — still needed if: — — moved unchanged to `team/SETUP.md` § Walls in full; agent-facing part in [W3]
[X26] Walls: deny-list spellings, "deny wins over allow" — prevents: #17 — still needed if: — — moved unchanged to `team/SETUP.md` § Walls in full; agent-facing part in [W4]
[X27] Walls: agent-account token type, Write-role abilities, cloud threads unchanged — prevents: #17 — still needed if: — — moved unchanged to `team/SETUP.md` § Walls in full; agent-facing part in [W5]
[X28] One-time setup per repo (8 steps) — prevents: — still needed if: — — moved unchanged to `team/SETUP.md`
[X29] Retro trend line format in CLOUD.md — prevents: — still needed if: — — moved to `assets/team/PAPERCUTS.md`, merged into [R6]
[X30] Runner offline rationale (variable change does not move queued jobs; GitHub fails after 24 h) — prevents: #15 — still needed if: — — moved to `team/RUNNER.md` § When it is offline, merged into [Q4]

## Cut or merged in v0.8.1

[X31] Retro counts `cards` and `human wait` defined in CLOUD.md — prevents: — still needed if: — — moved to the `## Retro` comment in `assets/team/PAPERCUTS.md`, merged into [R6]
[X32] Digest lists what waits on the human and for how long — prevents: #7 — still needed if: — — merged into [M2] and [H7] as the board's link; `bin/watch` shows a PR with an open or Vänta card as the human's turn with its age

## Cut or merged in v0.8.2

[X33] Response-file round format in CLOUD.md [B8] and [B13] — prevents: — still needed if: — — moved to `team/templates/response.md`, merged into [B8]
[X34] [R1] "the rest waits for the human's yes" — prevents: — still needed if: — — dropped as a restatement: Förslag rows never reach Kö except Auto-queue kinds
