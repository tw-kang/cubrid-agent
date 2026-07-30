---
name: setup-cubrid-agent
description: "Provision a freshly installed cubrid-agent so its skills become runnable. Runs the bundled setup.sh to lay down the $HOME machine assets (testcases and engine clones, CTP, the env file), then walks the operator through the Tier-3 steps the script can only flag -- sudo CLI installs (pandoc, gh, cubrid-jira), credentials, and sanity checks -- and ends with a per-skill readiness report. This is the manual entrypoint to run once after install; invoke it as /setup-cubrid-agent. It never writes credentials into the repo and never installs a CUBRID build on its own -- the build is issue-dependent, so it only guides the --build step. NOT for: running the pipeline skills, injecting secrets, or installing a CUBRID build unattended."
disable-model-invocation: true
---

# setup-cubrid-agent — one-time install → usable

Bring a freshly installed cubrid-agent to the "install + one setup → usable" bar. `setup.sh` handles the machine state (Tier 2) non-interactively and idempotently; this skill drives it, then completes the parts the script deliberately leaves to a human (Tier 3 — sudo installs and credentials), and reports which skills are actually runnable. Asset model and tiers: `docs/deployment.md`; decision: `.agents/adr/0003-setup-entrypoint-skill.md`.

**Manual entrypoint** (`disable-model-invocation: true`): it changes machine state (clones, sudo installs), so it runs only when the operator invokes `/setup-cubrid-agent`, never on its own.

## What it does / does NOT

**Does:** run the bundled `setup.sh`; parse its TODO lines; guide the operator through sudo CLI installs and credential setup (executing the installs with the operator's approval); run sanity checks; print a per-skill readiness report.

**Does NOT:** inject or print credentials (Tier 3 is the human's; secrets never land in the repo or a script); install a CUBRID build unattended (the build is issue-dependent — it only guides `--build`); run any pipeline skill.

## Process

### 1. Run the provisioning script

Run the `scripts/setup.sh` that ships next to this SKILL.md — it is the **canonical and only** copy (there is no repo-root wrapper; ADR-0003). Resolve it in this order:

1. `${CLAUDE_PLUGIN_ROOT}/skills/qa/setup-cubrid-agent/scripts/setup.sh` when `CLAUDE_PLUGIN_ROOT` is set (plugin channel);
2. otherwise the `scripts/setup.sh` in this skill's own directory (npx channel, or a repo checkout at `skills/qa/setup-cubrid-agent/scripts/setup.sh`).

Run it plain (no args) first: `bash <resolved-path>`. It is idempotent and non-interactive — safe to re-run. It clones the `$HOME` assets only when absent (never touches an existing clone), makes `~/.cubrid-agent/`, and writes `~/.cubrid-agent/env.sh`. It prints `OK` / `TODO` lines and a final `TODO N건` count.

### 2. Resolve the TODO lines (Tier 3 — with the operator)

Read the `TODO` lines and clear each one. Show the operator the exact command before running anything that needs `sudo`, and run it only on their approval. Reference: `docs/setup.md` §2–§3.

- **JDK (`javac`) missing** — `sudo dnf install java-1.8.0-openjdk-devel` (Debian/Ubuntu: `sudo apt install default-jdk`), then re-run `setup.sh` so it detects the JDK and rewrites `env.sh`.
- **`pandoc` missing, or reported without a jira reader/writer** — needs **>= 2.19**, and **do not use the distro package** (`dnf`/`apt` on RHEL 8 ships 2.0.6, which has neither format: writing a markdown issue body hard-fails, and reading an issue comes back empty instead of erroring on a `cubrid-jira` older than 2026-07-30). No sudo needed, and no `gh` either — a public release asset downloads unauthenticated, so this works before `gh` is installed or logged in (both of which may still be open TODOs in this same run). Drop a static build into `~/.local`, which shadows any system pandoc by `$PATH` order: `mkdir -p ~/.local && curl -fL -o /tmp/pandoc.tar.gz https://github.com/jgm/pandoc/releases/download/2.19.2/pandoc-2.19.2-linux-amd64.tar.gz && tar xzf /tmp/pandoc.tar.gz -C ~/.local --strip-components=1`. Verify the capability, not the binary: `pandoc --list-input-formats | grep -qx jira`.
- **`cubrid-jira` missing** — needs Python 3.14+ and pandoc >= 2.19; `uv tool install git+https://github.com/vimkim/cubrid-jira.git` (or `pipx install …`; never `pip install -e .`). An install older than 2026-07-29 lacks authenticated reads and the `attachment` subcommand, so the skills fail outright. Above that floor, take the latest rather than a date — two fixes landed two hours apart on 2026-07-30, so the date names both and neither. The latest buys: an old pandoc no longer blanks the body, and a 401 stops after one attempt instead of one per related issue. Either way: `uv tool upgrade cubrid-jira`.
- **`gh` missing** — the dnf/apt steps in stage2-setup §3.
- **Credentials missing** — do NOT set them for the operator; give the checklist and let them run it: `export CUBRID_JIRA_USER=… CUBRID_JIRA_PASSWORD=…` (or a `~/.netrc` `machine jira.cubrid.org`, `chmod 600`); `gh auth login` (or `GH_TOKEN`). Never echo a credential value.

After installs, **re-run `setup.sh`** and confirm the TODO count drops. CLI installs and credentials are the operator's to finish — a leftover TODO is a partial setup, not a failure (see the report).

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
