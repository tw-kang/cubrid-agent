#!/bin/bash
# Behavioural test for prepare-tc-workspace.sh — the helper that decides where a testcase gets authored.
#
# Dev-only, run by check-invariants.sh. Offline: a local repo stands in for origin, so nothing fetches.
#
# The rule it encodes: never author in a clone that has something to lose. The default clone is a
# human's working tree on the machines that matter — on this one it sits on `feature/meta/description`
# with nine changes staged — and the skills only ever said "never build on a human's checked-out
# branch" in prose, with no code testing it. A worktree keeps the object store shared and moves only
# the working directory, which is what the pipeline has been doing by hand.
#
# Both directions are pinned: a clone with nothing to lose must NOT grow a worktree (that would leave
# one per issue on CI and dedicated QA machines), and a clone with anything to lose must never be
# checked out.
set -u

BIN_DIR=$(cd "$(dirname "$(readlink -f "$0")")/../skills/qa/setup-cubrid-agent/bin" && pwd)
SRC="$BIN_DIR/prepare-tc-workspace.sh"
[ -f "$SRC" ] || { echo "test-prepare-tc-workspace: script not found at $SRC" >&2; exit 1; }

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
mkdir -p "$HOME/.cubrid-agent/worktrees"
KEY=CBRD-99999
WT="$HOME/.cubrid-agent/worktrees/tc-cbrd-99999"

