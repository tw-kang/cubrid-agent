#!/bin/bash
# Behavioural test for check-pr-push.sh — the branch, PR-header and direct-commit rules CI enforces.
#
# Dev-only, run by check-invariants.sh. Offline: every case builds a throwaway repo carrying its own
# head-keys file and a copy of the real release.sh, so the shipped surface under test is the real one.
set -u

SRC=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)/check-pr-push.sh
RELEASE=$(dirname "$SRC")/release.sh
[ -f "$SRC" ] || { echo "test-check-pr-push: script not found at $SRC" >&2; exit 1; }

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

T_PASS=0; T_FAIL=0; FAILURES=""
note_fail() { T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    $1"; }
pass() { T_PASS=$((T_PASS+1)); }
flat() { printf '%s' "$1" | tr '\n' '|'; }

N=0
R=
fixture() {
  N=$((N+1)); local d="$T/r$N"
  case "$d" in "$T"/*) ;; *) echo "test-check-pr-push: refusing to build a fixture outside $T" >&2; exit 1 ;; esac
  mkdir -p "$d/.github" "$d/.claude-plugin" "$d/scripts" "$d/skills/qa/demo" "$d/docs"
  printf '# head keys\nCUBRIDQA-1663\n' > "$d/.github/head-keys.txt"
  printf '{"version":"1.1.0"}\n' > "$d/.claude-plugin/plugin.json"
  printf '{"version":"1.1.0"}\n' > "$d/package.json"
  printf '{"plugins":[]}\n' > "$d/.claude-plugin/marketplace.json"
  printf '# Changelog\n' > "$d/CHANGELOG.md"
  cp "$RELEASE" "$d/scripts/release.sh"
  printf 'shipped\n' > "$d/skills/qa/demo/SKILL.md"
  printf 'not shipped\n' > "$d/docs/notes.md"
  git -C "$d" init -q -b develop >/dev/null 2>&1
  git -C "$d" add -A >/dev/null && git -C "$d" commit -qm "init" >/dev/null
  R=$d
}

expect() {  # expect <dir> <expected-exit> <pattern|""> <label> -- <args...>
  local dir=$1 want=$2 pat=$3 label=$4 out rc; shift 5
  out=$(cd "$dir" && bash "$SRC" "$@" 2>&1); rc=$?
  if [ "$rc" -ne "$want" ]; then note_fail "$label: exit $rc, expected $want — output: $(flat "$out")"; return; fi
  if [ -n "$pat" ] && ! printf '%s\n' "$out" | grep -qE "$pat"; then
    note_fail "$label: no line matching /$pat/ — output: $(flat "$out")"; return
  fi
  pass
}

fixture
expect "$R" 0 "ok +release PR" "the release PR is exempt from every PR rule" \
  -- pr develop main "Release v1.2.0" false

# The exemption is the release PR's whole shape, not its title: a feature branch titled like a
# release would otherwise skip every rule.
fixture
expect "$R" 1 "FAIL +branch" "a release-titled PR from a feature branch is not exempt" \
  -- pr feat/x develop "Release v1.2.0" false

fixture
expect "$R" 0 "ok +branch" "a branch named after a head key passes" \
  -- pr cubridqa-1663-v2-structure develop "[CUBRIDQA-1663] Restructure" true
expect "$R" 1 "FAIL +branch" "a free-form branch name fails" \
  -- pr feat/install-ux develop "[CUBRIDQA-1663] Restructure" true
expect "$R" 1 "FAIL +branch" "the v1 slash form fails" \
  -- pr cubridqa-1663/v2-structure develop "[CUBRIDQA-1663] Restructure" true
expect "$R" 1 "FAIL +branch" "a number that is not a head key fails" \
  -- pr cubridqa-1700-v2-structure develop "[CUBRIDQA-1663] Restructure" true
expect "$R" 1 "FAIL +branch" "a head-key prefix of a longer number fails" \
  -- pr cubridqa-16630-x develop "[CUBRIDQA-1663] Restructure" true

fixture
expect "$R" 0 "ok +title" "a title headed by a CUBRIDQA key passes" \
  -- pr cubridqa-1663-v2-structure develop "[CUBRIDQA-1700] Check branch names in CI" true
for bad in "Check branch names in CI" "CUBRIDQA-1700 Check branch names" "[cubridqa-1700] Check branch names" \
           "[CBRD-26000] Check branch names" "[#17] Check branch names" "Check [CUBRIDQA-1700] branch names"; do
  expect "$R" 1 "FAIL +title" "title \"$bad\" fails" \
    -- pr cubridqa-1663-v2-structure develop "$bad" true
done

# A head key is a placeholder: Draft may carry it, Ready may not (cubridci#127).
fixture
expect "$R" 0 "ok +Draft PR may carry head key CUBRIDQA-1663" "a Draft PR headed by the head key passes" \
  -- pr cubridqa-1663-v2-structure develop "[CUBRIDQA-1663] Restructure" true
expect "$R" 1 "FAIL +Ready PR is still headed by head key CUBRIDQA-1663" "a Ready PR headed by the head key fails" \
  -- pr cubridqa-1663-v2-structure develop "[CUBRIDQA-1663] Restructure" false
expect "$R" 0 "ok +title is headed by \[CUBRIDQA-1700\]" "a Ready PR headed by its sub-task key passes" \
  -- pr cubridqa-1663-v2-structure develop "[CUBRIDQA-1700] Restructure" false

fixture
expect "$R" 2 "draft" "a draft flag other than true/false is refused" \
  -- pr cubridqa-1663-v2-structure develop "[CUBRIDQA-1663] Restructure" yes
expect "$R" 2 "^check-pr-push\.sh pr <head-branch>" "an unknown mode prints the pr usage" -- merge
expect "$R" 2 "^check-pr-push\.sh push <before-sha>" "an unknown mode prints the push usage" -- merge
fixture; printf 'CUBRIDQA-1663\nCUBRDQA-1664\n' > "$R/.github/head-keys.txt"
expect "$R" 2 "CUBRDQA-1664" "a malformed head-keys line is refused rather than skipped" \
  -- pr cubridqa-1663-v2-structure develop "[CUBRIDQA-1663] Restructure" true

tip() { git -C "$R" rev-parse HEAD; }
edit() { printf 'x\n' >> "$R/$1"; }
squash() { GIT_COMMITTER_NAME=GitHub GIT_COMMITTER_EMAIL=noreply@github.com git -C "$R" commit -qam "$1"; }

fixture; B=$(tip); edit skills/qa/demo/SKILL.md; git -C "$R" commit -qam "Edit a shipped skill directly"
expect "$R" 1 "FAIL +[0-9a-f]+ .*Edit a shipped skill directly" "a direct commit to the shipped surface fails" \
  -- push "$B" "$(tip)"

fixture; B=$(tip); edit docs/notes.md; git -C "$R" commit -qam "Edit a dev-only doc directly"
expect "$R" 0 "ok" "a direct commit off the shipped surface passes" -- push "$B" "$(tip)"

fixture; B=$(tip); edit skills/qa/demo/SKILL.md; squash "[CUBRIDQA-1700] Edit a shipped skill (#21)"
expect "$R" 0 "ok +[0-9a-f]+ squash-merged PR" "a GitHub squash merge to the shipped surface passes" \
  -- push "$B" "$(tip)"

fixture; B=$(tip); edit skills/qa/demo/SKILL.md; git -C "$R" commit -qam "Edit a shipped skill (#21)"
expect "$R" 1 "FAIL +[0-9a-f]+ .*Edit a shipped skill \(#21\)" "a PR suffix GitHub did not commit is not a squash merge" \
  -- push "$B" "$(tip)"

fixture; B=$(tip); edit .claude-plugin/marketplace.json; git -C "$R" commit -qam "Edit the marketplace directly"
expect "$R" 1 "FAIL +[0-9a-f]+ .*Edit the marketplace directly" "a direct commit to marketplace.json fails" \
  -- push "$B" "$(tip)"

fixture; B=$(tip); edit .claude-plugin/plugin.json; edit package.json; edit CHANGELOG.md
git -C "$R" commit -qam "Release v1.2.0 (trigger 2)"
expect "$R" 0 "ok +[0-9a-f]+ release commit" "a release commit touching exactly the bumped files passes" \
  -- push "$B" "$(tip)"

# The subject is anyone's text: a hand-made commit titled like a release is not exempt.
fixture; B=$(tip); edit .claude-plugin/plugin.json; edit package.json; edit CHANGELOG.md; edit skills/qa/demo/SKILL.md
git -C "$R" commit -qam "Release v1.2.0 (trigger 2)"
expect "$R" 1 "FAIL +[0-9a-f]+ .*Release v1\.2\.0" "a release-titled commit that also edits a skill fails" \
  -- push "$B" "$(tip)"
fixture; B=$(tip); edit .claude-plugin/plugin.json; git -C "$R" commit -qam "Release v1.2.0 (trigger 2)"
expect "$R" 1 "FAIL +[0-9a-f]+ .*Release v1\.2\.0" "a release-titled commit missing a bumped file fails" \
  -- push "$B" "$(tip)"

# One bad commit in a range of good ones still fails, and is the one named.
fixture; B=$(tip)
edit skills/qa/demo/SKILL.md; squash "[CUBRIDQA-1700] First (#21)"
edit skills/qa/demo/SKILL.md; git -C "$R" commit -qam "Sneak a skill edit in"
edit docs/notes.md; git -C "$R" commit -qam "Edit notes"
expect "$R" 1 "FAIL +[0-9a-f]+ .*Sneak a skill edit in" "a direct shipped commit inside a range fails" \
  -- push "$B" "$(tip)"

# Linear history forbids merges on develop, but if one lands, what it brings in counts.
fixture; B=$(tip)
git -C "$R" checkout -qb side; edit skills/qa/demo/SKILL.md; git -C "$R" commit -qam "Edit on a side branch"
git -C "$R" checkout -q develop; git -C "$R" merge -q --no-ff -m "Merge side" side
expect "$R" 1 "FAIL +[0-9a-f]+ .*Merge side" "a merge commit bringing in a shipped change fails" \
  -- push "$B" "$(tip)"

# A branch's first push has no before. Only the tip is the pushed change that is new for sure.
ZERO=0000000000000000000000000000000000000000
fixture; edit skills/qa/demo/SKILL.md; git -C "$R" commit -qam "Direct shipped edit"
edit docs/notes.md; squash "[CUBRIDQA-1700] Docs (#22)"
expect "$R" 0 "ok" "a first push checks the tip only" -- push "$ZERO" "$(tip)"
fixture; edit skills/qa/demo/SKILL.md; git -C "$R" commit -qam "Direct shipped edit"
expect "$R" 1 "FAIL +[0-9a-f]+ .*Direct shipped edit" "a first push whose tip is a direct shipped commit fails" \
  -- push "$ZERO" "$(tip)"

fixture
expect "$R" 2 "cannot read" "a before commit that is not in the repo is refused" \
  -- push 1111111111111111111111111111111111111111 "$(tip)"

if [ "$T_FAIL" -eq 0 ]; then
  printf 'check-pr-push: %d/%d\n' "$T_PASS" "$T_PASS"; exit 0
else
  printf 'check-pr-push: %d passed, %d FAILED%s\n' "$T_PASS" "$T_FAIL" "$FAILURES"; exit 1
fi
