# cubrid-agent

Agents for the CUBRID QA development process. They drive CBRD issue state
transitions: gate Resolved issues for QA-readiness, author and verify CTP SQL
testcases against a local build, and act as the first reviewer on testcase PRs.

The repository ships through **two channels from one source**:

- **Claude Code** installs it as a **plugin** (root `.claude-plugin/`), which
  loads the five pipeline skills and wires in the Stage-2 quality-gate hooks.
- **Other agent CLIs** (Codex, Cursor, Gemini, …) install individual skills with
  the [`skills`](https://github.com/vercel-labs/skills) CLI.

## Install

### Claude Code (plugin)

```bash
claude plugin marketplace add tw-kang/cubrid-agent
claude plugin install cubrid-agent@cubrid-agent
# then, once, in a Claude Code session:
/setup-cubrid-agent
```

Install registers the marketplace (`.claude-plugin/marketplace.json`) and loads
the skills plus the `hooks/hooks.json` gates on the next session — but nothing is
runnable yet: the skills need `cubrid-jira`, a CTP checkout, and (for the verify
skills) a local CUBRID build that install does not provision. Run
**`/setup-cubrid-agent`** once to lay those machine assets down, finish the
credential steps, and get a per-skill readiness report. The 16 component skills
under `skills/qa/` are not always-on; invoke them by name when needed.

### Other CLIs (agent skills)

Skills live in the catalog layout `skills/qa/<name>/SKILL.md`, which the `skills`
CLI discovers directly from GitHub — no publish step:

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
(or its script directly) and expect no hook gates on those CLIs.

## Skills

### Setup (manual entrypoint)

| Skill | What it does |
| --- | --- |
| `setup-cubrid-agent` | Provisions a fresh install to the "install + one setup → usable" bar — runs `setup.sh` for the `$HOME` machine assets, walks the operator through the sudo installs and credentials it can only flag, and prints a per-skill readiness report. Manual only (`/setup-cubrid-agent`). |

### Pipeline (always-on in the plugin)

| Skill | What it does |
| --- | --- |
| `gate-resolved` | Reviews a Resolved CBRD issue for QA-readiness on two axes (necessity, plannability) and bounces the un-plannable ones — posting the transition and comment on a targeted call (drafting on a batch sweep, or downgrading to a draft when a false-positive guard trips). |
| `author-testcase` | Runs the end-to-end pipeline for one Resolved issue — select, ground, author, verify, review — and opens an upstream PR (ready-for-review on a targeted call, Draft on a batch queue). |
| `review-testcase` | First-reviewer of a SQL testcase PR in three layers (convention lint, mined domain lenses, local CTP execution). |
| `create-sql` | Creates a CTP SQL testcase (`.sql` + generated `.answer`) from scratch. |
| `verify-sql` | Runs one CTP SQL testcase on a local build, judges pass/fail, and diagnoses failures. |

### Component skills (on demand)

Per CTP category, a `create-<cat>` / `verify-<cat>` pair:

`create-cci` · `verify-cci` · `create-cdc-repl` · `verify-cdc-repl` ·
`create-ha-repl` · `verify-ha-repl` · `create-ha-shell` · `verify-ha-shell` ·
`create-isolation` · `verify-isolation` · `create-jdbc` · `verify-jdbc` ·
`create-shell` · `verify-shell` · `create-unittest` · `verify-unittest`

## Requirements

- **`git`, `jq`** — used by the hook gates and skills.
- **A local CUBRID build + CTP** — required by the `verify-*` skills and the
  verify stage of `author-testcase`. `/setup-cubrid-agent` provisions these; see
  also `docs/guides/stage2-setup.md`.
- The Stage-2 hooks only act on CUBRID testcase PRs (`gh pr create` against
  `cubrid-testcases`); they leave every other command alone.

## Repository layout

```
.claude-plugin/    plugin.json + marketplace.json (source "./")
skills/qa/         22 skills (1 setup + 5 pipeline + 16 component), catalog layout
hooks/hooks.json   Stage-2 quality-gate hook config
scripts/           hook scripts, addressed via ${CLAUDE_PLUGIN_ROOT}
docs/              design notes, ADRs, deployment (Korean, non-shipping)
```

## Versioning

`plugin.json` omits `version` for now, so Claude Code resolves the plugin to its
git commit SHA and every commit is a new version. Semantic versioning will be
pinned behind an eval gate in a later stage. See `CHANGELOG.md`.

## License

[Apache-2.0](./LICENSE).