T_PASS=0; T_FAIL=0; FAILURES=""
note_fail() { T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    $1"; }
g() { git -c user.name=t -c user.email=t@example.com "$@"; }

# A local "origin" so develop exists and nothing reaches the network.
ORIGIN="$T/origin"
g init -q "$ORIGIN"; mkdir -p "$ORIGIN/sql"
printf 'x\n' > "$ORIGIN/sql/seed.txt"
g -C "$ORIGIN" add -A; g -C "$ORIGIN" commit -qm base
g -C "$ORIGIN" branch -M develop

fresh_clone() {  # fresh_clone -> a clone on develop, clean
  rm -rf "$T/tc" "$WT"
  g clone -q "$ORIGIN" "$T/tc" 2>/dev/null
  g -C "$T/tc" checkout -q develop 2>/dev/null
}
run() {  # run [key] -> sets OUT (stdout = the path to author in), RC
  OUT=$(CUBRID_TESTCASES="$T/tc" bash "$SRC" "${1:-$KEY}" 2>"$T/err"); RC=$?
}
head_of() { git -C "$1" rev-parse --abbrev-ref HEAD 2>/dev/null; }

# ── nothing to lose: no worktree, author in place ────────────────────────────────────────────────
fresh_clone
run
[ "$RC" -eq 0 ] && [ "$OUT" = "$T/tc" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "clean clone on develop: expected the clone itself, got rc=$RC out=\"$OUT\""
[ -e "$WT" ] && note_fail "clean clone on develop: a worktree was created anyway" || T_PASS=$((T_PASS+1))
[ "$(head_of "$T/tc")" = "tc/cbrd-99999" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "clean clone on develop: the branch was not created (HEAD is $(head_of "$T/tc"))"

# ── uncommitted work: isolate, and do not touch the clone ────────────────────────────────────────
fresh_clone
printf 'mine\n' > "$T/tc/sql/wip.txt"; g -C "$T/tc" add -A   # staged, exactly like the real machine
run
[ "$RC" -eq 0 ] && [ "$OUT" = "$WT" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "dirty clone: expected the worktree path, got rc=$RC out=\"$OUT\""
[ "$(head_of "$T/tc")" = develop ] && T_PASS=$((T_PASS+1)) \
  || note_fail "dirty clone: the clone was checked out (HEAD is $(head_of "$T/tc"))"
[ -f "$T/tc/sql/wip.txt" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "dirty clone: the uncommitted file is gone"
[ "$(head_of "$WT")" = "tc/cbrd-99999" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "dirty clone: the worktree is not on the tc branch (HEAD is $(head_of "$WT"))"

# ── a human's branch, even clean: still isolate ──────────────────────────────────────────────────
fresh_clone
g -C "$T/tc" checkout -q -b feature/meta/description
run
[ "$RC" -eq 0 ] && [ "$OUT" = "$WT" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "human branch: expected the worktree path, got rc=$RC out=\"$OUT\""
[ "$(head_of "$T/tc")" = "feature/meta/description" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "human branch: the clone was moved off it (HEAD is $(head_of "$T/tc"))"

# ── a retry must reuse, not fail ─────────────────────────────────────────────────────────────────
run
[ "$RC" -eq 0 ] && [ "$OUT" = "$WT" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "second call: expected the same worktree, got rc=$RC out=\"$OUT\""
printf 'authored\n' > "$WT/sql/case.txt"
run
[ -f "$WT/sql/case.txt" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "second call: it discarded work already in the worktree"

# ── already on this issue's own branch: that is not someone else's work ──────────────────────────
fresh_clone
g -C "$T/tc" checkout -q -b tc/cbrd-99999
run
[ "$RC" -eq 0 ] && [ "$OUT" = "$T/tc" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "already on the tc branch: expected the clone itself, got rc=$RC out=\"$OUT\""

# ── a retry after authoring in place: the run's own dirt is not a reason to move ─────────────────
# §3 writes the .sql and §6 loops, so the second call always arrives with the clone dirty. Reading that
# as "something to lose" sent it to `worktree add` on a branch the clone already holds, which fails
# outright — the run would lose its own committed work to a hard error.
fresh_clone
run
printf 'authored\n' > "$T/tc/sql/case.txt"        # exactly what Author leaves behind
run
[ "$RC" -eq 0 ] && [ "$OUT" = "$T/tc" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "retry after authoring in place: expected the clone again, got rc=$RC out=\"$OUT\""

# ── a retry after isolating, once the human has tidied up ────────────────────────────────────────
# The branch lives in the worktree now. A clone that has since gone clean must not try to check it out.
fresh_clone
printf 'mine\n' > "$T/tc/sql/wip.txt"
run                                                # isolates
g -C "$T/tc" checkout -q -- . 2>/dev/null; rm -f "$T/tc/sql/wip.txt"
run
[ "$RC" -eq 0 ] && [ "$OUT" = "$WT" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "retry after the clone went clean: expected the worktree that holds the branch, got rc=$RC out=\"$OUT\""

# ── a second issue on a machine that authored a first one in place ───────────────────────────────
# The clone is left on tc/cbrd-99999. That is this pipeline's own leftover, not a human's work, so the
# next issue authors in place too — otherwise a dedicated QA machine grows one worktree per issue,
# which is the cost the conditional design exists to avoid.
fresh_clone
run
run CBRD-99998
[ "$RC" -eq 0 ] && [ "$OUT" = "$T/tc" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "second issue after an in-place first: expected the clone, got rc=$RC out=\"$OUT\""
[ -e "$HOME/.cubrid-agent/worktrees/tc-cbrd-99998" ] \
  && note_fail "second issue after an in-place first: it grew a worktree anyway" || T_PASS=$((T_PASS+1))

# ── a detached HEAD is a rebase as often as a CI checkout ────────────────────────────────────────
fresh_clone
g -C "$T/tc" checkout -q --detach 2>/dev/null
run
[ "$RC" -eq 0 ] && [ "$OUT" = "$WT" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "detached HEAD: expected isolation, got rc=$RC out=\"$OUT\""

# ── the branch survives its checkout: worktree removed, commits intact ───────────────────────────
# A branch with committed work but no checkout anywhere must be picked up, not recut from the base —
# `-b` would fail outright, and recutting would strand the commits.
fresh_clone
printf 'mine\n' > "$T/tc/sql/wip.txt"
run                                                    # isolates
printf 'authored\n' > "$WT/sql/case.txt"
git -C "$WT" -c user.name=t -c user.email=t@example.com add -A >/dev/null 2>&1
git -C "$WT" -c user.name=t -c user.email=t@example.com commit -qm "committed round" >/dev/null 2>&1
rm -rf "$WT"; g -C "$T/tc" worktree prune 2>/dev/null   # the checkout is gone, the branch is not
run
[ "$RC" -eq 0 ] && [ "$OUT" = "$WT" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "branch without a checkout (dirty clone): expected a fresh worktree on it, got rc=$RC out=\"$OUT\""
[ -f "$WT/sql/case.txt" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "branch without a checkout (dirty clone): the branch's committed work did not come back"

# Same state, but the clone is clean on develop — the in-place path must check the branch out, not -b it.
fresh_clone
run                                                    # in place, clone now on the tc branch
printf 'authored\n' > "$T/tc/sql/case.txt"
g -C "$T/tc" add -A >/dev/null 2>&1; g -C "$T/tc" commit -qm "committed round" >/dev/null 2>&1
g -C "$T/tc" checkout -q develop 2>/dev/null            # branch exists, checked out nowhere
run
[ "$RC" -eq 0 ] && [ "$OUT" = "$T/tc" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "branch without a checkout (clean clone): expected in-place pickup, got rc=$RC out=\"$OUT\""
[ -f "$T/tc/sql/case.txt" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "branch without a checkout (clean clone): the branch's committed work did not come back"

# ── a leftover directory git does not own is not ours to reuse or delete ─────────────────────────
fresh_clone
printf 'mine\n' > "$T/tc/sql/wip.txt"
mkdir -p "$WT"; printf 'someone\n' > "$WT/not-a-repo.txt"
run
[ "$RC" -ne 0 ] && T_PASS=$((T_PASS+1)) \
  || note_fail "stale directory at the worktree path: expected a refusal, got rc=$RC out=\"$OUT\""
[ -f "$WT/not-a-repo.txt" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "stale directory at the worktree path: it deleted content it does not own"
rm -rf "$WT"

# ── stdout is the path and nothing else, so a caller can use it directly ─────────────────────────
fresh_clone
run
case "$OUT" in
  */tc) T_PASS=$((T_PASS+1)) ;;
  *)    note_fail "stdout carries only the path: got \"$OUT\"" ;;
esac
[ "$(printf '%s' "$OUT" | wc -l)" -eq 0 ] && T_PASS=$((T_PASS+1)) \
  || note_fail "stdout carries only the path: it spans multiple lines"

# ── --pr N: a reviewer's checkout of someone else's branch ───────────────────────────────────────
# Reviewing is not authoring, and the difference is whose work is at stake. review-testcase runs on
# other people's PRs, so there is no case where the clone may be checked out: no branch, no in-place,
# nothing pushed. What it shares with authoring is worktree policy — reuse before create, refuse a
# directory git does not own — which is why it lives in the same script.
WT_PR="$HOME/.cubrid-agent/worktrees/pr-7"
pr_head() {  # pr_head <content> -> a new commit on refs/pull/7/head in the origin
  g -C "$ORIGIN" checkout -q -B pr-src develop 2>/dev/null
  printf '%s\n' "$1" > "$ORIGIN/sql/from-pr.txt"
  g -C "$ORIGIN" add -A; g -C "$ORIGIN" commit -qm "pr commit: $1"
  g -C "$ORIGIN" update-ref refs/pull/7/head "$(g -C "$ORIGIN" rev-parse pr-src)"
  g -C "$ORIGIN" checkout -q develop 2>/dev/null
}
runpr() {  # runpr [args...] -> sets OUT (stdout = the path to verify in), RC
  OUT=$(CUBRID_TESTCASES="$T/tc" bash "$SRC" "$@" 2>"$T/err"); RC=$?
}

pr_head first
fresh_clone; rm -rf "$WT_PR"
runpr --pr 7
[ "$RC" -eq 0 ] && [ "$OUT" = "$WT_PR" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "--pr on a clean clone: expected $WT_PR, got rc=$RC out=\"$OUT\" err=$(cat "$T/err")"
# A clean clone on develop is exactly where authoring works in place. Reviewing must not: the clone is
# the human's, and the branch under review is not ours to check out.
[ "$(head_of "$T/tc")" = develop ] && T_PASS=$((T_PASS+1)) \
  || note_fail "--pr on a clean clone: the clone was checked out anyway (HEAD is $(head_of "$T/tc"))"
[ -f "$WT_PR/sql/from-pr.txt" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "--pr: the worktree does not hold the PR's content"
# Detached on purpose: a local branch would be a second name for someone else's work, and it is what
# makes the refresh below refuse to run (git will not fetch into a checked-out branch).
[ "$(head_of "$WT_PR")" = HEAD ] && T_PASS=$((T_PASS+1)) \
  || note_fail "--pr: the worktree is not detached (HEAD is $(head_of "$WT_PR"))"
[ -z "$(git -C "$T/tc" for-each-ref --format='%(refname)' refs/heads/pr-7 2>/dev/null)" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "--pr: it created a local branch for someone else's PR"

# A re-run must land on the PR's CURRENT head — a review that verifies the revision before the author's
# last push reports findings they already fixed.
pr_head second
runpr --pr 7
[ "$RC" -eq 0 ] && [ "$OUT" = "$WT_PR" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "--pr re-run: expected the same worktree, got rc=$RC out=\"$OUT\" err=$(cat "$T/err")"
[ "$(cat "$WT_PR/sql/from-pr.txt" 2>/dev/null)" = second ] && T_PASS=$((T_PASS+1)) \
  || note_fail "--pr re-run: the worktree still holds the old revision ($(cat "$WT_PR/sql/from-pr.txt" 2>/dev/null))"

fresh_clone; rm -rf "$WT_PR"
printf 'mine\n' > "$T/tc/sql/wip.txt"; g -C "$T/tc" add -A
runpr --pr 7
[ "$RC" -eq 0 ] && [ "$OUT" = "$WT_PR" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "--pr on a dirty clone: expected $WT_PR, got rc=$RC out=\"$OUT\""
[ -f "$T/tc/sql/wip.txt" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "--pr on a dirty clone: the uncommitted file is gone"

# `checkout` carries edits and untracked files across, so a re-run over a modified worktree would
# review content the author never pushed — and report on it as theirs.
printf 'not from the author\n' > "$WT_PR/sql/from-pr.txt"
runpr --pr 7
[ "$RC" -ne 0 ] && T_PASS=$((T_PASS+1)) \
  || note_fail "--pr re-run over a modified worktree: expected a refusal, got rc=$RC"
[ "$(cat "$WT_PR/sql/from-pr.txt" 2>/dev/null)" = "not from the author" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "--pr re-run over a modified worktree: it discarded the change instead of refusing"
git -C "$WT_PR" checkout -q -- . 2>/dev/null
printf 'junk\n' > "$WT_PR/sql/untracked.sql"
runpr --pr 7
[ "$RC" -ne 0 ] && T_PASS=$((T_PASS+1)) \
  || note_fail "--pr re-run with an untracked file: expected a refusal, got rc=$RC"
rm -f "$WT_PR/sql/untracked.sql"

# PR numbers are per repository, so a fork's origin hands back a different pull request.
fresh_clone; rm -rf "$WT_PR"
g -C "$T/tc" remote set-url origin https://github.com/someone-else/cubrid-testcases.git
runpr --pr 7
grep -q 'not CUBRID/cubrid-testcases' "$T/err" && [ "$RC" -ne 0 ] && T_PASS=$((T_PASS+1)) \
  || note_fail "--pr with a fork origin: expected our refusal, got rc=$RC err=$(cat "$T/err")"

fresh_clone; rm -rf "$WT_PR"
mkdir -p "$WT_PR"; printf 'someone\n' > "$WT_PR/not-a-repo.txt"
runpr --pr 7
# The refusal must be ours, not git's incidental "directory not empty": only ours says what to do.
grep -q 'does not know it as a worktree' "$T/err" && [ "$RC" -ne 0 ] && T_PASS=$((T_PASS+1)) \
  || note_fail "--pr with a stale directory: expected our refusal, got rc=$RC err=$(cat "$T/err")"
[ -f "$WT_PR/not-a-repo.txt" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "--pr with a stale directory: it deleted content it does not own"
rm -rf "$WT_PR"

# A PR number that does not exist must fail loudly. Falling back to develop would review the base
# branch and call it the PR.
fresh_clone
runpr --pr 4242
[ "$RC" -ne 0 ] && T_PASS=$((T_PASS+1)) \
  || note_fail "--pr with an unknown PR: expected a refusal, got rc=$RC out=\"$OUT\""
[ ! -e "$HOME/.cubrid-agent/worktrees/pr-4242" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "--pr with an unknown PR: it created a worktree anyway"

# Two modes in one call has no answer — which tree should the caller use?
runpr --pr 7 CBRD-99999
[ "$RC" -ne 0 ] && T_PASS=$((T_PASS+1)) \
  || note_fail "--pr plus an issue key: expected a refusal, got rc=$RC out=\"$OUT\""
# Rejected before the value reaches a path: `--pr ../../x` would otherwise name a directory outside
# the worktree root.
runpr --pr not-a-number
grep -q 'takes a PR number' "$T/err" && [ "$RC" -ne 0 ] && T_PASS=$((T_PASS+1)) \
  || note_fail "--pr with a non-numeric argument: expected our refusal, got rc=$RC err=$(cat "$T/err")"

# stdout stays the path and nothing else.
fresh_clone; rm -rf "$WT_PR"
runpr --pr 7
[ "$(printf '%s' "$OUT" | wc -l)" -eq 0 ] && [ "$OUT" = "$WT_PR" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "--pr stdout carries only the path: got \"$OUT\""

if [ "$T_FAIL" -eq 0 ]; then
  printf 'prepare-tc-workspace: %d/%d\n' "$T_PASS" "$T_PASS"
  exit 0
else
  printf 'prepare-tc-workspace: %d passed, %d FAILED%s\n' "$T_PASS" "$T_FAIL" "$FAILURES"
  exit 1
fi
