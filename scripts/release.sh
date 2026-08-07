#!/bin/bash
# release.sh — this repo's versioning domain: which states may release, what the next version is,
# and the release itself.
#
#   release.sh check                   the eight state checks. exit 0 = this state may release.
#   release.sh next                    print "<version> <digit>" the next release would carry.
#   release.sh run --trigger <1|2|3>   bump on develop, merge develop into main, tag, publish.
#
# Dev-only: not a hook, never invoked by a skill. `check` runs from check-invariants.sh and CI.
#
# A change reaches an installed copy through the declared version, not through a commit, so the
# failure this script exists to prevent is a shipped change that nobody can receive or look up.
# `check` is offline. `next` computes and touches nothing. Only `run` reaches the network.
#
# SHIPPED_PATHS below is the canonical list of the shipped surface — the files whose change obliges
# a version bump. Prose points here instead of repeating the paths.
set -u

ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
[ -n "$ROOT" ] && cd "$ROOT" || { echo "release: not a git repo" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "release: jq is required." >&2; exit 1; }

# Written-then-moved files. A rewrite that fails half way must leave nothing behind: a stray
# CHANGELOG.new is an untracked file, and the next run refuses to start on an unclean tree.
NOTES=""; NEW_CHANGELOG=""; NEW_MANIFEST=""; NEW_PACKAGE=""
trap 'rm -f "$NOTES" "$NEW_CHANGELOG" "$NEW_MANIFEST" "$NEW_PACKAGE" 2>/dev/null' EXIT

SHIPPED_PATHS=(
  .claude-plugin/plugin.json
  skills/qa
  hooks
  scripts/gate-pr-submit.sh
  scripts/gate-stop.sh
  scripts/hint-missing-helper.sh
  scripts/lint-sql-tc.sh
)

MANIFEST=.claude-plugin/plugin.json
PACKAGE=package.json
CHANGELOG=CHANGELOG.md
SEMVER='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'

# ── reading the two files that carry a version ───────────────────────────────────────────────────
manifest_version() { jq -r '.version // empty' "$MANIFEST" 2>/dev/null; }
package_version()  { jq -r '.version // empty' "$PACKAGE" 2>/dev/null; }

# The body of a changelog section, its heading excluded, up to the next h2. `## Version note` has no
# bracket, so it never reads as a release but still ends the section above it.
section_body() {  # section_body "[Unreleased]" | section_body "[1.0.0]"
  awk -v h="## $1" 'index($0,h)==1 && !f {f=1; next} f && /^## / {exit} f' "$CHANGELOG"
}
released_versions() { sed -n 's/^## \[\([0-9][^]]*\)\].*/\1/p' "$CHANGELOG"; }

# An entry is a top-level bullet. Continuation lines and nested bullets are part of the entry above.
entry_lines()      { printf '%s\n' "$1" | grep '^- '; }
untagged_entries() { entry_lines "$1" | grep -vE '^- \((major|minor|patch)\) '; }
highest_digit() {   # the digit a section earns: the largest one any of its entries declared
  printf '%s\n' "$1" | grep -q '^- (major) ' && { echo major; return; }
  printf '%s\n' "$1" | grep -q '^- (minor) ' && { echo minor; return; }
  printf '%s\n' "$1" | grep -q '^- (patch) ' && { echo patch; return; }
  echo ""
}

# Every version this repo has ever declared, lowest first. A number that was declared once may sit in
# someone's cache, and a release at or below it is not seen as an update there. 1.0.1 and 1.0.2 went
# out before the rule existed and 1.0.0 is the rewrite (ADR 0007), so this is not hypothetical.
declared_versions() {
  git log -p --format= -- "$MANIFEST" 2>/dev/null \
    | sed -n 's/^+[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([0-9][^"]*\)".*/\1/p' | sort -V -u
}

bump_version() {  # bump_version <version> <digit>
  local ma mi pa
  IFS=. read -r ma mi pa <<<"$1"
  case "$2" in
    major) printf '%d.0.0\n' $((ma+1)) ;;
    minor) printf '%d.%d.0\n' "$ma" $((mi+1)) ;;
    patch) printf '%d.%d.%d\n' "$ma" "$mi" $((pa+1)) ;;
    *) return 1 ;;
  esac
}

