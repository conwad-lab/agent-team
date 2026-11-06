# Self-hosted runner on the Mac mini

For private cloud-mode repos whose CI should not spend GitHub-hosted Actions minutes. The rules live in `CLOUD.md` § Quota (Self-hosted runner); this file is the human's setup guide. Every step below is an **Operatör** step: only the human does it, on the mini or in the repo's GitHub settings.

## Rules

- **Private repos only.** Never register the runner on a public repo (agent-team, tb-site): anyone who can open a PR there could run code on the mini.
- **One runner per repo, one Linux machine per runner.** On a personal GitHub account runners are registered per repository (account-wide runners need an organization). Each repo's runner gets its own OrbStack Linux machine with its own Docker, so one repo's jobs never see another repo's containers or volumes. Start with one repo; add the next only when a story says so.
- **One job at a time.** A runner process takes one job at a time; jobs beyond that queue.
- **Its own macOS account.** The runner runs under a separate macOS user (`ci`) with no personal logins, keychains or browser sessions.
- **Jobs in a Linux VM.** The runner runs inside an OrbStack Linux machine under `ci`, because service containers and `container:` jobs need Linux and Docker.
- **Label `mini`.** Workflows pick the runner with `runs-on: ${{ fromJSON(vars.RUNS_ON || '["self-hosted","mini"]') }}` (`CLOUD.md` § Quota).
- **No secret in a file, except the runner's own identity.** The registration token is typed on the mini once and is never written into a repo, the rulebook, a story or a chat. Jobs get secrets only from `secrets.*` as environment variables. The one secret that does stay on the mini is the runner's identity: registering creates a key pair whose private key the runner keeps in its folder (`.credentials`, `.credentials_rsaparams`, `.runner`) to authenticate to GitHub. It can only fetch jobs for that one repo and reads no repo secret outside a job. Keep it inside the runner's Linux machine, readable only by its user (`chmod 600 .credentials*`), never copy or back it up, and if the mini is lost or shared, remove the runner on GitHub (§ Remove a runner): that revokes the key.

## Set up (once per mini)

1. Create a standard macOS user `ci` (System Settings → Users & Groups). Log in as `ci` from here on.
2. Install OrbStack, turn on "Start at login", and create one Linux machine per repo (for example `orb create ubuntu runner-<repo>`). In each machine (`orb -m runner-<repo>`), install Docker Engine (`curl -fsSL https://get.docker.com | sh`) and add your user to the `docker` group, so jobs and service containers run on Linux inside the VM.
3. Keep the mini reachable: System Settings → Energy: prevent automatic sleep, and start up after a power failure. After a restart, `ci` has to be logged in for OrbStack to start (with FileVault on, macOS cannot log in automatically, so log in once after each restart).

## Register a repo (once per repo)

1. In the repo on GitHub: Settings → Actions → Runners → **New self-hosted runner** → Linux, and the CPU of the mini (ARM64).
2. In that repo's OrbStack machine (`orb -m runner-<repo>`), in a new folder `~/actions-runner-<repo>`, run the download commands GitHub shows, then:
   `./config.sh --url https://github.com/<owner>/<repo> --token <token shown on the page> --labels mini --name mini-<repo> --unattended`
   The token is valid for about an hour and only for registering; paste it straight from the page.
3. Clean state between jobs: create `~/actions-runner-<repo>/cleanup.sh` with

   ```sh
   #!/bin/sh
   # Runs before and after every job (ACTIONS_RUNNER_HOOK_JOB_STARTED/COMPLETED).
   [ -n "$GITHUB_WORKSPACE" ] && [ -d "$GITHUB_WORKSPACE" ] && find "$GITHUB_WORKSPACE" -mindepth 1 -delete
   rm -f "$HOME/.docker/config.json" "$HOME/.npmrc" "$HOME/.netrc" "$HOME/.git-credentials"
   docker rm -f $(docker ps -aq) >/dev/null 2>&1
   docker volume prune -af >/dev/null 2>&1   # -a: named volumes too, not only anonymous ones
   docker network prune -f >/dev/null 2>&1
   exit 0
   ```

   `chmod +x cleanup.sh`, and add two lines to `~/actions-runner-<repo>/.env`:
   `ACTIONS_RUNNER_HOOK_JOB_STARTED=/home/<user>/actions-runner-<repo>/cleanup.sh` and
   `ACTIONS_RUNNER_HOOK_JOB_COMPLETED=/home/<user>/actions-runner-<repo>/cleanup.sh`.
   Each job then starts from an empty workspace and a fresh checkout (`actions/checkout` cleans by default), and credential files, containers and volumes (named ones too) a job may have left are gone after it. The machine runs this one runner only, so removing every container and volume never touches another job. The runner removes `$RUNNER_TEMP` itself. A persistent runner with this hook is used instead of `--ephemeral`, which would need a long-lived token on the mini to re-register after every job.
4. Install it as a service that starts at boot: `sudo ./svc.sh install && sudo ./svc.sh start`.
5. In `.team/team.md`, `runner: mini` (a rulebook-reviewed change in that repo, together with its workflows' `runs-on`).

## Check that it is online

- GitHub: repo Settings → Actions → Runners shows `mini-<repo>` as **Idle** or **Active** (works in a phone browser). **Offline** means the mini, OrbStack or the service is down.
- On the mini: `sudo ./svc.sh status` in the runner folder.

## When it is offline

Jobs on the `mini` label wait in the queue (GitHub fails them after 24 hours). The Builder reports it after **Runner offline after** and the human gets a decision card: **Vänta** or **Kör på GitHub-hosted** (`CLOUD.md` § Quota). For GitHub-hosted, set the repo variable `RUNS_ON` to `"ubuntu-latest"` (with the quotes: it is read as JSON) under Settings → Secrets and variables → Actions → Variables, and delete the variable again when the mini is back. Jobs already queued for `mini` keep waiting for it after the variable changes; the Builder cancels them and starts new runs (`CLOUD.md` § Quota, Runner offline).

## Remove a runner

Settings → Actions → Runners → the runner → Remove, then `sudo ./svc.sh uninstall` and `./config.sh remove --token <token shown>` on the mini.
