#!/bin/bash
# Behavioural test for render-pr-body.sh — the numbers it feeds the submit gate.
#
# Dev-only, run by check-invariants.sh. Offline: a throwaway $HOME and a throwaway git repo.
#
# What it pins: the case count is read from wherever the branch is actually checked out — authoring
# may have happened in a worktree while $CUBRID_TESTCASES still names the clone — and a rendered body
# whose human sections may be filled in is never clobbered without --force.
set -u

BIN_DIR=$(cd "$(dirname "$(readlink -f "$0")")/../skills/qa/setup-cubrid-agent/bin" && pwd)
SRC="$BIN_DIR/render-pr-body.sh"
[ -f "$SRC" ] || { echo "test-render-pr-body: script not found at $SRC" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "test-render-pr-body: jq is required." >&2; exit 1; }

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
export CUBRID_TESTCASES="$T/tc"
KEY=CBRD-99999
BRANCH=tc/cbrd-99999
RUN="$HOME/.cubrid-agent/$KEY"
mkdir -p "$RUN" "$CUBRID_TESTCASES"

T_PASS=0; T_FAIL=0; FAILURES=""
note_fail() { T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    $1"; }
g() { git -C "$CUBRID_TESTCASES" -c user.name=t -c user.email=t@example.com "$@"; }

# A branch whose .sql lives only in a worktree: the clone stays on develop with a stale copy.
g init -q 2>/dev/null
D="$CUBRID_TESTCASES/sql/_13_issues/_26_2h"
mkdir -p "$D/cases" "$D/answers"
printf 'x\n' > "$D/cases/cbrd_99999.sql"
g add -A >/dev/null 2>&1; g commit -qm base >/dev/null 2>&1
g branch -m develop 2>/dev/null
g worktree add -q "$T/wt" -b "$BRANCH" develop 2>/dev/null
printf "evaluate 'Case 1. x';\nSELECT 1;\nevaluate 'Case 2. y';\nSELECT 2;\n" > "$T/wt/sql/_13_issues/_26_2h/cases/cbrd_99999.sql"
git -C "$T/wt" -c user.name=t -c user.email=t@example.com commit -qam "two cases, only on the branch" >/dev/null 2>&1

printf '{"author":{"path":"sql/_13_issues/_26_2h/cases/cbrd_99999.sql","branch":"%s"}}\n' "$BRANCH" > "$RUN/manifest.json"

# ── the variable names the clone; the count must still come from the branch's checkout ───────────
bash "$SRC" "$KEY" >/dev/null 2>&1 || note_fail "render exited non-zero"
_got=$(grep -m1 '케이스' "$RUN/pr-body.md" 2>/dev/null)
case "$_got" in
  *"케이스 2개"*) T_PASS=$((T_PASS+1)) ;;
  *) note_fail "worktree authoring, variable points at the clone: 케이스 line is \"$_got\", expected 2개" ;;
esac

# ── the human sections are why a re-run must not clobber ─────────────────────────────────────────
if bash "$SRC" "$KEY" >/dev/null 2>"$T/err"; then
  note_fail "re-render without --force succeeded — a filled-in Purpose would have been thrown away"
else
  grep -q -- '--force' "$T/err" && T_PASS=$((T_PASS+1)) \
    || note_fail "re-render refusal never mentions --force (got: $(cat "$T/err"))"
fi
bash "$SRC" "$KEY" --force >/dev/null 2>&1 && T_PASS=$((T_PASS+1)) \
  || note_fail "--force re-render failed"

if [ "$T_FAIL" -eq 0 ]; then
  printf 'render-pr-body: %d/%d\n' "$T_PASS" "$T_PASS"
  exit 0
else
  printf 'render-pr-body: %d passed, %d FAILED%s\n' "$T_PASS" "$T_FAIL" "$FAILURES"
  exit 1
fi