increment_between() {  # increment_between <older> <newer> -> major|minor|patch|other
  local oa ob oc na nb nc
  IFS=. read -r oa ob oc <<<"$1"; IFS=. read -r na nb nc <<<"$2"
  # The kind of step, not its size. A release may have to skip past numbers this repo already
  # declared, and a skip is still a patch step if only the patch digit moved.
  if   [ "$na" -gt "$oa" ] && [ "$nb" -eq 0 ] && [ "$nc" -eq 0 ];              then echo major
  elif [ "$na" -eq "$oa" ] && [ "$nb" -gt "$ob" ] && [ "$nc" -eq 0 ];          then echo minor
  elif [ "$na" -eq "$oa" ] && [ "$nb" -eq "$ob" ] && [ "$nc" -gt "$oc" ];      then echo patch
  else echo other; fi
}

strip_blank_edges() {  # drop blank lines at both ends, keep the ones between
  awk 'NF { while (pending-- > 0) print ""; pending=0; started=1; print; next } started { pending++ }'
}

# ── check ────────────────────────────────────────────────────────────────────────────────────────
do_check() {
  local n_ok=0 n_bad=0 n_skip=0 skipped=""
  _ok()   { n_ok=$((n_ok+1));     printf '  ok   %d %s\n' "$1" "$2"; }
  _bad()  { n_bad=$((n_bad+1));   printf '  FAIL %d %s\n' "$1" "$2"; }
  _skip() { n_skip=$((n_skip+1)); skipped="$skipped $1"; printf '  skip %d %s\n' "$1" "$2"; }

  local v pv latest body prev inc dig tag changed _v
  v=$(manifest_version)

  if [ -n "$v" ]; then _ok 1 "plugin.json declares a version ($v)"
  else _bad 1 "plugin.json declares no version — installs would resolve to a commit SHA again"; fi

  if [[ "$v" =~ $SEMVER ]]; then _ok 2 "the declared version is semver"
  else _bad 2 "version \"$v\" is not semver X.Y.Z"; fi

  latest=$(released_versions | sed -n 1p)
  if [ -n "$v" ] && [ "$latest" = "$v" ]; then _ok 3 "the newest CHANGELOG release is the declared version"
  else _bad 3 "plugin.json says ${v:-none} but the newest CHANGELOG release is ${latest:-none}"; fi

  # A release heading without a date reads as still open, which is how one version ships twice.
  if [ -n "$v" ] && awk -v h="## [$v] - " \
       'index($0,h)==1 && $0 ~ /- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ {f=1} END {exit !f}' \
       "$CHANGELOG"; then
    _ok 4 "that heading carries an ISO date"
  else _bad 4 "the CHANGELOG heading for ${v:-the declared version} carries no ISO date"; fi

  pv=$(package_version)
  if [ -n "$v" ] && [ "$pv" = "$v" ]; then _ok 5 "package.json carries the same version"
  else _bad 5 "package.json says ${pv:-none}, plugin.json says ${v:-none}"; fi

  body=$(section_body "[Unreleased]")
  local bad_entry; bad_entry=$(untagged_entries "$body")
  if [ -z "$bad_entry" ]; then _ok 6 "every Unreleased entry declares its digit"
  else _bad 6 "an Unreleased entry declares no digit: ${bad_entry%%$'\n'*}"; fi

  # 7 needs history. Whoever changed the shipped surface owes an entry, and owes it now: judging the
  # digit at release time means reconstructing what a change meant weeks later.
  #
  # The anchor is the newest release tag this clone actually holds, not the tag of the declared
  # version. During a release the declared version has no tag yet — anchoring on it would make the
  # release fail its own check. A clone holding fewer tags falls back to an older anchor, which can
  # only over-report, never wave a change through.
  if [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = true ]; then
    _skip 7 "shallow clone: the history that would show what changed since the last release is not here"
  else
    tag=""
    for _v in $(released_versions); do
      git rev-parse -q --verify "refs/tags/v$_v" >/dev/null 2>&1 && { tag="v$_v"; break; }
    done
    if [ -z "$tag" ]; then
      _skip 7 "no release tag in this clone: there is no released point to compare the shipped surface against"
    else
      changed=$( { git diff --name-only "$tag" -- "${SHIPPED_PATHS[@]}"
                   git ls-files --others --exclude-standard -- "${SHIPPED_PATHS[@]}"; } | sort -u)
      # Two things can carry the declaration: an Unreleased entry, or a dated section newer than the
      # anchor. The second is the release in flight — its bump touched plugin.json and moved the
      # entries out of Unreleased, so without this the release would fail its own check.
      if [ -z "$changed" ]; then _ok 7 "the shipped surface is unchanged since $tag"
      elif [ -n "$(entry_lines "$body")" ]; then _ok 7 "the shipped change since $tag is declared in Unreleased"
      elif [ "$latest" != "${tag#v}" ]; then _ok 7 "the shipped change since $tag is declared in the $latest section"
      else
        _bad 7 "the shipped surface changed since $tag but nothing declares it: $(printf '%s' "$changed" | tr '\n' ' ')"
      fi
    fi
  fi

  prev=$(released_versions | sed -n 2p)
  if [ -z "$prev" ]; then
    _skip 8 "${latest:-the newest release} has no predecessor whose distance could be checked"
  else
    inc=$(increment_between "$prev" "$latest")
    dig=$(highest_digit "$(section_body "[$latest]")")
    if [ "$inc" = "$dig" ]; then _ok 8 "the $prev to $latest step is the $inc its entries declared"
    else _bad 8 "the $prev to $latest step is $inc but its highest entry declares ${dig:-nothing}"; fi
  fi

  if [ "$n_bad" -eq 0 ]; then
    printf 'release check: %d ok%s\n' "$n_ok" \
      "$([ "$n_skip" -gt 0 ] && printf ', %d skipped (%s)' "$n_skip" "${skipped# }")"
    return 0
  fi
  printf 'release check: %d ok, %d skipped, %d FAILED\n' "$n_ok" "$n_skip" "$n_bad"
  return 1
}

# ── next ─────────────────────────────────────────────────────────────────────────────────────────
do_next() {
  local v body dig next floor
  v=$(manifest_version)
  [[ "$v" =~ $SEMVER ]] || { echo "release: the declared version \"$v\" is not semver" >&2; return 1; }
  body=$(section_body "[Unreleased]")
  dig=$(highest_digit "$body")
  [ -n "$dig" ] || { echo "release: nothing to release — Unreleased carries no tagged entry" >&2; return 1; }
  next=$(bump_version "$v" "$dig") || return 1
  # Climb past anything this repo already declared, keeping the digit the entries asked for. Refusing
  # instead would leave a patch-only fix with no number to go out on, which is the release that
  # matters most.
  local floor; floor=$(declared_versions | tail -1)
  if [ -n "$floor" ] && [ "$(printf '%s\n%s\n' "$next" "$floor" | sort -V | tail -1)" = "$floor" ]; then
    next=$(bump_version "$floor" "$dig") || return 1
    echo "release: skipping past $floor, which this repo already declared" >&2
  fi
  printf '%s %s\n' "$next" "$dig"
}

# ── run ──────────────────────────────────────────────────────────────────────────────────────────
do_run() {
  local trigger="" branch checked next digit tag today body repo pr sha
  while [ $# -gt 0 ]; do
    case "$1" in
      --trigger) trigger=${2:-}; shift; [ $# -gt 0 ] && shift ;;
      *) echo "release: unknown argument \"$1\"" >&2; return 2 ;;
    esac
  done
  case "$trigger" in
    1|2|3) ;;
    *) echo "release: run needs --trigger <1|2|3>, which the release commit records" >&2; return 2 ;;
  esac

  # Everything local comes first. A release must not push what it cannot finish.
  branch=$(git rev-parse --abbrev-ref HEAD)
  [ "$branch" = develop ] || { echo "release: run from develop, not $branch" >&2; return 1; }
  [ -z "$(git status --porcelain)" ] || { echo "release: the working tree is not clean" >&2; return 1; }
  if ! checked=$(do_check); then
    printf '%s\n' "$checked" >&2
    echo "release: this state fails check, so there is nothing safe to release" >&2; return 1
  fi
  next=$(do_next) || return 1
  digit=${next#* }; next=${next%% *}; tag="v$next"
  git rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1 \
    && { echo "release: tag $tag already exists here" >&2; return 1; }
  git ls-remote --exit-code --tags origin "$tag" >/dev/null 2>&1 \
    && { echo "release: tag $tag already exists on origin" >&2; return 1; }

  today=$(date +%F)
  body=$(section_body "[Unreleased]")

  # Step 1 — the bump, pushed straight to develop. Existing installs clone that branch, so a release
  # that only reached main would never be delivered to them.
  NEW_CHANGELOG=$(mktemp); NEW_MANIFEST=$(mktemp); NEW_PACKAGE=$(mktemp)
  awk -v ver="$next" -v day="$today" '
    state==0 { print; if ($0 ~ /^## \[Unreleased\]/) state=1; next }
    state==1 && /^## / { printf "\n## [%s] - %s\n", ver, day; printf "%s", buf; print; state=2; next }
    state==1 { buf = buf $0 "\n"; next }
    { print }
    END { if (state==1) { printf "\n## [%s] - %s\n", ver, day; printf "%s", buf } }
  ' "$CHANGELOG" > "$NEW_CHANGELOG" || { echo "release: rewriting the changelog failed" >&2; return 1; }
  jq --arg v "$next" '.version = $v' "$MANIFEST" > "$NEW_MANIFEST" || return 1
  jq --arg v "$next" '.version = $v' "$PACKAGE"  > "$NEW_PACKAGE"  || return 1
  # Copy into place rather than move. `mv` would carry mktemp's 0600 onto tracked files, and git
  # records only the exec bit, so the tightened mode would survive every later commit unseen.
  if ! { cat "$NEW_CHANGELOG" > "$CHANGELOG" && cat "$NEW_MANIFEST" > "$MANIFEST" \
         && cat "$NEW_PACKAGE" > "$PACKAGE"; }; then
    git checkout -- "$CHANGELOG" "$MANIFEST" "$PACKAGE"
    echo "release: writing the bumped files failed — reverted, nothing was pushed" >&2; return 1
  fi
  rm -f "$NEW_CHANGELOG" "$NEW_MANIFEST" "$NEW_PACKAGE"
  NEW_CHANGELOG=""; NEW_MANIFEST=""; NEW_PACKAGE=""

  if ! checked=$(do_check); then
    printf '%s\n' "$checked" >&2
    git checkout -- "$CHANGELOG" "$MANIFEST" "$PACKAGE"
    echo "release: the bumped state fails check — reverted, nothing was pushed" >&2; return 1
  fi

  if ! git add -- "$CHANGELOG" "$MANIFEST" "$PACKAGE" \
     || ! git commit -qm "Release $tag (trigger $trigger)"; then
    git reset -q -- "$CHANGELOG" "$MANIFEST" "$PACKAGE" 2>/dev/null
    git checkout -- "$CHANGELOG" "$MANIFEST" "$PACKAGE"
    echo "release: committing the bump failed — reverted, nothing was pushed" >&2; return 1
  fi
  if ! git push -q origin develop; then
    echo "release: pushing develop failed. The bump commit is here but not on origin." >&2
    echo "release: push it, then open the release PR and tag $tag by hand." >&2
    return 1
  fi
  printf 'pushed %s to develop as a %s release\n' "$tag" "$digit"

  # Step 2 — develop into main, as a merge commit. A squash here would rewrite every commit and make
  # the two branches permanently diverge.
  NOTES=$(mktemp); printf '%s\n' "$body" | strip_blank_edges > "$NOTES"
  repo=$(gh repo view --json nameWithOwner -q .nameWithOwner) \
    || { echo "release: cannot read which repository this is — develop carries the bump" >&2; return 1; }
  pr=$(gh pr create --base main --head develop --title "Release $tag" --body-file "$NOTES") \
    || { echo "release: opening the release PR failed — develop carries the bump" >&2; return 1; }
  if ! gh pr merge "$pr" --merge; then
    echo "release: GitHub refused the merge. Merge it, then tag $tag on main: $pr" >&2; return 1
  fi

  # Step 3 — the tag and the notes, on the commit main now points at.
  sha=$(gh api "repos/$repo/commits/main" --jq .sha) \
    || { echo "release: cannot read what main points at. main carries the merge; tag $tag by hand" >&2; return 1; }
  if ! gh release create "$tag" --target "$sha" --title "$tag" --notes-file "$NOTES"; then
    echo "release: publishing failed. main carries the merge; tag $tag by hand" >&2; return 1
  fi
  git fetch -q origin --tags 2>/dev/null || true
  printf 'released %s\n' "$tag"
}

usage() {
  cat >&2 <<'USAGE'
usage: release.sh check                    the eight state checks; exit 0 = this state may release
       release.sh next                     print the version and digit the next release would carry
       release.sh run --trigger <1|2|3>    bump, push develop, merge into main, tag, publish
USAGE
}

case "${1:-}" in
  check) do_check ;;
  next)  do_next ;;
  run)   shift; do_run "$@" ;;
  *)     usage; exit 2 ;;
esac
