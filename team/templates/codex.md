# Codex requests (cloud mode)

The Builder posts these as written, filling in `NNN-slug`, the title and the human (`CLOUD.md` § Builder). The fact angle for data changes is in `CLOUD.md` § Data changes 3.

## Plan attack (§ Builder 0, on the story's issue)

```
@codex attack the plan: read .team/plans/NNN-slug.md against .team/backlog/NNN-slug.md, AGENTS.md and the code it names. Do not write code and do not open a PR. Find wrong facts, missing cases and failure paths, acceptance criteria the plan does not meet, and scope the story did not ask for. Number findings M/S/N with file:line or plan section.
```

## Build task (§ Builder 2, `builder: codex`, on the story's issue)

A new comment, or the issue's body when the issue is new; an edited body starts nothing.

```
@codex build .team/plans/NNN-slug.md for .team/backlog/NNN-slug.md. Follow AGENTS.md. Run Test before commit. Open a draft PR titled NNN: <story title> from feat/NNN-slug, body as in roles/coder.md with one line per acceptance criterion. Sign — Coder (Codex) on behalf of <human>.

<the plan's `## Work order`, pasted unchanged>
```

Fixes, one comment per finding on the PR: `@codex fix M2: <one line>`.

## Adversarial paths (§ Builder 3, first round, four separate comments)

```
@codex security review
```
```
@codex review — security: authorization, input validation, secrets, data exposure. Number findings M/S/N with file:line.
```
```
@codex review — failure paths: errors, empty and malformed input, concurrency, retries, rollbacks. Number findings M/S/N with file:line.
```
```
@codex review — story fit: does the diff meet every acceptance criterion in .team/backlog/NNN-slug.md, and does it do anything the story did not ask for? Number findings M/S/N with file:line.
```

## CLI work order (`builder: codex-cli`, on the story's issue, with the label `codex-cli`)

The Coordinator posts it (`team/CODEX-CLI.md` [K1]–[K2], [K7]): the header lines below, then the plan's `## Work order` pasted unchanged (Goal, May touch, Steps, Proof, Must not), then the two closing lines. The first line and the `Branch:`, `Plan:`, `PR title:` and `Model:` lines are read by the poller and must stay exactly in this form. `Model:` is the plan's `codex-model:` (`sol` or `astra`); without the line the host's default model runs. The poller reads `Proof:` from the plan on the default branch, never from this comment.

```
codex-cli: build
Branch: feat/NNN-slug
Plan: .team/plans/NNN-slug.md
PR title: NNN: <story title>
Model: sol | astra

Goal: <one sentence>
May touch: <the plan's Files, one path per line>
Steps:
1. <exact change, file by file>
Proof: <test file> — <command>
Must not: commit or push; touch any file not under May touch; add dependencies; change tests to make them pass; <story-specific>

Test before commit: <the command from AGENTS.md>; it and the Proof command must be green
Answer with: one line per acceptance criterion (`- [x] <criterion>: <how shown>`), then as the very last line `Hinder: inga` or `Hinder: <short list>`.
```

Fix, one order per Codex round (the findings to fix, quoted from the review):

```
codex-cli: fix
Branch: feat/NNN-slug
Plan: .team/plans/NNN-slug.md
Model: sol | astra

Fix: M1 `<file:line>` <finding in one line>; S2 …
May touch: <paths>
Test before commit: <command>; it must be green
Must not: <as in the build order>
Answer with: one line per finding (`- M1: <what changed>`), then as the very last line `Hinder: inga` or `Hinder: <short list>`.
```
