# Changelog

All notable changes to cubrid-agent are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning is deferred:
until the first tagged release, the plugin resolves to its git commit SHA
(see the version note below).

## [Unreleased]

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

`plugin.json` intentionally omits `version`, so Claude Code falls back to the git
commit SHA and every commit is treated as a new version. Semantic versioning will
be pinned behind an eval gate in a later stage.
