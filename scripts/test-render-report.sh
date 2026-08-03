#!/bin/bash
# Behavioural test for render-report.sh — the commit proof it prints under ## Author.
#
# Dev-only, run by check-invariants.sh. Offline: a throwaway $HOME and a throwaway git repo shaped like
# the testcase corpus. Nothing else on the machine is touched.
#
# What it pins: the proof counts the TC's own files in both directory layouts, never a sibling TC's,
# and says "커밋되지 않았다" whenever the `.sql` is not on the branch — including when its `.answer`
# already is. Why the scope has to work that way is in render-report.sh's own comment.
set -u

BIN_DIR=$(cd "$(dirname "$(readlink -f "$0")")/../skills/qa/setup-cubrid-agent/bin" && pwd)
SRC="$BIN_DIR/render-report.sh"
[ -f "$SRC" ] || { echo "test-render-report: script not found at $SRC" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "test-render-report: jq is required." >&2; exit 1; }

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
export CUBRID_TESTCASES="$T/tc"
KEY=CBRD-99999
BRANCH=tc/cbrd-99999
RUN="$HOME/.cubrid-agent/$KEY"
REPORT="$HOME/.cubrid-agent/reports/author-testcase/$KEY.md"
mkdir -p "$RUN" "$CUBRID_TESTCASES"

T_PASS=0; T_FAIL=0; FAILURES=""
note_fail() { T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    $1"; }

g() { git -C "$CUBRID_TESTCASES" -c user.name=t -c user.email=t@example.com "$@"; }
seed() {  # seed <tc path relative to $TC>
  printf '{"author":{"path":"%s","branch":"%s"}}\n' "$1" "$BRANCH" > "$RUN/manifest.json"
}
render() {  # clear first: a stale report must not be what the next assertion reads
  rm -f "$REPORT"
  bash "$SRC" "$KEY" --force >/dev/null 2>&1 || note_fail "render-report exited non-zero"
}
expect_proof() {  # expect_proof <name> <fragment the 커밋 상태 line must contain>
  _got=$(grep -m1 '커밋 상태' "$REPORT" 2>/dev/null)
  case "$_got" in
    *"$2"*) T_PASS=$((T_PASS+1)) ;;
    *)      note_fail "$1: 커밋 상태 line is \"$_got\", expected it to contain \"$2\"" ;;
  esac
}

g init -q 2>/dev/null
g checkout -q -b "$BRANCH" 2>/dev/null

# ── _13_issues layout: cases/ and answers/ are shared by every TC of the half-year ────────────────
# The half-year string is fixed on purpose: what is under test is the layout, not create-sql's date rule.
BUG="$CUBRID_TESTCASES/sql/_13_issues/_26_2h"
mkdir -p "$BUG/cases" "$BUG/answers"
printf 'x\n' > "$BUG/cases/cbrd_99998.sql"
printf 'x\n' > "$BUG/answers/cbrd_99998.answer"
g add -A >/dev/null 2>&1; g commit -q -m "sibling TC" >/dev/null 2>&1

# The case the old scope got wrong: our TC is written but never committed, and a sibling is.
printf 'x\n' > "$BUG/cases/cbrd_99999.sql"
seed "sql/_13_issues/_26_2h/cases/cbrd_99999.sql"; render
expect_proof "uncommitted TC beside a committed sibling" "커밋되지 않았다"

# The .sql is the work. An .answer committed beside an uncommitted .sql is exactly the "work that is
# not there" the proof exists to catch, and a filename count alone cannot see it.
printf 'x\n' > "$BUG/answers/cbrd_99999.answer"
g add -A -- "$BUG/answers" >/dev/null 2>&1; g commit -q -m "answer only" >/dev/null 2>&1
render
expect_proof "answer committed, .sql not" "커밋되지 않았다"

g add -A >/dev/null 2>&1; g commit -q -m "our TC" >/dev/null 2>&1
render
expect_proof "committed TC beside a sibling" "2개 파일"

printf 'x\n' > "$BUG/answers/cbrd_99999.answer_cci"
g add -A >/dev/null 2>&1; g commit -q -m "cci sidecar" >/dev/null 2>&1
render
expect_proof "the CCI sidecar counts too" "3개 파일"

# ── one issue, several .sql files ─────────────────────────────────────────────────────────────────
# create-sql's convention suffixes them off the same key and shares the one cases/+answers/ pair, so
# they are this TC's files and the proof must count them. A separate half-year tree keeps this case
# from mixing with the files committed above.
SUF="$CUBRID_TESTCASES/sql/_13_issues/_26_1h"
mkdir -p "$SUF/cases" "$SUF/answers"
printf 'x\n' > "$SUF/cases/cbrd_99999_select.sql"
printf 'x\n' > "$SUF/cases/cbrd_99999_update.sql"
printf 'x\n' > "$SUF/answers/cbrd_99999_select.answer"
printf 'x\n' > "$SUF/answers/cbrd_99999_update.answer"
g add -A >/dev/null 2>&1; g commit -q -m "suffixed pair" >/dev/null 2>&1
seed "sql/_13_issues/_26_1h/cases/cbrd_99999_select.sql"; render
expect_proof "suffixed .sql files count" "4개 파일"

# ── _36_guava layout: the TC owns its directory ───────────────────────────────────────────────────
REL="$CUBRID_TESTCASES/sql/_36_guava/cbrd_99999"
mkdir -p "$REL/cases" "$REL/answers"
printf 'x\n' > "$REL/cases/cbrd_99999.sql"
printf 'x\n' > "$REL/answers/cbrd_99999.answer"
g add -A >/dev/null 2>&1; g commit -q -m "release-dir TC" >/dev/null 2>&1
seed "sql/_36_guava/cbrd_99999/cases/cbrd_99999.sql"; render
expect_proof "release-dir layout still counts its own two files" "2개 파일"

if [ "$T_FAIL" -eq 0 ]; then
  printf 'render-report: %d/%d\n' "$T_PASS" "$T_PASS"
  exit 0
else
  printf 'render-report: %d passed, %d FAILED%s\n' "$T_PASS" "$T_FAIL" "$FAILURES"
  exit 1
fi
