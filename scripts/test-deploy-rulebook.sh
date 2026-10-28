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
# A local origin names no GitHub repo to ask, so the setting comes in from outside.
export DEPLOY_RULEBOOK_SQUASH_TITLE=COMMIT_OR_PR_TITLE

T_PASS=0; T_FAIL=0; FAILURES=""
note_fail() { T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    $1"; }
flat() { printf '%s' "$1" | tr '\n' '|'; }

REPO=cubrid-testcases-private-ex
A= O= C= W= F= CANONICAL= ORIGIN_TIP= FEATURE_TIP=

# A = fake cubrid-agent, O = bare origin, W = a second working copy that moves the origin,
# C = the clone under test, left on a feature branch and behind the origin so that a deploy which
# skips the fetch or branches from HEAD builds on the wrong base. Cases run in subshells, so the
# directory comes from mktemp rather than a counter.
fixture() {
  local d; d=$(mktemp -d "$T/case.XXXX")
  A=$d/agent; O=$d/$REPO.git; W=$d/seed; C=$d/clone; CANONICAL=$A/rulebook/$REPO
  mkdir -p "$A/scripts" "$A/.github" "$CANONICAL/shell/rules"
  cp "$SRC" "$A/scripts/deploy-rulebook.sh"
  printf '# head keys\nCUBRIDQA-1663\n' > "$A/.github/head-keys.txt"
  printf '# category owner\nshell tester-shell\nsql tester-sql\n' > "$A/rulebook/category-owners.txt"
  printf 'root rules\n' > "$CANONICAL/AGENTS.md"
  printf 'shell rules\n' > "$CANONICAL/shell/AGENTS.md"
  printf 'what to check\n' > "$CANONICAL/shell/rules/test-perspectives.md"
  printf 'how to write\n' > "$CANONICAL/shell/rules/writing-rules.md"
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

origin_commit() {
  git -C "$W" add -A && git -C "$W" commit -qm "$1" && git -C "$W" push -q "$O" develop
  ORIGIN_TIP=$(git -C "$O" rev-parse develop)
}

run() { OUT=$(bash "$A/scripts/deploy-rulebook.sh" "$@" 2>&1); RC=$?; }

t() {  # t <label> <case function>: the function prints why it failed, or nothing
  local why; why=$("$2" 2>&1)
  if [ -z "$why" ]; then T_PASS=$((T_PASS+1)); else note_fail "$1: $(flat "$why")"; fi
}

deployed() {
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
    git -C "$C" show "HEAD:$p" 2>/dev/null | cmp -s - "$CANONICAL/$p" || echo "$p is not committed byte for byte;"
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
t "one commit for the root files and one per category, each headed by the head key under COMMIT_OR_PR_TITLE" c_commits

# A PR_TITLE repo squashes every PR under the PR title, so the commits inside the PR carry no key.
c_title_pr() {
  fixture; export DEPLOY_RULEBOOK_SQUASH_TITLE=PR_TITLE
  deployed || return
  local subjects; subjects=$(git -C "$C" log --reverse --format=%s "$ORIGIN_TIP..HEAD" | tr '\n' '|')
  [ "$subjects" = "Deploy the repo-wide rulebook|Deploy the shell rulebook|" ] || echo "subjects: $subjects;"
  printf '%s\n' "$OUT" | grep -q 'PR_TITLE' || echo "the output does not name the setting it read"
}
t "where the squash title is PR_TITLE, the commit subjects carry no key" c_title_pr

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
refused_untouched() {
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

# A branch cut from a fork's develop carries whatever the fork holds. With only file:// allowed a fetch
# fails too, so each case also wants the refusal to name CUBRID.
fork_refused() {  # <origin url>
  fixture; git -C "$C" remote set-url origin "$1"
  export GIT_ALLOW_PROTOCOL=file GIT_TERMINAL_PROMPT=0
  refused_untouched "$C"
  [ "$RC" -eq 1 ] || echo "exit $RC, not 1;"
  printf '%s\n' "$OUT" | grep -q 'CUBRID' || echo "the refusal does not name CUBRID — $(flat "$OUT")"
}
c_fork_origin() { fork_refused "https://github.com/tester/$REPO.git"; }
t "an origin on a GitHub owner other than CUBRID is refused and the clone left untouched" c_fork_origin

# An SSH host alias from ~/.ssh/config hides github.com, so only the owner tells a fork apart.
c_fork_alias() { fork_refused "git@gh-work:tester/$REPO.git"; }
t "an origin behind an SSH host alias on an owner other than CUBRID is refused" c_fork_alias

c_cubrid_alias() {
  fixture; git -C "$C" remote set-url origin "git@gh-work:CUBRID/$REPO.git"
  export GIT_ALLOW_PROTOCOL=file GIT_TERMINAL_PROMPT=0
  run "$C"
  printf '%s\n' "$OUT" | grep -q 'not a CUBRID repo' && echo "refused as a fork — $(flat "$OUT")"
}
t "an origin behind an SSH host alias on CUBRID is not refused as a fork" c_cubrid_alias

origin_deployed() {  # put an exact deployed copy on the origin, after the clone, so only a fetch sees it
  mkdir -p "$W/shell/rules"
  cp "$CANONICAL/AGENTS.md" "$W/AGENTS.md" && cp "$CANONICAL/shell/AGENTS.md" "$W/shell/AGENTS.md"
  cp "$CANONICAL/shell/rules/"*.md "$W/shell/rules/"
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
  cp "$CANONICAL/AGENTS.md" "$W/AGENTS.md" && ln -sfn AGENTS.md "$W/CLAUDE.md"
  origin_commit "root files already deployed"
  deployed || return
  local n; n=$(git -C "$C" rev-list --count "$ORIGIN_TIP..HEAD")
  [ "$n" = 1 ] || { echo "expected 1 commit, got $n"; return; }
  printf '%s\n' "$OUT" | grep -q 'warning: one commit' || echo "no 'warning: one commit' — $(flat "$OUT")"
}
t "where the squash title is COMMIT_OR_PR_TITLE, a deploy that yields a single commit warns" c_one_commit

c_one_commit_pr_title() {
  fixture; export DEPLOY_RULEBOOK_SQUASH_TITLE=PR_TITLE
  cp "$CANONICAL/AGENTS.md" "$W/AGENTS.md" && ln -sfn AGENTS.md "$W/CLAUDE.md"
  origin_commit "root files already deployed"
  deployed || return
  [ "$(git -C "$C" rev-list --count "$ORIGIN_TIP..HEAD")" = 1 ] || { echo "expected 1 commit"; return; }
  printf '%s\n' "$OUT" | grep -q 'warning: one commit' && echo "warns though a PR_TITLE squash takes the PR title"
}
t "where the squash title is PR_TITLE, a single commit is no cause for a warning" c_one_commit_pr_title

c_title_unknown() {
  fixture; unset DEPLOY_RULEBOOK_SQUASH_TITLE
  refused_untouched "$C"
  printf '%s\n' "$OUT" | grep -q 'squash_merge_commit_title' || echo "the refusal does not name the setting — $(flat "$OUT")"
}
t "with a local origin and no setting given, the deploy is refused and the clone left untouched" c_title_unknown

c_title_unread() {
  fixture; unset DEPLOY_RULEBOOK_SQUASH_TITLE
  git -C "$C" remote set-url origin "git@gh-work:CUBRID/$REPO.git"
  export GIT_ALLOW_PROTOCOL=file GIT_TERMINAL_PROMPT=0
  local bin; bin=$(dirname "$C")/bin; mkdir -p "$bin"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/gh.log"\nexit 1\n' "$bin" > "$bin/gh" && chmod +x "$bin/gh"
  export PATH="$bin:$PATH"
  refused_untouched "$C"
  grep -q "^api repos/CUBRID/$REPO " "$bin/gh.log" 2>/dev/null || echo "gh was not asked about CUBRID/$REPO;"
  printf '%s\n' "$OUT" | tail -1 | grep -q 'squash_merge_commit_title' \
    || echo "the refusal does not name the setting — $(flat "$OUT")"
}
t "when GitHub does not answer for the origin's repo, the deploy is refused before the fetch" c_title_unread

c_nothing() {
  fixture; origin_deployed; origin_commit "deployed copy"
  deployed || return
  git -C "$C" show-ref --verify -q refs/heads/cubridqa-1663-rulebook && echo "made a branch with no commit;"
  [ "$(git -C "$C" symbolic-ref --short HEAD)" = feature ] || echo "moved HEAD;"
  printf '%s\n' "$OUT" | grep -q 'nothing to deploy' || echo "no 'nothing to deploy' — $(flat "$OUT")"
}
t "nothing to deploy leaves no empty branch behind" c_nothing

# --check reads the mode, and cp keeps the mode of a file it overwrites, so a deploy that leaves it
# makes a branch with no commit.
c_mode_only() {
  fixture; origin_deployed; chmod +x "$W/shell/AGENTS.md"; origin_commit "deployed copy, one file executable"
  run --check "$C"
  named shell/AGENTS.md || echo "--check does not name shell/AGENTS.md — $(flat "$OUT");"
  deployed || return
  [ "$(git -C "$C" ls-tree HEAD -- shell/AGENTS.md | cut -d' ' -f1)" = 100644 ] || echo "shell/AGENTS.md is not 100644 after the deploy;"
  [ "$(git -C "$C" rev-list --count "$ORIGIN_TIP..HEAD")" -ge 1 ] || echo "the branch has no commit"
}
t "a file on origin/develop that differs only in mode is reported by --check and fixed by a deploy" c_mode_only

# The owner approves the rulebook content; a PR without the owner as reviewer has no approver.
c_no_owner() {
  fixture; printf 'sql tester-sql\n' > "$A/rulebook/category-owners.txt"; git -C "$A" commit -qam "drop shell"
  refused_untouched "$C"
  [ "$RC" -eq 1 ] || echo "exit $RC, not 1;"
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
  fixture; printf 'not committed\n' >> "$CANONICAL/shell/rules/writing-rules.md"
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

# The tc PR stays open while the owner reviews it, and its branch is never force-pushed, so a fix to
# the canonical tree has to reach that branch as commits on top of it.
fork_pushed() {  # push the deploy branch to a fresh bare fork, as opening the PR does
  F=$(dirname "$C")/fork.git
  git init -q --bare "$F" && git -C "$C" push -q "$F" cubridqa-1663-rulebook 2>/dev/null
}
canonical_fix() { printf 'how to write, fixed\n' > "$CANONICAL/shell/rules/writing-rules.md"; git -C "$A" commit -qam "fix a rule"; }

c_update() {
  fixture; deployed || return; fork_pushed || { echo "the first push failed"; return; }
  local first; first=$(git -C "$C" rev-parse HEAD)
  git -C "$C" switch -q feature; canonical_fix
  deployed || return
  [ "$(git -C "$C" symbolic-ref --short HEAD)" = cubridqa-1663-rulebook ] || echo "not on the deploy branch;"
  git -C "$C" merge-base --is-ancestor "$first" HEAD || { echo "the first deploy's commits are gone;"; return; }
  [ "$(git -C "$C" rev-list --count "$first..HEAD")" = 1 ] || echo "expected one new commit;"
  [ "$(git -C "$C" diff-tree --no-commit-id --name-only -r HEAD)" = shell/rules/writing-rules.md ] \
    || echo "the new commit holds more than the changed file;"
  case "$(git -C "$C" log -1 --format=%s)" in "[CUBRIDQA-1663] "?*) ;; *) echo "subject not headed by the head key;" ;; esac
  git -C "$C" show HEAD:shell/rules/writing-rules.md | cmp -s - "$CANONICAL/shell/rules/writing-rules.md" \
    || echo "the fix is not committed byte for byte;"
  git -C "$C" push -q "$F" cubridqa-1663-rulebook 2>/dev/null || echo "a plain push to the fork was rejected;"
  printf '%s\n' "$OUT" | grep -q 'open PR' || echo "does not say the push updates the open PR;"
  printf '%s\n' "$OUT" | grep -qF -- '----- PR body -----' && echo "prints a PR body skeleton for a PR that exists;"
  printf '%s\n' "$OUT" | grep -q 'warning: one commit' && echo "warns of one commit though the PR already has more"
}
t "on an existing deploy branch, a canonical fix lands as a commit on top that a plain push accepts" c_update

# A rebase would rewrite the commits the fork already has, and the push would need force.
c_update_behind() {
  fixture; deployed || return; fork_pushed || { echo "the first push failed"; return; }
  local first; first=$(git -C "$C" rev-parse HEAD)
  git -C "$C" switch -q feature
  printf 'tc\n' > "$W/shell/_01/cases/c.sh"; origin_commit "origin moves while the PR is open"
  canonical_fix
  deployed || return
  git -C "$C" merge-base --is-ancestor "$first" HEAD || { echo "the first deploy's commits were rewritten;"; return; }
  git -C "$C" merge-base --is-ancestor "$ORIGIN_TIP" HEAD || echo "the branch lacks the new origin/develop tip;"
  git -C "$C" show HEAD:shell/rules/writing-rules.md | cmp -s - "$CANONICAL/shell/rules/writing-rules.md" \
    || echo "the fix is not committed;"
  git -C "$C" push -q "$F" cubridqa-1663-rulebook 2>/dev/null || echo "a plain push to the fork was rejected;"
  local subjects; subjects=$(git -C "$C" log --reverse --first-parent --format=%s "$first..HEAD" | tr '\n' '|')
  [ "$subjects" = "[CUBRIDQA-1663] Merge origin/develop into cubridqa-1663-rulebook|[CUBRIDQA-1663] Deploy the shell rulebook|" ] \
    || echo "subjects: $subjects"
}
t "a deploy branch behind origin/develop takes it by merge, not by rebase, with keyed subjects under COMMIT_OR_PR_TITLE" c_update_behind

c_update_behind_pr_title() {
  fixture; export DEPLOY_RULEBOOK_SQUASH_TITLE=PR_TITLE
  deployed || return
  local first; first=$(git -C "$C" rev-parse HEAD)
  git -C "$C" switch -q feature
  printf 'tc\n' > "$W/shell/_01/cases/c.sh"; origin_commit "origin moves while the PR is open"
  canonical_fix
  deployed || return
  local subjects; subjects=$(git -C "$C" log --reverse --first-parent --format=%s "$first..HEAD" | tr '\n' '|')
  [ "$subjects" = "Merge origin/develop into cubridqa-1663-rulebook|Deploy the shell rulebook|" ] || echo "subjects: $subjects"
}
t "where the squash title is PR_TITLE, the merge and the fix on an open deploy branch carry no key" c_update_behind_pr_title

c_update_nothing() {
  fixture; deployed || return
  local first; first=$(git -C "$C" rev-parse HEAD)
  git -C "$C" switch -q feature
  printf 'tc\n' > "$W/shell/_01/cases/c.sh"; origin_commit "origin moves while the PR is open"
  deployed || return
  [ "$(git -C "$C" rev-parse cubridqa-1663-rulebook)" = "$first" ] || echo "the deploy branch moved;"
  [ "$(git -C "$C" symbolic-ref --short HEAD)" = feature ] || echo "moved HEAD;"
  printf '%s\n' "$OUT" | grep -q 'no commit' || echo "no 'no commit' — $(flat "$OUT")"
}
t "a deploy branch that already matches the canonical tree gets no commit, not even a merge" c_update_nothing

if [ "$T_FAIL" -eq 0 ]; then
  printf 'deploy-rulebook: %d/%d\n' "$T_PASS" "$T_PASS"
  exit 0
else
  printf 'deploy-rulebook: %d passed, %d FAILED%s\n' "$T_PASS" "$T_FAIL" "$FAILURES"
  exit 1
fi
