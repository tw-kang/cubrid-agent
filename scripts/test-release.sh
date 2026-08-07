#!/bin/bash
# Behavioural test for release.sh — the versioning domain: `check`, `next` and `run`.
#
# Dev-only, run by check-invariants.sh. Offline: every case builds a throwaway repo in a temp dir,
# `origin` is a local bare repo, and `gh` is a stub that records what it was asked to do. Nothing
# here can reach GitHub whether or not the script is correct.
#
# What it pins, in the three shapes a release can go wrong:
#   check — each of the eight state checks fails on the violation it names (a fixture may trip a
#           neighbour too, so every assertion names the FAIL number it expects),
#   next  — the digit that wins is the highest one declared, applied to the current version,
#   run   — a release refuses to start from a state it cannot finish, and when it does start it
#           bumps, pushes, merges, tags and publishes in that order with those arguments.
set -u

SRC=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)/release.sh
[ -f "$SRC" ] || { echo "test-release: script not found at $SRC" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "test-release: jq is required." >&2; exit 1; }

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
TODAY=$(date +%F)

T_PASS=0; T_FAIL=0; FAILURES=""
note_fail() { T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    $1"; }
pass() { T_PASS=$((T_PASS+1)); }
flat() { printf '%s' "$1" | tr '\n' '|'; }

# ── a repo in a releasable state at 1.0.0 ────────────────────────────────────────────────────────
# Every case starts here and breaks as little as it can, so a failing check names the violation the
# case is about rather than an unrelated one. The builders set $R rather than printing
# it: a case that shares a directory with the case before it proves nothing about either.
N=0
R=
fixture() {
  N=$((N+1)); local d="$T/r$N"
  # A fixture path that escaped $T once put a git repo inside this one, and the `git -C` calls below
  # then walked up into the real repo and committed to it. Refuse before creating anything.
  case "$d" in "$T"/*) ;; *) echo "test-release: refusing to build a fixture outside $T" >&2; exit 1 ;; esac
  mkdir -p "$d/.claude-plugin" "$d/skills/qa/demo" "$d/hooks" "$d/scripts"
  printf '{\n  "name": "cubrid-agent",\n  "version": "1.0.0"\n}\n' > "$d/.claude-plugin/plugin.json"
  printf '{\n  "name": "cubrid-agent",\n  "version": "1.0.0"\n}\n' > "$d/package.json"
  cat > "$d/CHANGELOG.md" <<'MD'
# Changelog

All notable changes are documented here (see the version note at the end).

## [Unreleased]

## [1.0.0] - 2026-08-06

### Changed

- **Repackaged as a plugin.** The repository root is now a plugin.

## Version note

A change reaches installed copies through a bump, not through a commit.
MD
  printf 'shipped skill body\n' > "$d/skills/qa/demo/SKILL.md"
  printf '{"hooks":{}}\n' > "$d/hooks/hooks.json"
  for s in gate-pr-submit gate-stop hint-missing-helper lint-sql-tc; do
    printf '#!/bin/bash\n:\n' > "$d/scripts/$s.sh"
  done
  printf 'dev-only, not shipped\n' > "$d/scripts/check-invariants.sh"
  git -C "$d" init -q -b develop >/dev/null 2>&1
  git -C "$d" add -A >/dev/null && git -C "$d" commit -qm "init" >/dev/null
  R=$d
}

# Replace the changelog body from the Unreleased heading down, keeping the file's head.
set_changelog() {  # set_changelog <dir>  (body on stdin)
  { printf '# Changelog\n\nAll notable changes are documented here (see the version note at the end).\n\n'
    cat
    printf '\n## Version note\n\nA change reaches installed copies through a bump.\n'
  } > "$1/CHANGELOG.md"
}

set_version() {  # set_version <dir> <manifest-version> [package-version]
  jq --arg v "$2" '.version = $v' "$1/.claude-plugin/plugin.json" > "$1/.p" && mv "$1/.p" "$1/.claude-plugin/plugin.json"
  jq --arg v "${3:-$2}" '.version = $v' "$1/package.json" > "$1/.p" && mv "$1/.p" "$1/package.json"
}

expect_check() {  # expect_check <dir> <expected-exit> <pattern|""> <label>
  local out rc
  out=$(cd "$1" && bash "$SRC" check 2>&1); rc=$?
  if [ "$rc" -ne "$2" ]; then
    note_fail "$4: exit $rc, expected $2 — output: $(flat "$out")"; return
  fi
  if [ -n "$3" ] && ! printf '%s\n' "$out" | grep -qE "$3"; then
    note_fail "$4: no line matching /$3/ — output: $(flat "$out")"; return
  fi
  pass
}

expect_next() {  # expect_next <dir> <expected-stdout|""> <expected-exit> <label>
  local out rc
  out=$(cd "$1" && bash "$SRC" next 2>/dev/null); rc=$?
  if [ "$rc" -ne "$3" ]; then note_fail "$4: exit $rc, expected $3 (stdout: $(flat "$out"))"; return; fi
  if [ -n "$2" ] && [ "$out" != "$2" ]; then note_fail "$4: got \"$out\", expected \"$2\""; return; fi
  pass
}

# ── check: the clean state passes ────────────────────────────────────────────────────────────────
fixture
expect_check "$R" 0 "" "a releasable state passes all eight checks"
expect_check "$R" 0 "skip +7" "check 7 skips when no release tag exists to compare against"
expect_check "$R" 0 "skip +8" "check 8 skips for a first release with no predecessor"

# ── check 1: the version must be declared ────────────────────────────────────────────────────────
fixture; jq 'del(.version)' "$R/.claude-plugin/plugin.json" > "$R/.p" && mv "$R/.p" "$R/.claude-plugin/plugin.json"
expect_check "$R" 1 "FAIL +1" "an undeclared version fails check 1"

# ── check 2: semver, and only semver ─────────────────────────────────────────────────────────────
for bad in 1.2.3.4 01.0.0 1.0.0-beta 1.0 v1.0.0; do
  fixture; set_version "$R" "$bad"
  expect_check "$R" 1 "FAIL +2" "version \"$bad\" fails check 2"
done

# ── check 3: the declared version is the newest dated release ────────────────────────────────────
fixture; set_version "$R" 1.1.0
expect_check "$R" 1 "FAIL +3" "a version ahead of the changelog fails check 3"

# ── check 4: that heading carries an ISO date ────────────────────────────────────────────────────
fixture; set_changelog "$R" <<'MD'
## [Unreleased]

## [1.0.0]

### Changed

- **Repackaged as a plugin.** Text.
MD
expect_check "$R" 1 "FAIL +4" "an undated release heading fails check 4"

fixture; set_changelog "$R" <<'MD'
## [Unreleased]

## [1.0.0] - 2026-8-6

### Changed

- **Repackaged as a plugin.** Text.
MD
expect_check "$R" 1 "FAIL +4" "a non-ISO date fails check 4"

# ── check 5: package.json carries the same version ───────────────────────────────────────────────
fixture; set_version "$R" 1.0.0 0.0.0
expect_check "$R" 1 "FAIL +5" "a package.json that drifted fails check 5"

# ── check 6: every Unreleased entry declares its digit ───────────────────────────────────────────
fixture; set_changelog "$R" <<'MD'
## [Unreleased]

### Changed

- **Untagged entry.** Nobody said what digit this earns.

## [1.0.0] - 2026-08-06

### Changed

- **Repackaged as a plugin.** Text.
MD
expect_check "$R" 1 "FAIL +6" "an Unreleased entry without a digit tag fails check 6"

fixture; set_changelog "$R" <<'MD'
## [Unreleased]

### Changed

- (patch) **Tagged entry.** This one says what it earns.
  A continuation line is not an entry.
  - a nested bullet is not an entry either

## [1.0.0] - 2026-08-06

### Changed

- **Repackaged as a plugin.** Text.
MD
expect_check "$R" 0 "ok +6" "a tagged entry passes check 6, and continuations are not entries"

# ── check 7: a changed shipped surface needs an Unreleased entry ──────────────────────────────────
fixture; git -C "$R" tag v1.0.0
printf 'edited after the release\n' >> "$R/skills/qa/demo/SKILL.md"
git -C "$R" commit -qam "change a shipped skill"
expect_check "$R" 1 "FAIL +7" "a shipped change with an empty Unreleased fails check 7"

# The same edit, still uncommitted: the check runs before the commit, so it must see the worktree.
fixture; git -C "$R" tag v1.0.0
printf 'edited but not committed\n' >> "$R/skills/qa/demo/SKILL.md"
expect_check "$R" 1 "FAIL +7" "an uncommitted shipped change also fails check 7"

# A new file under the shipped surface is a shipped change even before it is tracked.
fixture; git -C "$R" tag v1.0.0
mkdir -p "$R/skills/qa/newskill"; printf 'new\n' > "$R/skills/qa/newskill/SKILL.md"
expect_check "$R" 1 "FAIL +7" "an untracked file under the shipped surface fails check 7"

# Mid-release the declared version has no tag yet, so the anchor falls back to the newest tag the
# clone holds. The bump itself changed plugin.json and emptied Unreleased, so check 7 must read the
# new dated section as the declaration — otherwise every release fails its own check and reverts.
fixture; set_version "$R" 1.1.0; set_changelog "$R" <<'MD'
## [Unreleased]

## [1.1.0] - 2026-08-06

### Changed

- (minor) **A new skill.** Text.

## [1.0.0] - 2026-08-05

### Changed

- **Repackaged as a plugin.** Text.
MD
git -C "$R" add -A >/dev/null && git -C "$R" commit -qm "bump" >/dev/null
git -C "$R" tag v1.0.0 HEAD~1
expect_check "$R" 0 "ok +7 .*declared in the 1\\.1\\.0 section" "check 7 reads a newer dated section as the declaration"

# With no release tag at all there is nothing to compare against, and that is not the operator's fault.
fixture
expect_check "$R" 0 "skip +7 no release tag" "check 7 skips when no release tag exists at all"

# CI checks out shallow. The check that enforces the declaration must say it cannot judge, and it
# must say so before it looks for a tag — a shallow clone has neither the history nor the tags.
fixture; git -C "$R" tag v1.0.0
if git clone -q --depth 1 "file://$R" "$R.shallow" 2>/dev/null; then
  expect_check "$R.shallow" 0 "skip +7 shallow" "check 7 skips in a shallow clone and says why"
else
  note_fail "check 7 in a shallow clone: could not build the shallow fixture"
fi

# Outside the shipped surface, no entry is owed.
fixture; git -C "$R" tag v1.0.0
printf 'dev-only edit\n' >> "$R/scripts/check-invariants.sh"
git -C "$R" commit -qam "change a dev-only script"
expect_check "$R" 0 "ok +7" "a change outside the shipped surface passes check 7"

# With an entry present, the same shipped change is fine.
fixture; git -C "$R" tag v1.0.0
printf 'edited after the release\n' >> "$R/skills/qa/demo/SKILL.md"
set_changelog "$R" <<'MD'
## [Unreleased]

### Changed

- (patch) **Corrected the demo skill.** Text.

## [1.0.0] - 2026-08-06

### Changed

- **Repackaged as a plugin.** Text.
MD
git -C "$R" commit -qam "change a shipped skill and declare it"
expect_check "$R" 0 "ok +7" "a declared shipped change passes check 7"

# ── check 8: the increment matches the highest digit the section declared ─────────────────────────
fixture; set_version "$R" 1.1.0; set_changelog "$R" <<'MD'
## [Unreleased]

## [1.1.0] - 2026-08-06

### Changed

- (patch) **A correction.** Text.

## [1.0.0] - 2026-08-05

### Changed

- **Repackaged as a plugin.** Text.
MD
expect_check "$R" 1 "FAIL +8" "a minor bump carrying only patch entries fails check 8"

fixture; set_version "$R" 1.1.0; set_changelog "$R" <<'MD'
## [Unreleased]

## [1.1.0] - 2026-08-06

### Added

- (minor) **A new skill.** Text.
- (patch) **A correction that rode along.** Text.

## [1.0.0] - 2026-08-05

### Changed

- **Repackaged as a plugin.** Text.
MD
expect_check "$R" 0 "ok +8" "a minor bump whose highest entry is minor passes check 8"

fixture; set_version "$R" 2.0.0; set_changelog "$R" <<'MD'
## [Unreleased]

## [2.0.0] - 2026-08-06

### Changed

- (major) **Renamed a skill.** Text.

## [1.0.0] - 2026-08-05

### Changed

- **Repackaged as a plugin.** Text.
MD
expect_check "$R" 0 "ok +8" "a major bump whose highest entry is major passes check 8"

# ── next: the highest declared digit wins, applied to the current version ────────────────────────
next_fixture() {  # next_fixture <version> <entry-lines...>
  local v=$1; shift
  fixture; set_version "$R" "$v"
  { printf '## [Unreleased]\n\n### Changed\n\n'
    printf '%s\n' "$@"
    printf '\n## [%s] - 2026-08-06\n\n### Changed\n\n- **Text.** Text.\n' "$v"
  } | set_changelog "$R"
}
next_fixture 1.0.0 '- (patch) **A.** t'; expect_next "$R" "1.0.1 patch" 0 "patch entries produce a patch bump"
next_fixture 1.0.0 '- (minor) **A.** t'; expect_next "$R" "1.1.0 minor" 0 "minor entries produce a minor bump"
next_fixture 1.0.0 '- (major) **A.** t'; expect_next "$R" "2.0.0 major" 0 "major entries produce a major bump"
next_fixture 1.0.0 '- (patch) **A.** t' '- (major) **B.** t' '- (minor) **C.** t'
expect_next "$R" "2.0.0 major" 0 "the highest digit in a mixed section wins"
next_fixture 1.2.3 '- (minor) **A.** t'; expect_next "$R" "1.3.0 minor" 0 "a minor bump zeroes the patch digit"
next_fixture 1.2.3 '- (major) **A.** t'; expect_next "$R" "2.0.0 major" 0 "a major bump zeroes the rest"
next_fixture 9.9.9 '- (patch) **A.** t'; expect_next "$R" "9.9.10 patch" 0 "the patch digit is a number, not a character"
fixture; expect_next "$R" "" 1 "an empty Unreleased has nothing to release"

# A number this repo declared once may still sit in someone's cache, so a later release must climb
# past it. Here history declares 1.0.2 and the file says 1.0.0 — the patch bump would land on 1.0.1.
next_fixture 1.0.2 '- (patch) **A.** t'
git -C "$R" commit -qam "declare 1.0.2" >/dev/null
set_version "$R" 1.0.0
expect_next "$R" "1.0.3 patch" 0 "a bump climbs past a version already declared, keeping its digit"
_out=$(cd "$R" && bash "$SRC" next 2>&1); printf '%s\n' "$_out" | grep -q 'skipping past 1\.0\.2' && pass \
  || note_fail "the skip says which version it climbed past: $(flat "$_out")"

# The skip must survive check 8, or the release it produced cannot pass its own state check.
fixture; set_version "$R" 1.0.3; set_changelog "$R" <<'MD'
## [Unreleased]

## [1.0.3] - 2026-08-07

### Fixed

- (patch) **A correction.** Text.

## [1.0.0] - 2026-08-06

### Changed

- **Text.** Text.
MD
expect_check "$R" 0 "ok +8" "check 8 reads a skip as the step its entries declared"

# ── run: the world it talks to ───────────────────────────────────────────────────────────────────
# `origin` is a real local bare repo, so the push is real and observable. `gh` is a stub: it records
# every call and answers the four questions release.sh asks it.
STUB="$T/bin"; mkdir -p "$STUB"
cat > "$STUB/gh" <<'STUBSCRIPT'
#!/bin/bash
printf '%s\n' "$*" >> "$GH_LOG"
_prev=""
for a in "$@"; do
  case "$_prev" in --notes-file) cat "$a" > "$GH_NOTES" ;; esac
  _prev=$a
done
case "$1" in
  repo)    printf 'testowner/testrepo\n' ;;
  pr)      case "$2" in
             create) printf 'https://github.com/testowner/testrepo/pull/7\n' ;;
             merge)  [ -n "${GH_MERGE_FAILS:-}" ] && { echo "Pull request is not mergeable" >&2; exit 1; }; exit 0 ;;
           esac ;;
  api)     printf '%s\n' "${GH_MAIN_SHA:-1111111111111111111111111111111111111111}" ;;
  release) [ -n "${GH_RELEASE_FAILS:-}" ] && { echo "release failed" >&2; exit 1; }
           printf 'https://github.com/testowner/testrepo/releases/tag/%s\n' "$3" ;;
esac
exit 0
STUBSCRIPT
chmod +x "$STUB/gh"
export PATH="$STUB:$PATH"

run_fixture() {  # run_fixture [entry-line] — a repo with an origin and one tagged Unreleased entry
  fixture
  local d=$R
  set_changelog "$d" <<MD
## [Unreleased]

### Changed

- ${1:-(minor) **A new skill.** It does a new thing.}

## [1.0.0] - 2026-08-06

### Changed

- **Repackaged as a plugin.** Text.
MD
  git -C "$d" commit -qam "declare the change" >/dev/null
  git -C "$d" tag v1.0.0 HEAD~1
  git init -q --bare "$d.origin" >/dev/null
  git -C "$d" remote add origin "$d.origin"
  git -C "$d" push -q -u origin develop 2>/dev/null
}

run_release() {  # run_release <dir> [env assignments...] — sets $OUT and $RC in the caller
  local d=$1; shift
  export GH_LOG="$d.gh.log" GH_NOTES="$d.gh.notes"
  : > "$GH_LOG"
  OUT=$( (cd "$d" && env "$@" bash "$SRC" run --trigger 2) 2>&1 ); RC=$?
}

# happy path
run_fixture
# `mv` from a mktemp file would tighten these to 0600, and git records only the exec bit, so the
# change would never show in a diff. Capture what they were before the release rewrites them.
MODES_BEFORE=$(cd "$R" && stat -c '%n %a' CHANGELOG.md .claude-plugin/plugin.json package.json)
run_release "$R"
[ "$RC" -eq 0 ] && pass || note_fail "a release from a clean state succeeds: exit $RC — $(flat "$OUT")"

grep -q "^## \[1\.1\.0\] - $TODAY\$" "$R/CHANGELOG.md" && pass \
  || note_fail "the release writes a dated heading: no \"## [1.1.0] - $TODAY\" in the changelog"

_unrel=$(awk '/^## \[Unreleased\]/{f=1;next} /^## /{if(f)exit} f' "$R/CHANGELOG.md" | grep -c '^- ')
[ "$_unrel" -eq 0 ] && pass || note_fail "the release empties Unreleased: $_unrel entries left behind"

grep -q '^- (minor) \*\*A new skill\.\*\*' "$R/CHANGELOG.md" && pass \
  || note_fail "the entry moves into the dated section: it is gone from the changelog entirely"

[ "$(jq -r .version "$R/.claude-plugin/plugin.json")" = 1.1.0 ] && pass \
  || note_fail "plugin.json carries the new version: got $(jq -r .version "$R/.claude-plugin/plugin.json")"
[ "$(jq -r .version "$R/package.json")" = 1.1.0 ] && pass \
  || note_fail "package.json carries the new version: got $(jq -r .version "$R/package.json")"

# The bump reaches origin/develop: existing installs clone that branch, so a release that only
# tagged main would never be delivered to them.
[ "$(git -C "$R.origin" rev-parse develop)" = "$(git -C "$R" rev-parse develop)" ] && pass \
  || note_fail "the bump commit is pushed to origin/develop: origin is behind"
git -C "$R" log -1 --format=%s | grep -q '^Release v1\.1\.0 (trigger 2)$' && pass \
  || note_fail "the release commit names the version and the trigger: got \"$(git -C "$R" log -1 --format=%s)\""

grep -q '^pr create --base main --head develop --title Release v1\.1\.0' "$R.gh.log" && pass \
  || note_fail "the release opens a develop->main PR titled for the version: $(flat "$(cat "$R.gh.log")")"
grep -qE '^pr merge .* --merge( |$)' "$R.gh.log" && pass \
  || note_fail "the release PR is merged with a merge commit, not squashed: $(flat "$(cat "$R.gh.log")")"
grep -q -- '--squash' "$R.gh.log" && note_fail "the release PR must not be squashed: --squash was passed" || pass
grep -q '^release create v1\.1\.0 --target 1111111111111111111111111111111111111111' "$R.gh.log" && pass \
  || note_fail "the tag is created on the merge commit main now points at: $(flat "$(cat "$R.gh.log")")"

# The release notes are the changelog section verbatim — that is the whole point of writing the
# entry at change time.
grep -q '^- (minor) \*\*A new skill\.\*\* It does a new thing\.$' "$R.gh.notes" && pass \
  || note_fail "the release notes are the section body: got $(flat "$(cat "$R.gh.notes" 2>/dev/null)")"
grep -q '^## \[1\.1\.0\]' "$R.gh.notes" 2>/dev/null \
  && note_fail "the release notes must not repeat the heading GitHub already shows" || pass

MODES_AFTER=$(cd "$R" && stat -c '%n %a' CHANGELOG.md .claude-plugin/plugin.json package.json)
[ "$MODES_BEFORE" = "$MODES_AFTER" ] && pass \
  || note_fail "the release leaves the file modes it found: $(flat "$MODES_BEFORE") became $(flat "$MODES_AFTER")"

# order matters: a tag that appears before the merge points at a commit main does not have
_order=$(grep -nE '^(pr create|pr merge|release create)' "$R.gh.log" | cut -d: -f2 | cut -d' ' -f1-2 | tr '\n' ',')
[ "$_order" = "pr create,pr merge,release create," ] && pass \
  || note_fail "the release runs PR, merge, then publish, in that order: got $_order"

# ── run: the states it must refuse, before it changes anything ───────────────────────────────────
refuses() {  # refuses <dir> <pattern> <label>
  local head_before; head_before=$(git -C "$1" rev-parse HEAD)
  run_release "$1"; local out=$OUT
  if [ "$RC" -eq 0 ]; then note_fail "$3: it went ahead (exit 0)"; return; fi
  if ! printf '%s\n' "$out" | grep -qE "$2"; then
    note_fail "$3: refused but said \"$(flat "$out")\", expected /$2/"; return
  fi
  [ -s "$1.gh.log" ] && { note_fail "$3: refused only after calling gh — $(flat "$(cat "$1.gh.log")")"; return; }
  # A refusal that already rewrote or committed something is not a refusal. A half-written file is
  # worse than either: it is untracked, so it fails the clean-tree check on every later run.
  [ "$(git -C "$1" rev-parse HEAD)" = "$head_before" ] || { note_fail "$3: refused after committing"; return; }
  git -C "$1" diff --quiet HEAD -- CHANGELOG.md .claude-plugin/plugin.json package.json \
    || { note_fail "$3: refused after rewriting the changelog or a manifest"; return; }
  ls "$1"/*.new "$1"/.claude-plugin/*.new >/dev/null 2>&1 \
    && { note_fail "$3: refused but left a half-written file behind"; return; }
  pass
}

run_fixture; printf 'uncommitted\n' >> "$R/README.md"
refuses "$R" "clean|uncommitted" "a dirty working tree stops the release"

run_fixture; git -C "$R" checkout -q -b cubridqa-1508/wip
refuses "$R" "develop" "a release from another branch stops"

fixture; git init -q --bare "$R.origin" >/dev/null; git -C "$R" remote add origin "$R.origin"; git -C "$R" push -q -u origin develop 2>/dev/null
refuses "$R" "nothing to release|Unreleased" "an empty Unreleased stops the release"

run_fixture '(minor) **A new skill.** Text.'; git -C "$R" tag v1.1.0
refuses "$R" "v1\.1\.0" "an existing tag for the next version stops the release"

run_fixture; set_version "$R" 1.0.0 0.0.0; git -C "$R" commit -qam "drift package.json" >/dev/null
refuses "$R" "check" "a state that fails check stops the release"

# A trigger is what the release commit records, so the run cannot start without one.
run_fixture
export GH_LOG="$R.gh.log" GH_NOTES="$R.gh.notes"; : > "$GH_LOG"
_out=$(cd "$R" && bash "$SRC" run 2>&1); _rc=$?
{ [ "$_rc" -ne 0 ] && printf '%s\n' "$_out" | grep -qE 'trigger'; } && pass \
  || note_fail "run without --trigger stops: exit $_rc — $(flat "$_out")"
_out=$(cd "$R" && bash "$SRC" run --trigger 9 2>&1); _rc=$?
{ [ "$_rc" -ne 0 ] && printf '%s\n' "$_out" | grep -qE 'trigger'; } && pass \
  || note_fail "run with an unknown trigger stops: exit $_rc — $(flat "$_out")"

# ── run: a merge the repository refuses leaves no tag behind ─────────────────────────────────────
run_fixture
run_release "$R" GH_MERGE_FAILS=1
[ "$RC" -ne 0 ] && pass || note_fail "a blocked merge fails the release: exit 0"
grep -q '^release create' "$R.gh.log" \
  && note_fail "a blocked merge must not publish: release create was called anyway" || pass
printf '%s\n' "$OUT" | grep -q 'https://github.com/testowner/testrepo/pull/7' && pass \
  || note_fail "a blocked merge reports the PR to finish by hand: $(flat "$OUT")"

# ── run: a commit that fails leaves nothing rewritten and nothing staged ─────────────────────────
# A repo-local pre-commit hook is the one way to make `git commit` fail on demand. Without the revert
# the bumped files stay rewritten AND staged, and every later run refuses on "not clean" without
# naming why.
run_fixture
printf '#!/bin/sh\nexit 1\n' > "$R/.git/hooks/pre-commit"; chmod +x "$R/.git/hooks/pre-commit"
run_release "$R"
[ "$RC" -ne 0 ] && pass || note_fail "a rejected commit fails the release: exit 0"
printf '%s\n' "$OUT" | grep -q 'committing the bump failed' && pass \
  || note_fail "a rejected commit says so: $(flat "$OUT")"
git -C "$R" diff --quiet HEAD -- CHANGELOG.md .claude-plugin/plugin.json package.json && pass \
  || note_fail "a rejected commit is reverted: the bumped files are still rewritten"
[ -z "$(git -C "$R" diff --cached --name-only)" ] && pass \
  || note_fail "a rejected commit leaves nothing staged: $(git -C "$R" diff --cached --name-only | tr '\n' ' ')"
[ -s "$R.gh.log" ] && note_fail "a rejected commit must not reach gh" || pass

# ── run: a publish that fails leaves main merged and the tag missing ──────────────────────────────
# This is the worst state the script can reach, so it must name it rather than exit quietly.
run_fixture
run_release "$R" GH_RELEASE_FAILS=1 GH_MAIN_SHA=2222222222222222222222222222222222222222
[ "$RC" -ne 0 ] && pass || note_fail "a failed publish fails the release: exit 0"
printf '%s\n' "$OUT" | grep -q 'tag v1\.1\.0 by hand' && pass \
  || note_fail "a failed publish says main carries the merge and the tag is owed: $(flat "$OUT")"
grep -q '^release create v1\.1\.0 --target 2222222222222222222222222222222222222222' "$R.gh.log" \
  && pass || note_fail "the tag targets the sha main reports, not a guess: $(flat "$(cat "$R.gh.log")")"

# ── run: a tag that exists only on origin still stops the release ─────────────────────────────────
run_fixture
git -C "$R" tag v1.1.0 && git -C "$R" push -q origin v1.1.0 && git -C "$R" tag -d v1.1.0 >/dev/null
refuses "$R" "v1\.1\.0" "a tag that exists only on origin stops the release"

# ── usage ────────────────────────────────────────────────────────────────────────────────────────
fixture; _out=$(cd "$R" && bash "$SRC" 2>&1); _rc=$?
{ [ "$_rc" -ne 0 ] && printf '%s\n' "$_out" | grep -q 'check'; } && pass \
  || note_fail "no mode prints usage and fails: exit $_rc — $(flat "$_out")"
fixture; _out=$(cd "$R" && bash "$SRC" publish 2>&1); _rc=$?
[ "$_rc" -ne 0 ] && pass || note_fail "an unknown mode fails instead of guessing"

if [ "$T_FAIL" -eq 0 ]; then
  printf 'release: %d/%d\n' "$T_PASS" "$T_PASS"
  exit 0
else
  printf 'release: %d passed, %d FAILED%s\n' "$T_PASS" "$T_FAIL" "$FAILURES"
  exit 1
fi
