---
name: setup-cubrid-agent
description: "Provision a freshly installed cubrid-agent so its skills become runnable. Asks the operator once for consent, then runs the bundled setup.sh so it both lays down the $HOME machine assets (testcases and engine clones, CTP, the env file) and installs the three CLIs the skills require -- gh, pandoc >= 2.19, cubrid-jira -- instead of only naming them. Then it resolves whatever could not be forced (a sudo password, the JDK), runs sanity checks, and ends with a per-skill readiness report. This is the manual entrypoint to run once after install; invoke it as /setup-cubrid-agent. Credentials stay the operator's and never land in the repo, and it never installs a CUBRID build on its own -- the build is issue-dependent, so it only guides the --build step. NOT for: running the pipeline skills, injecting secrets, or installing a CUBRID build unattended."
disable-model-invocation: true
# Provisioning: the steps are fixed and the judgment is narrow (which TODOs matter, did a sanity
# check pass), so deliberating here buys nothing. Not `low` — reading TODO output is interpretation.
effort: medium
---

# setup-cubrid-agent — one-time install → usable

Bring a freshly installed cubrid-agent to the "install + one setup → usable" bar. `setup.sh` handles the machine state (Tier 2) non-interactively and idempotently; this skill drives it, then completes the parts the script deliberately leaves to a human (Tier 3 — sudo installs and credentials), and reports which skills are actually runnable. Asset model and tiers: `docs/deployment.md`; decision: `.agents/adr/0003-setup-entrypoint-skill.md`.

**Manual entrypoint** (`disable-model-invocation: true`): it changes machine state (clones, sudo installs), so it runs only when the operator invokes `/setup-cubrid-agent`, never on its own.

## What it does / does NOT

**Does:** ask the operator once for consent, then run the bundled `setup.sh` so it lays down the `$HOME` assets **and installs the three CLIs the skills require**; resolve whatever the script could not force; run sanity checks; print a per-skill readiness report.

