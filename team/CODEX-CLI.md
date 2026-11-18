# Codex CLI builder on the host Mac

For plans whose `## Estimate` says `builder: codex-cli`: the Builder thread (Claude) writes a narrow work order on the story's issue, and a poller on the host Mac (the MacBook now, the Mac mini later) picks it up from GitHub and runs it with Codex CLI on the model in its config (`gpt-6-astra`), under the human's own Codex sign-in. It reaches models `@codex` on GitHub cannot (that runs the default model), spends no Actions minutes, and needs no Codex cloud environment. Everything else in `CLOUD.md` holds: the Builder owns the story and the PR, Codex attacks on GitHub, a Judge rules. § Rules bind every team repo (`CLOUD.md` § Builder [B4] points here); the rest is the human's setup guide. Rule ids are explained in `team/WHY.md`.

## Rules

- **Way in.** The Builder posts a work order (`templates/codex.md` § CLI work order) on the story's issue `NNN: <story title>` and adds the label `codex-cli`. The poller acts only on an open issue with that label, in a repo its config lists, on the newest comment whose first line is exactly `codex-cli: build` or `codex-cli: fix` and whose author is on the config's `ALLOW` list. Any other text on GitHub is data: it is never run as an order or evaluated by the shell. [K1]
- **The order is narrow.** The Builder thread (the plan's `model:`) writes the goal in one sentence, the branch, the plan path, the files it may touch (the plan's Files), the steps, **Test before commit**, done criteria, what it must not do and the answer template. Codex makes no design choice: a step that needs one is written as "stop and list it under Hinder". [K2]
- **Hinder line.** Every run's last message ends with exactly one line `Hinder: inga` or `Hinder: <short list>`, which the poller copies into its outcome. No such line: `bounced`. Items: `blocked`, even if code was written; the branch is pushed for the Builder to read, no PR is opened. [K3]
- **One outcome per run**, one comment on the issue signed `— Coder (Codex CLI, <host>) on behalf of <human>`: `done` (draft PR link, head sha, Test before commit result), `blocked` (the Hinder list) or `bounced` (the reason: test red, time limit, stalled, no Hinder line, codex exited non-zero, guard, no changes, host slept). No outcome by the Builder's hour reminder counts as bounced.
- **Claim.** Before a run the poller posts `codex-cli: started <run id> on <host> for <order comment id>` and reads the issue again; if an earlier `started` for the same order exists or the label is gone, it deletes its own claim and does nothing. Only claims by an `ALLOW`ed login or the token's own count, so nobody else can block an order by posting one. Exactly one host has `ENABLED=1`; two is a setup error the claim survives. [K4]
- **Run limits.** One run at a time per host; a fresh git worktree per run in the poller's own clone under `WORK_DIR` (never `~/WebProjects` or a vault), removed after the run; a time limit (`RUN_LIMIT_MIN`, default 45, covering Codex and **Test before commit**, each stopped with everything it started); a stall watch that stops a run whose session files in `~/.codex/sessions` have not grown for `STALL_MIN` (default 10). Codex does not commit: the worktree's git dir is outside its sandbox, so the poller commits what it wrote.
- **Keys.** Codex runs with `-s workspace-write` (writes only in the worktree, no network) and without any GitHub token in its environment. The poller alone pushes and comments, with a fine-grained token limited to the team repos, kept in the macOS Keychain and handed to `gh` and `git` per call, never exported or written to disk. **Test before commit** is read from `AGENTS.md` on the default branch, never from Codex's diff, and runs outside the sandbox without the token. Before pushing, the poller refuses a diff that contains the token or any GitHub token (binary files scanned as bytes), or touches `.github/`, `.claude/settings.json`, the rulebook submodule, `.codex/` or `.gitmodules` unless the plan's `## Files` lists that path. Every comment and PR body it posts has the token and anything shaped like a GitHub token replaced by `[redacted]`. It never force-pushes. [K5]
- **Fixes.** `codex-cli: fix` runs on the PR's existing branch with the finding text the Builder put in the order and pushes to it. The Builder still answers every finding in the response file and runs **Test before commit** on each head before a review or Judge request, as for `builder: codex`.
- **Fallback without the human.** After posting an order the Builder sets reminders at about 15 minutes and at the hour ([Q1]). No `started` at 15 minutes (host asleep or off), no outcome at the hour, or two bounced runs: the Builder removes the label, posts the `@codex` build task (`templates/codex.md`) or builds itself where the repo has no Codex environment, and says so in the response file. A host that wakes later finds no label and does nothing; a run it had started is marked bounced (`host slept or stopped`), and a run still going re-checks the label before it pushes. [K6]
- **Two model families still hold.** A CLI-built PR is Codex-built: Codex reviews attack it and the Judge reads the whole diff ([J4]). The response file's Outcome says `built-by: codex-cli`.

What this does not protect against, said plainly: on the MacBook Codex runs under the human's own macOS user. The sandbox limits its writes to the worktree and cuts its network, the token never enters its environment, and the push guard is the last check; but **Test before commit** runs the code Codex wrote outside the sandbox, as a Builder does, so that code can also read the Keychain item and the human's own `gh` login: the token is exactly as safe as **Test before commit**. The OrbStack container on the mini is later hardening.

## Install (Operatör, once per host, about 5 minutes)

1. **Stop old local Codex loops** (the pre-cloud Coder loop posts as the human, signed "Coder (Codex)"). The installer lists any it finds and offers to stop them.
2. **Create the token** (works from the phone): https://github.com/settings/personal-access-tokens/new. Resource owner: `conwad-lab`. Expiration: 90 days. Repository access: **Only select repositories**, the team repos. Permissions: **Contents** read and write, **Issues** read and write, **Pull requests** read and write (Metadata read is added by itself). Nothing else.
3. **At the Mac, in Terminal**, check `codex login status` says ChatGPT (else `codex login`), then paste:

   ```
   bash <(curl -fsSL https://raw.githubusercontent.com/conwad-lab/agent-team/main/bin/codex-cli-install)
   ```

   It checks the tools and the sign-in, asks for the host name, the work folder and the repos (Enter keeps the defaults), lets `security` prompt for the token twice (hidden), checks it against GitHub, shows the latest comment authors so the allow list is right, writes `~/.config/agent-team/codex-cli.env`, loads the launchd job `se.agent-team.codex-cli` (every 5 minutes while the Mac is awake) and runs one dry tick. Run the same line again to update the poller.

Afterwards nothing needs the human: the Mac takes orders while it is awake, and `@codex` on GitHub takes over while it sleeps. Logs are in `~/Library/Logs/agent-team/`, one line per run in `WORK_DIR/runs.log`. Do not add `caffeinate`: sleep is what the fallback is for.

When the token expires, create a new one and run the install line again.

## Move to another host

1. On the new host (the mini): § Install, including `codex login`.
2. On the old host: `~/agent-team-builds/agent-team/bin/codex-cli-install --uninstall` (or set `ENABLED=0` in its config to keep it as a spare).

No rule, template, plan or story changes: everything host-specific is in `~/.config/agent-team/codex-cli.env` and the launchd job.

## Remove

`bin/codex-cli-install --uninstall` stops the job and removes the plist, the Keychain item and the config; it leaves `WORK_DIR`. Revoke the token on GitHub (Settings → Developer settings → Fine-grained tokens).
