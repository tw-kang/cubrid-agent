#!/bin/bash
# check-pr-push.sh — the delivery rules CI enforces, so a reviewer does not have to.
#
#   check-pr-push.sh pr <head-branch> <base-branch> <title> <draft:true|false>
#   check-pr-push.sh push <before-sha> <after-sha>
#
# Dev-only: run by the `validate` workflow. Exit 0 = every rule holds, 1 = a rule failed, 2 = bad input.
set -u

ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
[ -n "$ROOT" ] && cd "$ROOT" || { echo "check-pr-push: not a git repo" >&2; exit 2; }

FAILED=0
ok()   { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; FAILED=$((FAILED+1)); }
usage() { sed -n '4,5p' "$0" | sed 's/^# *//' >&2; exit 2; }

HEAD_KEYS_FILE=.github/head-keys.txt

# A malformed line would silently drop a key, and a Ready PR carrying it would then pass.
read_head_keys() {
  [ -f "$HEAD_KEYS_FILE" ] || { echo "check-pr-push: $HEAD_KEYS_FILE is missing" >&2; exit 2; }
  local bad
  HEAD_KEYS=$(sed 's/#.*//' "$HEAD_KEYS_FILE" | tr -d ' \t' | grep -v '^$')
  bad=$(printf '%s\n' "$HEAD_KEYS" | grep -vxE 'CUBRIDQA-[1-9][0-9]*|')
  [ -z "$bad" ] || { echo "check-pr-push: not a CUBRIDQA key in $HEAD_KEYS_FILE: $(echo $bad)" >&2; exit 2; }
}

check_pr() {
  local branch=$1 base=$2 title=$3 draft=$4 num= key=
  case "$draft" in true|false) ;; *) echo "check-pr-push: draft must be true or false, got: $draft" >&2; exit 2 ;; esac
  if [ "$branch" = develop ] && [ "$base" = main ] && [[ $title =~ ^Release\ v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    ok "release PR ($title, develop -> main): exempt from the branch and header rules"
    return
  fi
  read_head_keys

  [[ $branch =~ ^cubridqa-([0-9]+)-[a-z0-9][a-z0-9-]*$ ]] && num=${BASH_REMATCH[1]}
  if [ -n "$num" ] && printf '%s\n' "$HEAD_KEYS" | grep -qx "CUBRIDQA-$num"; then
    ok "branch $branch is named after head key CUBRIDQA-$num"
  else
    fail "branch $branch is not cubridqa-<head key number>-<content>; head keys: $(echo ${HEAD_KEYS:-none})"
  fi

  [[ $title =~ ^\[(CUBRIDQA-[1-9][0-9]*)\]\ [^[:space:]] ]] && key=${BASH_REMATCH[1]}
  if [ -z "$key" ]; then
    fail "title does not start with [CUBRIDQA-<n>]: $title"
  elif ! printf '%s\n' "$HEAD_KEYS" | grep -qx "$key"; then
    ok "title is headed by [$key]"
  elif [ "$draft" = true ]; then
    ok "Draft PR may carry head key $key until it is made Ready"
  else
    fail "Ready PR is still headed by head key $key — swap it for the sub-task key, or convert back to Draft"
  fi
}

check_push() {
  local before=$1 after=$2 commits c files subject shipped=()
  mapfile -t shipped < <(sed -n '/^SHIPPED_PATHS=(/,/^)/p' scripts/release.sh | sed '1d;$d' | tr -d ' \t')
  [ ${#shipped[@]} -gt 0 ] || { echo "check-pr-push: no SHIPPED_PATHS in scripts/release.sh" >&2; exit 2; }

  # A first push has no before, and walking all of its history would judge commits that reached the
  # repo long ago through other branches.
  if [[ $before =~ ^0+$ ]]; then
    commits=$(git rev-list -1 "$after" 2>/dev/null) || { echo "check-pr-push: cannot read $after" >&2; exit 2; }
    ok "first push: checking the tip only"
  else
    commits=$(git rev-list --reverse "$before..$after" 2>/dev/null) || { echo "check-pr-push: cannot read $before..$after" >&2; exit 2; }
  fi

  for c in $commits; do
    files=$(git diff-tree -r --root --name-only --no-commit-id -m --first-parent "$c" -- "${shipped[@]}")
    [ -n "$files" ] || continue
    subject=$(git log -1 --format=%s "$c")
    if [[ $subject =~ ^Release\ v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\ \(trigger\ [123]\)$ ]]; then
      ok "${c:0:7} release commit: $subject"
    # GitHub commits a squash merge itself; a direct commit that only borrows the "(#NN)" suffix does not.
    elif [ "$(git log -1 --format=%p "$c" | wc -w)" -eq 1 ] && [ "$(git log -1 --format=%ce "$c")" = noreply@github.com ] \
         && [[ $subject =~ \ \(#[0-9]+\)$ ]]; then
      ok "${c:0:7} squash-merged PR: $subject"
    else
      fail "${c:0:7} changed the shipped surface without a PR: $subject ($(echo $files))"
    fi
  done
}

case "${1:-}" in
  pr)   [ $# -eq 5 ] || usage; check_pr "$2" "$3" "$4" "$5" ;;
  push) [ $# -eq 3 ] || usage; check_push "$2" "$3" ;;
  *)    usage ;;
esac

[ "$FAILED" -eq 0 ] && { echo "check-pr-push: ok"; exit 0; }
echo "check-pr-push: $FAILED violation(s)"; exit 1
