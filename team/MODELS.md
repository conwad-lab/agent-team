# Models: the map, the nightly update and the model watch

New models reach the team on the human's yes, within two days of a tool offering them. The host Mac keeps its CLIs current every night and writes what each one offers; the daily routine compares that, and the Claude models the Coordinator itself can pick, with the project's **model map**, and puts one card per newer model to the human. Nothing switches without a yes. `CLOUD.md` [R12] points here; rule ids are explained in `team/WHY.md`.

## The model map

One file per project, `MODELS.md` in the project folder (beside `BOARD.md`), which the routine and the human both read. The project instruction names the file instead of listing ids, so a yes is one edit there. One line per role:

```
- light: claude-sonnet-5-5 — since 2026-11-16 — Conny on card "Modellval"
- standard: claude-opus-5-5 — since 2026-11-16 — Conny on card "Modellval"
- strongest: claude-fable-5-2 — since 2026-11-16 — Conny on card "Modellval"
- astra: gpt-6-astra — since 2026-11-18 — codex-cli install
- sol: gpt-6-sol — since 2026-11-21 — codex-cli install
- declined: gpt-6.2-sol — 2026-11-24 — Conny: Vänta
```

- `role: id — since YYYY-MM-DD — source`. The id is exactly as the tool or the project lists it (spaces allowed, e.g. `Gemini 4 Argon`). `light`, `standard` and `strongest` are the Claude thread models ([T2]); `astra` and `sol` mirror the poller config's `MODELS` (`team/CODEX-CLI.md`), which the poller itself reads; `reserve` is the Gemini reviewer's model once story G runs.
- `declined: <id> — <date> — <who>` records a card answered no: that id never gets a card again, a later one does.
- **Families**: astra, sol, luna, terra, argon, carbon, hydrogen, opus, sonnet, haiku, fable. An offered id is **newer** than one in use when it is the same line of models (the two ids match once their numbers are taken out, so `gpt-6.2-astra` is an Astra and `gpt-6.2-astra-mini` or `Gemini 4 Carbon` is not an Argon) and its version number is higher. Ids outside the families are never compared.

## How each tool is asked

`bin/models` asks each tool with stdin closed and a 60-second limit, never a prompt; a tool without a non-interactive listing says `offers unknown`, and no card comes from it.

| Tool | Version | Models offered | Checked |
|---|---|---|---|
| Codex CLI | `codex --version` | `codex debug models`: the catalogue as JSON, refreshed from the account when signed in; entries with `visibility: list` (hidden ones are left out) | 0.171.0, 2026-11-23: lists `gpt-6.2-astra` and `gpt-6.2-sol` |
| Antigravity `agy` | `agy --version` | `agy models`: one model per line, read leniently (bullets, notes in brackets and after two spaces dropped) | 1.5.9 listed its models 2026-11-14; the first run's `Models:` line confirms the format |
| Claude Code | `claude --version` | none: Claude Code has no model listing (2.1.330). The Coordinator's own model list stands in (§ Routine 2) | 2026-11-23 |

## The nightly update (host Mac)

`bin/codex-cli-install` loads a second launchd job, `se.agent-team.tools-update`, at 03:30 local time (a Mac asleep runs it on waking). `bin/tools-update` updates `codex`, `agy` and `claude`: with Homebrew where Homebrew installed it, else with the tool's own `update` command, else skipped. It logs one line per tool, `<date> <tool> <old> → <new>`, to `~/Library/Logs/agent-team/tools-update.log`; a failed update keeps the old version, logs the error and goes on. It touches nothing else: Homebrew runs without upgrading dependents or its 30-day cleanup, a formula whose own dependencies are outdated is skipped and logged (`skipped: would also upgrade <deps>`), and it never uses `sudo`. Every command, the GitHub post included, runs with a time limit in a process group of its own, and a lock (one step, never ownerless) keeps two runs apart. Then `bin/models` writes `~/Library/Logs/agent-team/models.txt` and posts it, with the poller's token, as one comment on the issue `agent-team: models on <host>` in `conwad-lab/agent-team` (`MODELS_REPO` in the poller config changes the repo), edited in place each night. The token needs Issues on that repo (§ Install). A tool update that breaks the poller shows as a bounced run; the log gives the date to compare against.

## Routine

Every run, after the work orders [R11]:

1. Read the newest comment starting `<!-- agent-team-models -->` on the open issue `agent-team: models on <host>` in `conwad-lab/agent-team`. Missing, or its `models <host> <time>` line older than 2 days: one **Förslag** row `modellvakten tyst sedan <date>` (the host slept, or the job or token broke) instead of cards from it.
2. Write the Claude models the project offers when you start a thread, one `coordinator offers <id>` line each, to a file.
3. Run `bin/models --report <comment> --report <that file> --map <project folder>/MODELS.md`. Put one `Models:` line in the run's output: each tool's version and how many ids it offers, and the `newer` lines (or `inga nya`).
4. One card per `newer <tool> <role> <in-use> → <offered>` line: `Byt <role> till <offered>?`, recommended **Ja**, with the evidence line (the tool and its version, the date the host first listed it if the log shows it) and what changes: the Builder or Judge threads (Claude roles) or the Codex CLI runs (astra, sol). Options **Ja** and **Vänta**. A card not yet answered is not sent again; **Vänta** adds a `declined:` line to the map.

## On yes

The Coordinator changes the id in every place it is written:

- **The model map**: the role's line gets the new id, `since <date>` and the card as source; the old line moves under `## History` at the bottom of the file. Threads started from then on use it.
- **Codex roles** (astra, sol): an Operatör line for the human, `kör install-raden igen (team/CODEX-CLI.md § Install) och skriv <id> för <role>`, since the poller config lives on the host. Until then the poller runs the old id.
- **The rulebook**: one PR in `conwad-lab/agent-team`, `Rulebook story. Model: <role> → <id>`, that changes the installer's default (`bin/codex-cli-install`, `assets/codex-cli/codex-cli.env.example`) for a Codex role and adds the switch with its date to [R12]'s model note in `team/WHY.md`.

Out of scope: switching automatically; `@codex` on GitHub (no model choice exists there).
