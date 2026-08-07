# Changelog

All notable changes to cubrid-agent are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) (see the
[Version note](#version-note) at the end of this file).

## [Unreleased]

## [1.0.3] - 2026-08-07

### Fixed

- (patch) **The TC gate reminder now speaks only in a session that did testcase work.** It reads
  state under `~/.cubrid-agent/`, not the working directory, so it used to fire in every project on
  the machine — including repositories that have nothing to do with CUBRID testcases. The two hooks
  that already recognise testcase work — the convention lint on a TC `.sql` write, and the submit
  gate on a TC pull request — now mark the session, and the reminder stays silent in sessions that
  carry no such mark. A run abandoned in an earlier session is no longer raised in an unrelated one;
  the run directory and its branch still hold the work.
- (patch) **A submitted run is recorded as submitted.** `author-testcase` now sets `submitted` in the
  run manifest once the pull request exists. Nothing wrote that field before, so the triage query in
  the setup runbook and the stop reminder both read a finished run as still in flight.
- (patch) **Stopped the TC gate reminder from firing on a standalone verify run.** A manifest that
  `verify-sql` wrote on its own carries no authoring gate that could ever close, but the Stop hook
  counted it as an unfinished run. It repeated the reminder on every stop for seven days, and named
  the run `?`, so nobody could find which one it meant. The reminder now counts only runs that
  authored something, and it names a run by its directory when the manifest carries no issue key.

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
- **A measured account of how an update arrives, in README and `docs/setup.md`.**
  Four timed deliveries landed between twenty-four seconds and nine minutes into a
  session, with no manual command. The same note states the two limits that follow
  from it. The check runs once per session, and it is rate-limited between sessions,
  so a session opened soon after your last update delivers nothing however long you
  keep it open. Both files put the two commands that pull immediately next to the note.

## Version note

Claude Code compares the `version` that `plugin.json` declares. A change therefore
reaches installed copies through a **bump**, not through a commit — push without a bump
and every installed copy stays on what it already has.

Each bump adds one dated section above, in the `## [x.y.z] - YYYY-MM-DD` form this file
already uses. That section is also the release notes of the matching GitHub Release,
word for word. Read it there before you install, or read it here after.

Which digit moves tells you what the release asks of you:

- **major** — you have to change something to keep using the plugin. The entry says what.
- **minor** — a new capability. What you already use keeps working.
- **patch** — the same thing, done more correctly.

Entries under `[Unreleased]` are tagged with the digit they claim — `- (minor) …` — so
the number of the next release is already decided when it is cut.