**Does NOT:** inject or print credentials (Tier 3 is the human's; secrets never land in the repo or a script); install a CUBRID build unattended (the build is issue-dependent — it only guides `--build`); run any pipeline skill.

## Process

### 1. Ask once, then run the provisioning script

`gh`, `pandoc` and `cubrid-jira` are not optional — without them the pipeline skills cannot read an issue, write to Jira, or open a PR. So the script installs them rather than naming them, and the operator's consent is collected **once, here**, before anything is touched. State exactly what will change:

- **`gh`** — needs root (`sudo dnf` / `sudo apt-get`). The only one that does.
- **`pandoc 2.19.2`** — a static build unpacked into `~/.local`, no sudo. Never the distro package (RHEL 8 ships 2.0.6, which has no `jira` reader/writer).
- **`cubrid-jira`** — `uv tool install` into `~/.local`, no sudo; `uv` is installed the same way when absent.
- Not installed either way: **credentials** (yours alone) and a **CUBRID build** (issue-dependent, `--build`).

Run the `scripts/setup.sh` that ships next to this SKILL.md — it is the **canonical and only** copy (there is no repo-root wrapper; ADR-0003). Resolve it in this order:

1. `${CLAUDE_PLUGIN_ROOT}/skills/qa/setup-cubrid-agent/scripts/setup.sh` when `CLAUDE_PLUGIN_ROOT` is set (plugin channel);
2. otherwise the `scripts/setup.sh` in this skill's own directory (npx channel, or a repo checkout at `skills/qa/setup-cubrid-agent/scripts/setup.sh`).

On **yes**: `bash <resolved-path> --install-clis`. On **no**: `bash <resolved-path>` — identical run minus the installs, with every missing tool reported as a `TODO` carrying its command. Either way it is idempotent and non-interactive: it installs only what its capability checks say is missing (so a re-run installs nothing), clones the `$HOME` assets only when absent, makes `~/.cubrid-agent/`, writes `~/.cubrid-agent/env.sh`, and ends with `OK` / `TODO` lines plus a TODO count.

It also installs the **shared helpers the pipeline skills call by absolute path** into `~/.cubrid-agent/bin/`. They live in this skill's `bin/` (its own implementation stays in `scripts/`, so what is payload and what is setup do not mix): `ground-issue.sh` grounds one JIRA issue (body + every comment + every attachment, classified by content), and `render-pr-body.sh` renders a TC PR body from the run manifest and the testcase. One installed path is what makes those skills channel-independent: the plugin exports `CLAUDE_PLUGIN_ROOT`, but `npx skills add` copies a single skill's own directory, so no skill-relative path resolves for a helper that several skills share. **A machine provisioned before a helper changed needs a re-run** — that is how the new copy arrives.

### 2. Resolve what the script could not force (Tier 3 — with the operator)

With `--install-clis` a CLI still showing up as `TODO` means its install could not be forced — read the line, it says which. The common one is `gh`: `sudo` asked for a password, which a script cannot answer, so the exact command is in the TODO and the operator runs it themselves. Everything below is what remains a human's job. Reference: `docs/setup.md` §2–§3.

- **JDK (`javac`) missing** — the script does not install this one (distro package, needs root): `sudo dnf install java-1.8.0-openjdk-devel` (Debian/Ubuntu: `sudo apt install default-jdk`), then re-run `setup.sh` so it detects the JDK and rewrites `env.sh`.
- **`gh` still TODO** — `sudo` asked for a password, or the machine has neither `dnf` nor `apt-get`. Give the operator the command the TODO already carries: `sudo dnf install -y 'dnf-command(config-manager)' && sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo && sudo dnf install -y gh` (other distros: `docs/setup.md` §3).
- **`pandoc` still TODO** — the download or extract failed, or the machine is not x86_64. It needs **>= 2.19**, and **never the distro package** (`dnf`/`apt` on RHEL 8 ships 2.0.6, which has neither format: writing a markdown issue body hard-fails, and reading an issue comes back empty instead of erroring on a `cubrid-jira` older than 2026-07-30). No sudo needed, and no `gh` either — a public release asset downloads unauthenticated. A static build in `~/.local` shadows any system pandoc by `$PATH` order: `mkdir -p ~/.local && curl -fL -o /tmp/pandoc.tar.gz https://github.com/jgm/pandoc/releases/download/2.19.2/pandoc-2.19.2-linux-amd64.tar.gz && tar xzf /tmp/pandoc.tar.gz -C ~/.local --strip-components=1`. Verify the capability, not the binary: `pandoc --list-input-formats | grep -qx jira`.
- **`cubrid-jira` still TODO** — `uv tool install git+https://github.com/vimkim/cubrid-jira.git` (or `pipx install …`; never `pip install -e .`); uv fetches the Python 3.14+ it needs, so there is no system-Python prerequisite. An install older than 2026-07-29 lacks authenticated reads and the `attachment` subcommand, so the skills fail outright. Above that floor, take the latest rather than a date — two fixes landed two hours apart on 2026-07-30, so the date names both and neither. The latest buys: an old pandoc no longer blanks the body, and a 401 stops after one attempt instead of one per related issue. Either way: `uv tool upgrade cubrid-jira`.
- **`~/.local/bin` not on PATH** — the script reports this when it installed there but a new shell would not see it. `export PATH="$HOME/.local/bin:$PATH"` in `~/.bashrc`; without it the next session behaves as if pandoc and cubrid-jira were never installed.
- **Credentials missing** — do NOT set them for the operator; give the checklist and let them run it: `export CUBRID_JIRA_USER=… CUBRID_JIRA_PASSWORD=…` (or a `~/.netrc` `machine jira.cubrid.org`, `chmod 600`); `gh auth login` (or `GH_TOKEN`). Never echo a credential value.

After any of these, **re-run `setup.sh`** and confirm the TODO count drops. Credentials — and any install that needed a sudo password — are the operator's to finish; a leftover TODO is a partial setup, not a failure (see the report).

### 3. Sanity checks

- `cubrid-jira search CBRD-25913` → issue markdown means the CLI + credentials work. Check that the **Description section has content**: an empty body with a healthy exit is the pandoc symptom above, not an empty issue — as is a `Warning: pandoc cannot convert Jira wiki markup …` on stderr, which a newer CLI prints while handing back raw markup. On `Auth failed (HTTP 401)`, **do not retry** (repeat failures trigger a CAPTCHA lockout) — an install older than 2026-07-29 has no authenticated reads, so `uv tool upgrade cubrid-jira` first, then re-check the credentials.
- `gh auth status` → authenticated.
- `source ~/.cubrid-agent/env.sh` in a CTP session → `CTP_HOME`, `JAVA_HOME` and `CUBRID_JIRA_USER` set. Remind the operator this `source` is per-session. If `CUBRID_JIRA_USER` is missing from it, the Jira username could not be resolved — the pipeline skills must stop rather than run a queue query that would return 0 issues.

### 4. CUBRID build — guide only, never run

The `verify` skills and the verify stage of author-testcase need a CUBRID **release** build **that contains the target issue's fix** at `$HOME/CUBRID`. The build is issue-dependent, so this skill does **not** install one. Guide the operator to re-run the same `scripts/setup.sh` with `--build <url>` from the build server (`192.168.1.91:8080`), reachable only inside the CUBRID network. `verify-sql` can also install a build per issue.

### 5. Per-skill readiness report

Close with an honest per-skill readiness summary — partial setup is expected outside the CUBRID network:

| Skill | Runnable when | Needs a build? |
| --- | --- | --- |
| `gate-resolved` | cubrid-jira + credentials present | No |
| `author-testcase` · `review-testcase` · `verify-sql` | + CTP assets + a fix-including `$HOME/CUBRID` (`--build`) + per-session `source ~/.cubrid-agent/env.sh` | Yes |

State plainly what is ready now, what is still TODO, and — for the build-dependent skills — that full one-command setup only completes inside the CUBRID network. End by pointing to `docs/setup.md` §4 for how to launch each skill.

## Channel note

- **Claude Code (plugin):** this skill and its `scripts/setup.sh` ship in the plugin; the hook quality-gates are active. `/setup-cubrid-agent` is the entrypoint.
- **Other CLIs (npx skills):** the skill and its script install, so provisioning still runs — but the Claude-Code-only hooks and any plugin-side auto-provisioning do not exist on those CLIs. Run the skill's `scripts/setup.sh` and finish Tier 3 the same way; expect no hook gates.
