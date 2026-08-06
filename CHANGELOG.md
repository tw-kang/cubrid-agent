# Changelog

All notable changes to cubrid-agent are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) (see the version note below).

## [Unreleased]

## [1.0.1] - 2026-08-06

### Changed

- **Recorded what a release delivery actually costs.** `1.0.0` reached a clean install
  twenty-four seconds into a session with no manual command, so README and
  `docs/setup.md` now give three measurements instead of two and drop the hedge about
  the pre-1.0.0 scheme. This release is also the measurement of a version *bump*
  arriving, which `1.0.0` alone could not show.

## [1.0.0] - 2026-08-06

### Rollout stage

This release is **Stage 2 — team-internal rollout**: teammates install the plugin and invoke the
skills by hand, and every Jira or GitHub write is gated on that human invocation. Unattended
operation — triggers, cron, pod execution — is not in this release. What the stages are, which one
comes next, and the history of getting here live in CUBRIDQA-1425; this file records only where the
released version stands.

### Changed

- **Repackaged as a Claude Code plugin (dual channel).** The repository root is
  now a plugin (`.claude-plugin/plugin.json`) and a self-referencing marketplace
  (`.claude-plugin/marketplace.json`, `source: "./"`). Claude Code installs it as
  a plugin; other agent CLIs install individual skills with `npx skills add`.
- **Absorbed the component skills.** The 18 CUBRID component testcase skills
  (previously the external `tw-kang/skills` repo, wired in by clone + symlink)
  now live under `skills/qa/`, imported with full git history.
- **Renamed skills to an action-oriented convention.** `cubrid-<cat>-tc-create` /
  `cubrid-<cat>-tc-verify` became `create-<cat>` / `verify-<cat>` (underscores
  corrected: `cdc_repl` → `cdc-repl`, `ha_repl` → `ha-repl`, `ha_shell` →
  `ha-shell`). The three orchestrators were renamed `resolve-gate` →
  `gate-resolved`, `tc-author` → `author-testcase`, `tc-reviewer` →
  `review-testcase`.
- **Declared six skills in the plugin.** `plugin.json` `skills[]` registers the
  pipeline five — `gate-resolved`, `author-testcase`, `review-testcase`,
  `create-sql`, `verify-sql` — plus the `setup-cubrid-agent` entrypoint. The other
  16 stay on disk under `skills/qa/` but the plugin does not load them: the default
  `skills/` scan does not recurse into `skills/qa/`, so only declared paths load.
  Reach those 16 through the `skills` CLI channel.
- **Ported the hook gates to plugin form.** The three quality-gate hooks
  moved from `.claude/settings.json` + `.claude/hooks/` to `hooks/hooks.json` +
  `scripts/`, addressed with `${CLAUDE_PLUGIN_ROOT}`.

### Added

- At least three skill-creator evals for each promoted skill.

### Version note

This file is the canonical statement of the versioning policy; other docs link here.

`plugin.json` declares `version` from 1.0.0 on. Claude Code compares the declared
version, so **a change reaches installed copies through a bump, not through a
commit** — push without a bump and the fleet stays on what it has. Every bump gets
its own dated heading above, in the `## [x.y.z] - YYYY-MM-DD` form this file already
follows.

What earns which digit is not settled yet — that is an open interview
(CUBRIDQA-1491). Until it is, treat any change a teammate would receive as a patch
bump.
