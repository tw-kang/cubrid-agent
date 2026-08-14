# Changelog

All notable changes to cubrid-agent are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) (see the
[Version note](#version-note) at the end of this file).

## [Unreleased]

### Changed

- (minor) **The preparation phase now answers itself in one call.** `author-testcase` and
  `create-sql` open with `~/.cubrid-agent/bin/scout.sh CBRD-XXXXX`, which reports in a single answer
  what used to be eight separate look-ups: which helpers, CTP, build and credentials this machine
  has, which tree the testcase belongs in and which sibling documents that area's conventions,
  whether the corpus already covers the repro (`--grep <pattern>`, because the same repro often sits
  under another name), and how far the run has got. It only reads — no writes, no network — so the
  orchestrator and the author lane can both call it at any point. When something is absent it names
  it, says what its absence costs, and stops, so a missing build or an unauthenticated `gh` shows up
  at the start of a run instead of at Verify or at the pull request.

- (minor) **The `author-testcase` lanes now hand their reports over as files.** Each lane — the
  author, the static review and the answer review — writes its report to
  `~/.cubrid-agent/CBRD-XXXXX/<lane>-<n>.md` and returns only a verdict and one line, and the
  orchestrator passes the next lane that path instead of repeating the report back into the
  conversation. Every round keeps its own file, so a run leaves its review history on disk for a
  human to read. The orchestrator also no longer watches the filesystem to learn that a lane
  finished — the lane's return is that signal.
- (minor) **The TC convention lint now judges the five shapes that break CTP's line splitter**, so a
  testcase that would silently stop running is caught on the `.sql` write instead of by a reviewer
  reading CTP's Java source. The five are a semicolon ending a header line, an odd number of
  apostrophes in an `evaluate` label, a label that does not close with an apostrophe and a semicolon,
  a prepared name never released, and a line-leading `@`, `$` or `--+` that CTP does not recognise as
  a directive. Each says what CTP does with the line and what to write instead. The submit gate now
  blocks on all five, recorded in the run manifest as `lint.header_no_semicolon`,
  `lint.evaluate_quotes`, `lint.evaluate_terminator`, `lint.prepare_released` and `lint.directives`;
  a manifest written before this release keeps passing, because an absent field is read as clean.

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
