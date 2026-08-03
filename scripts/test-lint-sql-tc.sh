#!/bin/bash
# Behavioural test for lint-sql-tc.sh — the PostToolUse hook whose fields the submit gate blocks on.
#
# Dev-only, run by check-invariants.sh. Offline: a throwaway $HOME, a throwaway testcase tree, and a
# manifest the hook patches. Nothing else on the machine is touched.
#
# It exists because the hook shipped with a header check that matched `/**` and the issue key on the SAME
# line, while the corpus convention puts the key on the next one — 0 of the 47 corpus testcases with a
# header block passed it, so `lint.header` was false for every correctly authored testcase and the submit
# gate blocked all of them. Nothing tested the hook, so nothing said so. Each case below is a rule the
# gate can refuse work over; the fixtures are shaped like real corpus files, not like the checks.
set -u

HOOK=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)/lint-sql-tc.sh
[ -f "$HOOK" ] || { echo "test-lint-sql-tc: hook not found at $HOOK" >&2; exit 1; }

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
export CUBRID_TESTCASES="$T/tc"
KEY=CBRD-99999
RUN="$HOME/.cubrid-agent/$KEY"
mkdir -p "$RUN"

# The half-year the hook expects is derived from today, exactly as create-sql's rule says, so this test
# does not rot on 1 January.
HALF="_$(date +%y)_$([ "$(date +%-m)" -le 6 ] && echo 1 || echo 2)h"
BUG_DIR="$CUBRID_TESTCASES/sql/_13_issues/$HALF/cases"
REL_DIR="$CUBRID_TESTCASES/sql/_36_guava/cbrd_99999/cases"
mkdir -p "$BUG_DIR" "$REL_DIR"

