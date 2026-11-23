# Self-hosted runner on the host Mac

For private cloud-mode repos whose CI should not spend GitHub-hosted Actions minutes. The host Mac is the Mac that runs the team's self-hosted work: the human's MacBook now, the Mac mini later. The rules are § Rules below, which `CLOUD.md` § Quota (Self-hosted runner) points to and every team repo follows; the rest of this file is the human's setup guide. Every step below is an **Operatör** step: only the human does it, on the host Mac or in the repo's GitHub settings.

## Rules

- **Pricing check** (moved unchanged from `CLOUD.md` [Q3] in v0.8.22, binding as if it stood there). Where Actions minutes are a Signal source, the routine rechecks GitHub's self-hosted pricing.
- **Private repos only.** Never register the runner on a public repo (agent-team, tb-site): anyone who can open a PR there could run code on the host Mac. `bin/runner-install` refuses a repo that is not private or not owned by the configured account. Keep "Run workflows from fork pull requests" off in each repo (Settings → Actions → General; off by default in a private repo).
- **One runner per repo, one Linux machine per runner.** On a personal GitHub account runners are registered per repository (account-wide runners need an organization). Each runner gets its own isolated OrbStack Linux machine with its own Docker, so one repo's jobs never see another repo's containers or volumes. `RUNNERS_PER_REPO` adds machines, never runners in a shared machine: the cleanup hook removes every container and volume, so a shared Docker would kill the sibling's service containers.
- **One job at a time.** A runner process takes one job at a time; jobs beyond that queue.
- **The isolated machine is the boundary.** `orb create --isolated --isolate-network`: no Mac files, no `mac` commands, no network to the Mac or the other machines. The installer checks this from inside before it registers, and deletes a machine that fails. OrbStack's machines share one Linux VM and kernel, so this stops a job that reads or writes where it should not, not code built to break out of a kernel; that is why only the team's own private repos run here.
- **Its own macOS account on a shared or always-on host.** On the mini, the runner's machines live under a separate macOS user (`ci`) with no personal logins, keychains or browser sessions. On the human's own MacBook they run under the human's user: the isolated machine is the boundary.
- **Jobs in a Linux VM.** Service containers and `container:` jobs need Linux and Docker. On Apple silicon the runner is Linux ARM64: an action or image built only for x64 fails there, which each repo's own runner story checks.
- **Clean between jobs.** Each job starts from a clean workspace, and the cleanup hook (`assets/runner/cleanup.sh`) removes credential files, containers and volumes (named ones too) before and after it, so no secret a job used stays on the host. The hook needs Docker: the installer makes Docker start with the machine, and a hook that finds it down starts it once and gives it under a minute, every probe with its own time limit, before it stops the job. Images are different: the hook removes dangling ones every job, and every unused image and the build cache only when the machine has under 10 GB free, so a job does not pull its images again each time. While there is room, an image one job pulled or built is there for the same repo's next job, as the runner's tool cache is.
- **Disk.** A machine with its tools and the runner takes a few GB of the Mac's disk, more with the images its jobs pull. The installer creates no new machine when the Mac has less than `MIN_FREE_GB` free (5 unless `runner.env` says otherwise): it says how much is free and stops for that repo before OrbStack starts. Machines that exist are still updated.
- **Label `mini`.** Workflows pick the runner with `runs-on: ${{ fromJSON(vars.RUNS_ON || '["self-hosted","mini"]') }}` and keep the draft guard (`CLOUD.md` § Quota). The label names the team's host, whichever Mac it is, so moving to the mini changes no workflow.
- **No secret in a file, except the runner's own identity.** The registration token is never written into a repo, the rulebook, a story or a chat, and the human never sees or pastes it: the installer fetches it with the human's own `gh` login and pipes it straight into the machine, where it is `config.sh`'s argument for the seconds the registration takes. Jobs get secrets only from `secrets.*` as environment variables. The one secret that does stay on the host is the runner's identity: registering creates a key pair whose private key the runner keeps in its folder (`.credentials`, `.credentials_rsaparams`, `.runner`) to authenticate to GitHub. It can only fetch jobs for that one repo and reads no repo secret outside a job. It stays inside the runner's machine, readable only by its user, is never copied or backed up, and if the host is lost or shared, remove the runner (§ Remove a runner): that revokes the key.
- **Sleep.** A sleeping or closed MacBook takes no jobs: they queue and **Runner offline** applies (§ When it is offline). The mini removes this gap.

## Install (once per host, about 10 minutes)

1. Install OrbStack if it is missing (`brew install --cask orbstack`), open it once and turn on "Start at login". `gh auth status` shows your own login (`gh auth login` if not).
2. In Terminal:
   `bash <(curl -fsSL https://raw.githubusercontent.com/conwad-lab/agent-team/main/bin/runner-install)`
   Enter keeps each value in brackets (account, host name, the private repos). Per repo it makes the isolated machine, checks the isolation, installs what the PR workflows assume from `ubuntu-latest` (git, curl, jq, zip, python3, build tools, `gh`, Docker, passwordless sudo), downloads the runner and checks it against GitHub's published SHA-256, registers it as `<host>-<repo>` with the labels `mini` and `<host>`, installs the cleanup hook and starts the service.
