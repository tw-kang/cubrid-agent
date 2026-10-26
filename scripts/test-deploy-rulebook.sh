#!/bin/bash
# Behavioural test for deploy-rulebook.sh — the tool that copies a canonical rulebook into a tc repo clone.
#
# Dev-only, run by check-invariants.sh. Offline: every case builds a fake cubrid-agent (a copy of the
# real script with its own rulebook, owner table and head keys), a bare origin and a clone. Only the CLI
# seam is observed: exit code, output, and the git state of the clone and the origin.
set -u

SRC=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)/deploy-rulebook.sh
[ -f "$SRC" ] || { echo "test-deploy-rulebook: script not found at $SRC" >&2; exit 1; }

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

T_PASS=0; T_FAIL=0; FAILURES=""
note_fail() { T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    $1"; }
flat() { printf '%s' "$1" | tr '\n' '|'; }

REPO=cubrid-testcases-private-ex
A= O= C= W= CAN= ORIGIN_TIP= FEATURE_TIP=

# A = fake cubrid-agent, O = bare origin, W = a second working copy that moves the origin,
# C = the clone under test, left on a feature branch and behind the origin so that a deploy which
# skips the fetch or branches from HEAD builds on the wrong base. Cases run in subshells, so the
# directory comes from mktemp rather than a counter.
fixture() {
  local d; d=$(mktemp -d "$T/case.XXXX")
  A=$d/agent; O=$d/$REPO.git; W=$d/seed; C=$d/clone; CAN=$A/rulebook/$REPO
  mkdir -p "$A/scripts" "$A/.github" "$CAN/shell/rules"
  cp "$SRC" "$A/scripts/deploy-rulebook.sh"
  printf '# head keys\nCUBRIDQA-1663\n' > "$A/.github/head-keys.txt"
  printf '# category owner\nshell tester-shell\nsql tester-sql\n' > "$A/rulebook/category-owners.txt"
  printf 'root rules\n' > "$CAN/AGENTS.md"
  printf 'shell rules\n' > "$CAN/shell/AGENTS.md"
  printf 'what to check\n' > "$CAN/shell/rules/test-perspectives.md"
  printf 'how to write\n' > "$CAN/shell/rules/writing-rules.md"
  git -C "$A" init -q && git -C "$A" add -A && git -C "$A" commit -qm init

  git init -q -b develop "$W"
  mkdir -p "$W/shell/_01/cases" && printf 'tc\n' > "$W/shell/_01/cases/a.sh"
  git -C "$W" add -A && git -C "$W" commit -qm seed
  git clone -q --bare "$W" "$O"
  git clone -q "$O" "$C"
  git -C "$C" switch -q -c feature
  printf 'local\n' > "$C/local.txt" && git -C "$C" add -A && git -C "$C" commit -qm local
  FEATURE_TIP=$(git -C "$C" rev-parse HEAD)
  printf 'tc\n' > "$W/shell/_01/cases/b.sh"
  origin_commit "origin moves after the clone"
}

origin_commit() {  # commit whatever W holds and push it to the origin's develop
  git -C "$W" add -A && git -C "$W" commit -qm "$1" && git -C "$W" push -q "$O" develop
  ORIGIN_TIP=$(git -C "$O" rev-parse develop)
}

run() { OUT=$(bash "$A/scripts/deploy-rulebook.sh" "$@" 2>&1); RC=$?; }

t() {  # t <label> <case function>: the function prints why it failed, or nothing
  local why; why=$("$2" 2>&1)
  if [ -z "$why" ]; then T_PASS=$((T_PASS+1)); else note_fail "$1: $(flat "$why")"; fi
}

deployed() {  # run a deploy that must succeed; print why it did not
  run "$C"
  [ "$RC" -eq 0 ] || { echo "exit $RC — $(flat "$OUT")"; return 1; }
}

c_branch() {
  fixture; deployed || return
  local b; b=$(git -C "$C" symbolic-ref --short HEAD)
  [ "$b" = cubridqa-1663-rulebook ] || { echo "HEAD is on $b"; return; }
  git -C "$C" merge-base --is-ancestor "$ORIGIN_TIP" HEAD || echo "branch lacks the fetched origin/develop tip"
  git -C "$C" merge-base --is-ancestor "$FEATURE_TIP" HEAD && echo "branch carries the clone's feature commit"
}
t "the branch starts at the fetched origin/develop, not at HEAD" c_branch

c_bytes() {
  fixture; deployed || return
  local p
  for p in AGENTS.md shell/AGENTS.md shell/rules/test-perspectives.md shell/rules/writing-rules.md; do
    git -C "$C" show "HEAD:$p" 2>/dev/null | cmp -s - "$CAN/$p" || echo "$p is not committed byte for byte;"
  done
}
t "every canonical file is committed byte for byte" c_bytes

c_symlink() {
  fixture; deployed || return
  local p mode
  for p in CLAUDE.md shell/CLAUDE.md; do
    mode=$(git -C "$C" ls-tree HEAD -- "$p" | cut -d' ' -f1)
    [ "$mode" = 120000 ] || { echo "$p has mode '$mode';"; continue; }
    [ "$(git -C "$C" cat-file -p "HEAD:$p")" = AGENTS.md ] || echo "$p does not point at AGENTS.md;"
  done
}
t "a CLAUDE.md symlink to AGENTS.md sits next to every AGENTS.md" c_symlink

# Each commit must revert alone, so each one holds exactly the root files or exactly one category.
c_commits() {
  fixture; deployed || return
  local c s files units=""
  for c in $(git -C "$C" rev-list --reverse "$ORIGIN_TIP..HEAD"); do
    s=$(git -C "$C" log -1 --format=%s "$c")
    case "$s" in "[CUBRIDQA-1663] "?*) ;; *) echo "subject not headed by the head key: $s;" ;; esac
    files=$(git -C "$C" diff-tree --no-commit-id --name-only -r "$c" | tr '\n' ' ')
    case "$files" in
      "AGENTS.md CLAUDE.md ") units="$units root" ;;
      "shell/AGENTS.md shell/CLAUDE.md shell/rules/test-perspectives.md shell/rules/writing-rules.md ") units="$units shell" ;;
      *) echo "commit '$s' mixes units: $files;" ;;
    esac
  done
  [ "$units" = " root shell" ] || echo "expected one root and one shell commit, got:$units"
}
t "one commit for the root files and one per category, each headed by the head key" c_commits

