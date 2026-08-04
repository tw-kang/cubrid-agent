# cubrid-agent

Agents for the CUBRID QA development process. They drive CBRD issue state
transitions: gate Resolved issues for QA-readiness, author and verify CTP SQL
testcases against a local build, and act as the first reviewer on testcase PRs.

The repository ships through **two channels from one source**:

- **Claude Code** installs it as a **plugin** (root `.claude-plugin/`), which
  loads six skills — setup plus the five pipeline skills — and wires in the
  quality-gate hooks.
- **Other agent CLIs** (Codex, Cursor, Gemini, …) install individual skills with
  the [`skills`](https://github.com/vercel-labs/skills) CLI. This is also the only
  channel that reaches the 16 component skills, which the plugin does not load.

## Install

### Claude Code (plugin)

```bash
claude plugin marketplace add tw-kang/cubrid-agent
claude plugin install cubrid-agent@cubrid-agent
# then, once, in a Claude Code session:
/cubrid-agent:setup-cubrid-agent
```

Install registers the marketplace (`.claude-plugin/marketplace.json`) and loads
the six declared skills plus the `hooks/hooks.json` gates on the next session —
but nothing is runnable yet: the skills need `cubrid-jira`, a CTP checkout, and
(for the verify skills) a local CUBRID build that install does not provision. Run
**`/cubrid-agent:setup-cubrid-agent`** once to lay those machine assets down,
finish the credential steps, and get a per-skill readiness report.

### Staying current

Auto-update is off by default for third-party marketplaces, so an install stays on
the commit it first fetched. `setup-cubrid-agent` turns it on and pulls once; after
that an update lands about ten minutes into a session (measured: a commit pushed at
17:14 was installed at 17:52, nine minutes into the next working session — an idle
session never triggers the check). To pull one immediately:

```bash
claude plugin marketplace update cubrid-agent
claude plugin update cubrid-agent@cubrid-agent   # restart or /reload-plugins to apply
```

Re-run `/cubrid-agent:setup-cubrid-agent` after an update: it refreshes the helper
copies under `~/.cubrid-agent/bin/`, which a plugin update does not touch.

Plugin skills are namespaced, so `/cubrid-agent:<skill>` is the canonical name and
the one autocomplete offers. The bare `/<skill>` also reaches it unless another
command already claims that name.

**The plugin loads six skills, not all 22 — and the directory says which.**
`skills/qa/` holds the shipped set and nothing else: every directory there is
declared in `plugin.json`, and those six are what an install loads. `skills/in-progress/`
holds the 16 component skills, still being built; they are absent from the session,
not lazily loaded. A skill is promoted by moving it into `skills/qa/` and adding its
`plugin.json` line in the same commit. `claude plugin details cubrid-agent` prints
what an install actually loaded and its always-on token cost. To use a component
skill anyway, install it through the `skills` CLI channel below.

### Other CLIs (agent skills)

Skills keep the catalog layout `skills/<tree>/<name>/SKILL.md`, which the `skills`
CLI discovers directly from GitHub — no publish step, and both trees are found:

```bash
# one skill into one or more agents (project scope by default)
npx skills add tw-kang/cubrid-agent -s create-sql -a claude-code -a codex -a cursor

# user (global) scope
npx skills add tw-kang/cubrid-agent -g -s verify-sql

# every skill into every supported agent
npx skills add tw-kang/cubrid-agent --all

# list without installing
npx skills add tw-kang/cubrid-agent --list
```

On other CLIs the skills (including `setup-cubrid-agent` and its `scripts/setup.sh`)
install and run, so provisioning still works — but the quality-gate **hooks are
Claude-Code-only** and do not travel with the skills. Run `/setup-cubrid-agent`
(no plugin prefix: these land as ordinary personal or project skills) or its
script directly, and expect no hook gates on those CLIs.

## Skills

### Setup (manual entrypoint)

| Skill | What it does |
| --- | --- |
| `setup-cubrid-agent` | Provisions a fresh install to the "install + one setup → usable" bar — asks once, then runs `setup.sh` for the `$HOME` machine assets **and** the three required CLIs (`gh`, `pandoc`, `cubrid-jira`), resolves what it could not force, and prints a per-skill readiness report. Manual only (`/cubrid-agent:setup-cubrid-agent`). |

### Pipeline (always-on in the plugin)

| Skill | What it does |
| --- | --- |
| `gate-resolved` | Reviews a Resolved CBRD issue for QA-readiness on two axes (necessity, plannability) and bounces the un-plannable ones — posting the transition and comment on a targeted call (drafting on a batch sweep, or downgrading to a draft when a false-positive guard trips). |
| `author-testcase` | Runs the end-to-end pipeline for one Resolved issue — select, ground, author, verify, review — and opens an upstream PR (ready-for-review on a targeted call, Draft on a batch queue). |
| `review-testcase` | First-reviewer of a SQL testcase PR in three layers (convention lint, mined domain lenses, local CTP execution). |
| `create-sql` | Creates a CTP SQL testcase (`.sql` + generated `.answer`) from scratch. |
| `verify-sql` | Runs one CTP SQL testcase on a local build, judges pass/fail, and diagnoses failures. |

Together with `setup-cubrid-agent` these six cost about 2,000 tokens of always-on
context per session — measured 2026-07-31, and it grows as descriptions do, so
`claude plugin details cubrid-agent` is what prints the figure for your install.

### Component skills (`skills` CLI only)

The plugin does not load these — install one with
`npx skills add tw-kang/cubrid-agent -s <name>`. Per CTP category, a
`create-<cat>` / `verify-<cat>` pair:

`create-cci` · `verify-cci` · `create-cdc-repl` · `verify-cdc-repl` ·
`create-ha-repl` · `verify-ha-repl` · `create-ha-shell` · `verify-ha-shell` ·
`create-isolation` · `verify-isolation` · `create-jdbc` · `verify-jdbc` ·
`create-shell` · `verify-shell` · `create-unittest` · `verify-unittest`

## Requirements

- **`git`, `jq`** — used by the hook gates and skills.
- **`gh`, `cubrid-jira`, `pandoc` >= 2.19** — not optional: without them a skill
  cannot open a PR, read a CBRD issue, or write to Jira. `/cubrid-agent:setup-cubrid-agent`
  asks once and installs all three, so you normally do not install them by hand.
  Take pandoc from a static release, **not** the distro package: RHEL 8 ships 2.0.6,
  which has no `jira` reader, so a Jira write hard-fails and an issue body can come
  back **empty instead of erroring**. Check the capability, not the binary:
  `pandoc --list-input-formats | grep -qx jira`.
- **A local CUBRID build + CTP** — required by the `verify-*` skills and the
  verify stage of `author-testcase`. `/cubrid-agent:setup-cubrid-agent` provisions
  these; see also `docs/setup.md`.
- The hooks only act on CUBRID testcase PRs (`gh pr create` against
  `cubrid-testcases`); they leave every other command alone.

## Repository layout

```
.claude-plugin/    plugin.json + marketplace.json (source "./")
skills/qa/         the shipped set — 6 skills (1 setup + 5 pipeline), each one
                   declared in plugin.json
skills/in-progress/ 16 component skills, not shipped; promoted into skills/qa/
                   when done. Reachable through the skills CLI channel
hooks/hooks.json   quality-gate hook config
scripts/           hook scripts, addressed via ${CLAUDE_PLUGIN_ROOT},
                   plus check-invariants.sh (dev-only, run by CI)
docs/              design notes, ADRs, deployment (Korean, non-shipping)
```

## Versioning

`plugin.json` omits `version` for now, so Claude Code resolves the plugin to its
git commit SHA and every commit is a new version. Semantic versioning will be
pinned behind an eval gate in a later stage. See `CHANGELOG.md`.

## License

[Apache-2.0](./LICENSE).
