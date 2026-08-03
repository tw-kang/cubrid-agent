#!/bin/bash
# Decide where a testcase may be authored, and print that path. Installed to ~/.cubrid-agent/bin/.
#
# Why this is a script (DP6): "never build on a human's checked-out branch" was prose in
# author-testcase, and prose cannot see a working tree. On the machines that matter the default clone
# IS a human's workspace — this one sits on `feature/meta/description` with changes staged — and an
# agent running `git checkout -b` there drags that work onto a branch it does not own.
#
# What it does NOT do: copy anything. A worktree shares the object store and moves only the working
# directory, so isolating costs a checkout, not a clone. That is what the pipeline had been doing by
# hand before this existed.
#
# Usage: prepare-tc-workspace.sh CBRD-XXXXX
#   stdout: the single path the caller must use as $CUBRID_TESTCASES from here on.
#   stderr: what it decided and why.
set -u

USAGE='prepare-tc-workspace.sh CBRD-XXXXX'
KEY=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) printf '%s\n' "$USAGE"; exit 0 ;;
    -*)        printf 'prepare-tc-workspace: unknown option: %s\n%s\n  If that is a documented flag, this installed copy is stale (the plugin updated, ~/.cubrid-agent/bin did not) — run /setup-cubrid-agent to refresh it.\n' "$1" "$USAGE" >&2; exit 1 ;;
    *)         KEY=$(printf '%s' "$1" | grep -oiE '[A-Z]+-[0-9]+' | head -1 | tr '[:lower:]' '[:upper:]'); shift ;;
  esac
done
[ -n "$KEY" ] || { printf 'prepare-tc-workspace: need an issue key\n%s\n' "$USAGE" >&2; exit 1; }

# shellcheck disable=SC1090
if [ -f "$HOME/.cubrid-agent/env.sh" ]; then set +u; . "$HOME/.cubrid-agent/env.sh"; set -u; fi
TC=${CUBRID_TESTCASES:-$HOME/cubrid-testcases}
git -C "$TC" rev-parse --git-dir >/dev/null 2>&1 \
  || { printf 'prepare-tc-workspace: %s is not a git clone — run /setup-cubrid-agent first.\n' "$TC" >&2; exit 1; }

BRANCH="tc/$(printf '%s' "$KEY" | tr '[:upper:]' '[:lower:]')"
WT="$HOME/.cubrid-agent/worktrees/$(printf '%s' "$BRANCH" | tr '/' '-')"

git -C "$TC" fetch -q origin develop 2>/dev/null \
  || printf 'prepare-tc-workspace: could not fetch origin/develop — basing on the ref already here.\n' >&2
BASE=origin/develop
git -C "$TC" rev-parse --verify -q "$BASE" >/dev/null 2>&1 \
  || { printf 'prepare-tc-workspace: %s has no %s — git -C %s fetch origin develop\n' "$TC" "$BASE" "$TC" >&2; exit 1; }

# Ask git where the branch already is before deciding anything. A branch can only be checked out in one
# place, so if it has one, that place IS the answer — and every other order gets this wrong: a retry
# arrives with the run's own work uncommitted (§3 writes the .sql, §6 loops), and a clone that has since
# gone clean would try to check out a branch a worktree already holds, which fails outright.
CHECKED_OUT=$(git -C "$TC" worktree list --porcelain 2>/dev/null \
  | awk -v b="refs/heads/$BRANCH" '/^worktree /{p=$2} /^branch /{if ($2 == b) print p}' | head -1)
if [ -n "$CHECKED_OUT" ]; then
  printf 'prepare-tc-workspace: %s is already checked out at %s — continuing there.\n' "$BRANCH" "$CHECKED_OUT" >&2
  [ "$CHECKED_OUT" = "$TC" ] || printf 'prepare-tc-workspace: pass CUBRID_TESTCASES=%s to every helper and CTP call from here on.\n' "$CHECKED_OUT" >&2
  printf '%s\n' "$CHECKED_OUT"
  exit 0
fi

# Nowhere yet, so this is a first run for the issue. "Has something to lose" decides where it starts:
# uncommitted work, or a HEAD that is someone's task rather than a base to cut from. A `tc/cbrd-*` HEAD
# is this pipeline's own leftover, not a human's — treating it as foreign is what made a dedicated
# machine collect a worktree per issue from the second issue onwards. A detached HEAD is NOT safe: a
# rebase, a bisect and a CI checkout all look like that, and only one of them can afford a checkout.
HEAD_BRANCH=$(git -C "$TC" rev-parse --abbrev-ref HEAD 2>/dev/null)
DIRTY=$(git -C "$TC" status --porcelain 2>/dev/null | head -1)
ISOLATE=1
[ -z "$DIRTY" ] && case "$HEAD_BRANCH" in develop|master|main|tc/cbrd-*) ISOLATE=0 ;; esac

if [ "$ISOLATE" = 0 ]; then
  git -C "$TC" checkout -q -b "$BRANCH" "$BASE" || exit 1
  printf 'prepare-tc-workspace: %s was clean and on %s — authoring in place on %s.\n' "$TC" "$HEAD_BRANCH" "$BRANCH" >&2
  printf '%s\n' "$TC"
  exit 0
fi

# Isolating. A leftover directory that git does not know as a worktree is not ours to reuse or delete —
# say so rather than handing back a path that is not a repository.
git -C "$TC" worktree prune 2>/dev/null
[ -e "$WT" ] && { printf 'prepare-tc-workspace: %s exists but git does not know it as a worktree. Remove it yourself once you are sure it holds nothing, then re-run.\n' "$WT" >&2; exit 1; }
git -C "$TC" worktree add -q "$WT" -b "$BRANCH" "$BASE" || exit 1
printf 'prepare-tc-workspace: %s is on %s%s, so %s was cut from %s instead — the clone is untouched.\n' \
  "$TC" "$HEAD_BRANCH" "$([ -n "$DIRTY" ] && printf ' with uncommitted work')" "$WT" "$BASE" >&2
printf 'prepare-tc-workspace: pass CUBRID_TESTCASES=%s to every helper and CTP call from here on.\n' "$WT" >&2
printf '%s\n' "$WT"