# The owner table also lists sql; only the categories in this repo's tree may become reviewers.
c_pr_body() {
  fixture; deployed || return
  local want
  printf '%s\n' "$OUT" | grep -qx 'reviewers: tester-shell' || echo "no 'reviewers: tester-shell' line;"
  for want in '<http://jira.cubrid.org/browse/CUBRIDQA-1663>' '### Purpose' '### Implementation' '### Remarks' \
              '제안' '담당자 확인 목록'; do
    printf '%s\n' "$OUT" | grep -qF -- "$want" || echo "body lacks '$want';"
  done
  [ "$(git -C "$O" for-each-ref --format='%(refname) %(objectname)')" = "refs/heads/develop $ORIGIN_TIP" ] \
    || echo "the origin changed: $(git -C "$O" for-each-ref --format='%(refname)' | tr '\n' ' ')"
}
t "prints the PR body skeleton and the category owner as reviewer, and pushes nothing" c_pr_body

clone_state() {  # every ref (remote-tracking ones show a fetch), HEAD, and the work tree
  git -C "$C" for-each-ref --format='%(refname) %(objectname)'
  git -C "$C" symbolic-ref HEAD
  git -C "$C" status --porcelain
  cat "$C/local.txt" "$C/shell/AGENTS.md" 2>/dev/null
}
refused_untouched() {  # run with the given args; the run must fail and leave the clone as it was
  local before; before=$(clone_state)
  run "$@"
  [ "$RC" -ne 0 ] || { echo "exit 0 — $(flat "$OUT")"; return; }
  [ "$(clone_state)" = "$before" ] || echo "the clone changed"
}

c_dirty_tracked() {
  fixture; printf 'edited\n' > "$C/local.txt"
  refused_untouched "$C"
}
t "a clone with an uncommitted edit is refused and left untouched" c_dirty_tracked

c_dirty_untracked() {
  fixture; mkdir -p "$C/shell" && printf 'my draft\n' > "$C/shell/AGENTS.md"
  refused_untouched "$C"
}
t "an untracked file where the rulebook would land is refused and left untouched" c_dirty_untracked

origin_deployed() {  # put an exact deployed copy on the origin, after the clone, so only a fetch sees it
  mkdir -p "$W/shell/rules"
  cp "$CAN/AGENTS.md" "$W/AGENTS.md" && cp "$CAN/shell/AGENTS.md" "$W/shell/AGENTS.md"
  cp "$CAN/shell/rules/"*.md "$W/shell/rules/"
  ln -sfn AGENTS.md "$W/CLAUDE.md" && ln -sfn AGENTS.md "$W/shell/CLAUDE.md"
}
named() { printf '%s\n' "$OUT" | grep -qE "(^|[[:space:]])$1\$"; }

# shell/CLAUDE.md holds the same bytes as the symlink, as a checkout without core.symlinks writes it;
# only its mode tells it apart.
c_check_differs() {
  fixture; origin_deployed
  rm "$W/shell/CLAUDE.md" && printf 'AGENTS.md' > "$W/shell/CLAUDE.md"
  printf 'edited on develop\n' > "$W/shell/rules/writing-rules.md"
  rm "$W/shell/rules/test-perspectives.md"
  origin_commit "deployed copy drifts"
  run --check "$C"
  [ "$RC" -ne 0 ] || echo "exit 0;"
  local p
  for p in shell/CLAUDE.md shell/rules/writing-rules.md shell/rules/test-perspectives.md; do
    named "$p" || echo "$p not reported;"
  done
  for p in AGENTS.md CLAUDE.md shell/AGENTS.md; do
    named "$p" && echo "$p reported though it matches;"
  done
  [ "$(git -C "$C" symbolic-ref --short HEAD)" = feature ] || echo "--check moved HEAD"
  git -C "$C" show-ref --verify -q refs/heads/cubridqa-1663-rulebook && echo "--check made a branch"
  [ -z "$(git -C "$C" status --porcelain)" ] || echo "--check touched the work tree"
}
t "--check names every path that differs from origin/develop and exits non-zero" c_check_differs