3. When a repo's runner is online it shows the repo variable `RUNS_ON` and asks whether to delete it. `y` sends the jobs that use the `runs-on` expression to the runner; it prints the line that sets the variable back.

Run the same line again to update the hook and missing tools, to bring back a stopped runner, or after editing `~/.config/agent-team/runner.env` (repos, `RUNNERS_PER_REPO`). A runner that is online is never registered again. The installer prints only its own lines; what apt, Docker, the runner's scripts and systemd print is shown when a step fails, or always with ` --verbose` after the line. A repo's workflows still say where they run: `runner: mini` in `.team/team.md` and the `runs-on` expression are that repo's own rulebook-reviewed change.

## Manual fallback

Only if the installer cannot be used. Per repo:

1. `orb create --isolated --isolate-network ubuntu:noble runner-<repo>`. A normal OrbStack machine sees the Mac's files (`/mnt/mac`) and the other machines' files (`/mnt/machines`). Check from inside (`orb -m runner-<repo>`): `ls /mnt/mac /mnt/machines /Users` lists nothing of the Mac or of another machine, and after installing Docker Engine (`curl -fsSL https://get.docker.com | sh`, your user in the `docker` group) `docker run --rm hello-world` works.
2. In the repo on GitHub: Settings → Actions → Runners → **New self-hosted runner** → Linux, ARM64. In the machine, in `~/actions-runner`, run the download commands GitHub shows (they check the SHA-256), then
   `./config.sh --url https://github.com/<owner>/<repo> --token <token shown on the page> --labels mini --name <host>-<repo> --unattended`
   The token is valid for about an hour and only for registering; paste it straight from the page, nowhere else.
3. Copy `assets/runner/cleanup.sh` to `~/actions-runner/cleanup.sh`, `chmod +x` it, and add two lines to `~/actions-runner/.env`:
   `ACTIONS_RUNNER_HOOK_JOB_STARTED=/home/<user>/actions-runner/cleanup.sh` and
   `ACTIONS_RUNNER_HOOK_JOB_COMPLETED=/home/<user>/actions-runner/cleanup.sh`.
   Each job then starts from an empty workspace and a fresh checkout, and what a job left is gone after it. If the hook fails for a real reason (Docker down), the job does not start: that is on purpose, a job never runs on a dirty machine. A persistent runner with this hook is used instead of `--ephemeral`, which would need a long-lived token on the host to re-register after every job.
4. `chmod 600 .credentials*`, then `sudo ./svc.sh install && sudo ./svc.sh start`.

## Check that it is online

- On the host: the install line followed by ` --status` shows per runner the machine, the service and GitHub's view (online, offline, busy), `no-docker` when the service runs but Docker in the machine does not (every job then fails in the hook with "Cannot connect to the Docker daemon"; run the install line again: it starts Docker and, for the one diagnosed fault where two networks claim the same bridge, moves Docker's local network database aside, putting it back if that does not help), and last the Mac's free disk.
- GitHub: repo Settings → Actions → Runners shows `<host>-<repo>` as **Idle** or **Active** (works in a phone browser). **Offline** means the host is asleep or off, or OrbStack or the service is down.

## When it is offline

Jobs on the `mini` label wait in the queue (GitHub fails them after 24 hours). When the Builder's reminder fires (`CLOUD.md` [Q4]), a required check still queued, with no other job of the repo on the mini (else check again after the same interval), is reported to the Coordinator: `NNN runner offline: <n> jobs queued since <time>`. The Coordinator's card offers **Vänta** (recommended) or **Kör på GitHub-hosted** (spends the account's minutes). For GitHub-hosted, set the repo variable `RUNS_ON` to `"ubuntu-latest"` (with the quotes: it is read as JSON) under Settings → Secrets and variables → Actions → Variables, and delete the variable again when the host is back. Jobs already queued for `mini` keep waiting for it after the variable changes.

On **Kör på GitHub-hosted** (`CLOUD.md` [Q4]; moved here unchanged in v0.8.6 and v0.8.17, binding as if it stood there): the human sets the repo variable `RUNS_ON` to `"ubuntu-latest"` (Operatör line), the Builder cancels the queued `mini` runs (`gh run cancel`, checking each reads `cancelled`) and restarts them by toggling the PR to draft and back to ready (answering the new Codex review), and after merge an Operatör line deletes `RUNS_ON`.

The Codex CLI poller on the same host is a separate job: when it is down the watch says `poller-down`, and `team/CODEX-CLI.md` § When the poller is down has the fix.

## Move to the mini

Run the install line on the mini (under `ci`), then `--uninstall` on the MacBook. No workflow changes: the label stays `mini`. Keep the mini reachable: System Settings → Energy: prevent automatic sleep, and start up after a power failure. After a restart, `ci` has to be logged in for OrbStack to start (with FileVault on, macOS cannot log in automatically, so log in once after each restart).

## Remove a runner

`bin/runner-install --uninstall [repo…]` (all repos if none is named) removes the runner on GitHub, which revokes its key, and deletes its machine. By hand: Settings → Actions → Runners → the runner → Remove, then `orb delete runner-<repo>`.