T_PASS=0; T_FAIL=0; FAILURES=""
note_fail() { T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    $1"; }

seed_manifest() {  # seed_manifest [issue type]
  if [ $# -eq 1 ]; then printf '{"select":{"issue_type":"%s"}}\n' "$1" > "$RUN/manifest.json"
  else printf '{}\n' > "$RUN/manifest.json"; fi
}
lint() {  # lint <file> -> runs the hook, leaves the manifest patched
  printf '{"tool_input":{"file_path":"%s"}}' "$1" | bash "$HOOK" > "$T/out" 2>&1
}
field() { jq -r --arg k "$1" '(.lint // {}) | if has($k) then (.[$k]|tostring) else "absent" end' "$RUN/manifest.json"; }
expect() {  # expect <name> <field> <want>
  _got=$(field "$2")
  [ "$_got" = "$3" ] && T_PASS=$((T_PASS+1)) || note_fail "$1: lint.$2 is \"$_got\", expected \"$3\""
}
says() {  # says <name> <fragment>
  grep -qF -- "$2" "$T/out" && T_PASS=$((T_PASS+1)) || note_fail "$1: the message never mentions \"$2\""
}

# The shape every corpus testcase uses: block opens on its own line, key on the next.
good_header() {
  printf '/**\n * This test case verifies %s: a thing that must hold.\n *\n * Coverage:\n * 1. The thing.\n */\n' "$1"
}
body() {
  printf -- '--+ server-message on\n\nDROP TABLE IF EXISTS t1;\nCREATE TABLE t1(c1 int);\n\n'
  printf "evaluate 'Case 1. The thing';\nSELECT 1 FROM t1;\n\nDROP TABLE t1;\n\n"
  printf -- '--+ server-message off\n'
}

# ── the regression that shipped: a corpus-shaped header must be recognised ─────────────────────────
seed_manifest "Correct Error"
{ good_header CBRD-99999; body; } > "$BUG_DIR/cbrd_99999.sql"
lint "$BUG_DIR/cbrd_99999.sql"
expect "corpus-shaped header" header true
expect "corpus-shaped header" header_size true
expect "corpus-shaped header" header_no_dashdash true
expect "corpus-shaped header" evaluate true
expect "corpus-shaped header" cleanup true
expect "corpus-shaped header" english_comments true
expect "corpus-shaped header" placement true

# ── `--` inside the header stops the case running, so it is a violation, not a style note ──────────
seed_manifest "Correct Error"
{ printf '/**\n * This test case verifies CBRD-99999: digits are masked -- so beware.\n */\n'; body; } > "$BUG_DIR/cbrd_99999.sql"
lint "$BUG_DIR/cbrd_99999.sql"
expect "-- in header" header_no_dashdash false
says   "-- in header" "SQL line comment"

# ── the other bounds ──────────────────────────────────────────────────────────────────────────────
seed_manifest "Correct Error"
{ printf -- '-- CBRD-99999 old style, no block\n'; body; } > "$BUG_DIR/cbrd_99999.sql"
lint "$BUG_DIR/cbrd_99999.sql"
expect "no header block" header false

seed_manifest "Correct Error"
{ printf '/**\n'; i=0; while [ "$i" -lt 21 ]; do printf ' * CBRD-99999 line %s\n' "$i"; i=$((i+1)); done; printf ' */\n'; body; } > "$BUG_DIR/cbrd_99999.sql"
lint "$BUG_DIR/cbrd_99999.sql"
expect "header over 20 lines" header_size false

seed_manifest "Correct Error"
{ good_header CBRD-99999; printf 'DROP TABLE IF EXISTS t1;\nCREATE TABLE t1(c1 int);\nSELECT 1;\nDROP TABLE t1;\n'; } > "$BUG_DIR/cbrd_99999.sql"
lint "$BUG_DIR/cbrd_99999.sql"
expect "no evaluate label" evaluate false

seed_manifest "Correct Error"
{ good_header CBRD-99999; printf "CREATE TABLE t1(c1 int);\nevaluate 'Case 1. x';\nSELECT 1;\n"; } > "$BUG_DIR/cbrd_99999.sql"
lint "$BUG_DIR/cbrd_99999.sql"
expect "CREATE without DROP IF EXISTS" cleanup false

seed_manifest "Correct Error"
{ good_header CBRD-99999; body; printf -- '-- 한글 주석은 금지다\n'; } > "$BUG_DIR/cbrd_99999.sql"
lint "$BUG_DIR/cbrd_99999.sql"
expect "non-English comment" english_comments false

# ── placement: the issue type alone decides the tree, and an unknown type is not a pass ────────────
seed_manifest "Correct Error"
{ good_header CBRD-99999; body; } > "$REL_DIR/cbrd_99999.sql"
lint "$REL_DIR/cbrd_99999.sql"
expect "bug fix in a release dir" placement false

seed_manifest "Improve Function/Performance"
lint "$REL_DIR/cbrd_99999.sql"
expect "improvement in a release dir" placement true

seed_manifest
{ good_header CBRD-99999; body; } > "$BUG_DIR/cbrd_99999.sql"
lint "$BUG_DIR/cbrd_99999.sql"
expect "no issue type recorded" placement null

# --- length advice: reported, never recorded, never a violation ----------------------------------
# The gate fields are a 20-line ceiling and nothing at all about comment volume, and writing to a
# ceiling lands well above the practice — a 17-line header and five comment lines shipped with every
# gate green. The advice quotes the corpus quartile instead of inventing a limit, so it must fire on
# the top quartile, stay silent below it, and leave the recorded fields untouched either way.
never_says() {  # never_says <name> <fragment>
  grep -qF -- "$2" "$T/out" && note_fail "$1: the message says \"$2\" when it should not" || T_PASS=$((T_PASS+1))
}
long_header() {  # long_header <key> <total lines>
  printf '/**\n * This test case verifies %s: a thing that must hold.\n * Coverage:\n' "$1"
  _i=1; while [ "$_i" -le $(( $2 - 4 )) ]; do
    printf ' * %d. Case %d does a thing worth one whole line of prose.\n' "$_i" "$_i"; _i=$((_i+1))
  done
  printf ' */\n'
}
chatty_body() {  # body carrying five inline -- comments
  printf -- '--+ server-message on\n\n-- one\n-- two\n-- three\n-- four\n-- five\n'
  printf 'DROP TABLE IF EXISTS t1;\nCREATE TABLE t1(c1 int);\n\n'
  printf "evaluate 'Case 1. The thing';\nSELECT 1 FROM t1;\n\nDROP TABLE t1;\n\n"
  printf -- '--+ server-message off\n'
}

seed_manifest "Correct Error"
{ good_header CBRD-99999; body; } > "$BUG_DIR/cbrd_99999.sql"
lint "$BUG_DIR/cbrd_99999.sql"
never_says "a short header draws no advice" "corpus p75"

{ long_header CBRD-99999 17; body; } > "$BUG_DIR/cbrd_99999.sql"
lint "$BUG_DIR/cbrd_99999.sql"
says   "a 17-line header draws advice"      "header is 17 lines against a corpus p75 of 16"
expect "  ... and is still within the gate" header_size true

{ good_header CBRD-99999; chatty_body; } > "$BUG_DIR/cbrd_99999.sql"
lint "$BUG_DIR/cbrd_99999.sql"
says   "five inline comments draw advice"   "5 inline"
expect "  ... and record nothing"           header_size true
never_says "  ... and are not a violation"  "convention violations"

{ long_header CBRD-99999 16; body; } > "$BUG_DIR/cbrd_99999.sql"
lint "$BUG_DIR/cbrd_99999.sql"
never_says "the p75 itself is not flagged"  "corpus p75 of 16"

if [ "$T_FAIL" -eq 0 ]; then
  printf 'lint-sql-tc: %d/%d\n' "$T_PASS" "$T_PASS"
  exit 0
else
  printf 'lint-sql-tc: %d passed, %d FAILED%s\n' "$T_PASS" "$T_FAIL" "$FAILURES"
  exit 1
fi