c_check_matches() {
  fixture; origin_deployed; origin_commit "deployed copy"
  run --check "$C"
  [ "$RC" -eq 0 ] || echo "exit $RC — $(flat "$OUT")"
}
t "--check exits 0 when origin/develop carries exactly the deployed copy" c_check_matches

c_one_commit() {
  fixture
  cp "$CAN/AGENTS.md" "$W/AGENTS.md" && ln -sfn AGENTS.md "$W/CLAUDE.md"
  origin_commit "root files already deployed"
  deployed || return
  local n; n=$(git -C "$C" rev-list --count "$ORIGIN_TIP..HEAD")
  [ "$n" = 1 ] || { echo "expected 1 commit, got $n"; return; }
  printf '%s\n' "$OUT" | grep -q 'warning: one commit' || echo "no 'warning: one commit' — $(flat "$OUT")"
}
t "a deploy that yields a single commit warns" c_one_commit

c_nothing() {
  fixture; origin_deployed; origin_commit "deployed copy"
  deployed || return
  git -C "$C" show-ref --verify -q refs/heads/cubridqa-1663-rulebook && echo "made a branch with no commit;"
  [ "$(git -C "$C" symbolic-ref --short HEAD)" = feature ] || echo "moved HEAD;"
  printf '%s\n' "$OUT" | grep -q 'nothing to deploy' || echo "no 'nothing to deploy' — $(flat "$OUT")"
}
t "nothing to deploy leaves no empty branch behind" c_nothing

# The owner approves the rulebook content; a PR without the owner as reviewer has no approver.
c_no_owner() {
  fixture; printf 'sql tester-sql\n' > "$A/rulebook/category-owners.txt"; git -C "$A" commit -qam "drop shell"
  refused_untouched "$C"
  printf '%s\n' "$OUT" | grep -q 'shell' || echo "the refusal does not name shell — $(flat "$OUT")"
}
t "a category with no owner in the table is refused and the clone left untouched" c_no_owner

# The tc repo history is what says which rulebook is in use, so each commit names its canonical commit.
c_source() {
  fixture; deployed || return
  local src c; src=$(git -C "$A" rev-parse HEAD)
  for c in $(git -C "$C" rev-list "$ORIGIN_TIP..HEAD"); do
    git -C "$C" log -1 --format=%b "$c" | grep -qF "$src" || echo "commit $c does not name canonical commit $src;"
  done
}
t "every deploy commit names the cubrid-agent commit it copied from" c_source

c_dirty_canonical() {
  fixture; printf 'not committed\n' >> "$CAN/shell/rules/writing-rules.md"
  refused_untouched "$C"
}
t "an uncommitted canonical tree is refused, since no commit could name it" c_dirty_canonical

two_heads() { printf 'CUBRIDQA-1663\nCUBRIDQA-1700\n' >> "$A/.github/head-keys.txt"; git -C "$A" commit -qam "second head"; }

c_key_ambiguous() {
  fixture; two_heads
  refused_untouched "$C"
  printf '%s\n' "$OUT" | grep -q -- '--key' || echo "the refusal does not mention --key — $(flat "$OUT")"
}
t "with more than one head key and no --key, the deploy is refused and the clone left untouched" c_key_ambiguous

c_key_given() {
  fixture; two_heads
  run --key CUBRIDQA-1700 "$C"
  [ "$RC" -eq 0 ] || { echo "exit $RC — $(flat "$OUT")"; return; }
  [ "$(git -C "$C" symbolic-ref --short HEAD)" = cubridqa-1700-rulebook ] || echo "not on cubridqa-1700-rulebook;"
  git -C "$C" log --format=%s "$ORIGIN_TIP..HEAD" | grep -vq '^\[CUBRIDQA-1700\] ' && echo "a subject lacks [CUBRIDQA-1700];"
  printf '%s\n' "$OUT" | grep -qxF '<http://jira.cubrid.org/browse/CUBRIDQA-1700>' || echo "the body links another key;"
}
t "--key names the head key of the branch, the subjects and the body" c_key_given

if [ "$T_FAIL" -eq 0 ]; then
  printf 'deploy-rulebook: %d/%d\n' "$T_PASS" "$T_PASS"
  exit 0
else
  printf 'deploy-rulebook: %d passed, %d FAILED%s\n' "$T_PASS" "$T_FAIL" "$FAILURES"
  exit 1
fi
