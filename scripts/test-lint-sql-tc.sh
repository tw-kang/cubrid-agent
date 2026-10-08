#!/bin/bash
# Behavioural test for lint-sql-tc.sh — the PostToolUse hook whose fields the submit gate blocks on.
#
# Dev-only, run by check-invariants.sh. Offline: a throwaway $HOME, a throwaway testcase tree, and a
# manifest the hook patches. Nothing else on the machine is touched.
#
# Each case is a rule the submit gate can refuse work over. The fixtures are shaped like real corpus
# files, not like the checks — a header check once matched a shape the corpus never uses, and every
# correctly authored testcase failed it.
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
body_with() {  # body_with <label line> — the same body, with the evaluate label swapped
  printf -- '--+ server-message on\n\nDROP TABLE IF EXISTS t1;\nCREATE TABLE t1(c1 int);\n\n'
  printf '%s\n' "$1"
  printf 'SELECT 1 FROM t1;\n\nDROP TABLE t1;\n\n'
  printf -- '--+ server-message off\n'
}
body() { body_with "evaluate 'Case 1. The thing';"; }

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
expect "corpus-shaped header" header_no_semicolon true
expect "corpus-shaped header" evaluate_quotes true
expect "corpus-shaped header" evaluate_terminator true
expect "corpus-shaped header" prepare_released true
expect "corpus-shaped header" directives true

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
# No label at all is one missing label, never a malformed one: both label rules see an empty set here,
# and a grep that reports "some line does not match" for no lines would fail every such file.
expect "  ... and no malformed one" evaluate_quotes true
expect "  ... and no malformed one" evaluate_terminator true

seed_manifest "Correct Error"
{ good_header CBRD-99999; printf "CREATE TABLE t1(c1 int);\nevaluate 'Case 1. x';\nSELECT 1;\n"; } > "$BUG_DIR/cbrd_99999.sql"
lint "$BUG_DIR/cbrd_99999.sql"
expect "CREATE without DROP IF EXISTS" cleanup false

seed_manifest "Correct Error"
{ good_header CBRD-99999; body; printf -- '-- 한글 주석은 금지다\n'; } > "$BUG_DIR/cbrd_99999.sql"
lint "$BUG_DIR/cbrd_99999.sql"
expect "non-English comment" english_comments false

# ── CTP's line splitter: five shapes that make it read the file as something else ──────────────────
# CTP reads a .sql line by line (CTP/sql/.../common/SQLParser.java): it flushes a statement at the
# first line that ENDS in `;`, and it takes a line whose first character is `@`, `$` or `--+` as a
# directive instead of SQL. Every one of these was checked by hand against that java source, twice in
# the same rehearsal. Measured over the 488 corpus `cases/cbrd_*.sql` on 2026-08-13, each rule fires on
# 0 of them, so the fixtures below are ordinary testcases with one thing wrong — not check-shaped ones.

# A `;` inside the header flushes the statement there, so the `/**` comment block never closes.
seed_manifest "Correct Error"
{ printf '/**\n * This test case verifies CBRD-99999: the count stays 1;\n */\n'; body; } > "$BUG_DIR/cbrd_99999.sql"
lint "$BUG_DIR/cbrd_99999.sql"
expect "; ends a header line" header_no_semicolon false
says   "; ends a header line" "never closes"

# An apostrophe inside the label closes the string literal early. Doubling it is the fix, so an even
# count passes: `it''s` is one apostrophe to the server and four on the line.
seed_manifest "Correct Error"
{ good_header CBRD-99999; body_with "evaluate 'Case 1. It's a thing';"; } > "$BUG_DIR/cbrd_99999.sql"
lint "$BUG_DIR/cbrd_99999.sql"
expect "apostrophe in the label" evaluate_quotes false
says   "apostrophe in the label" "closes early"

seed_manifest "Correct Error"
{ good_header CBRD-99999; body_with "evaluate 'Case 1. It''s a thing';"; } > "$BUG_DIR/cbrd_99999.sql"
lint "$BUG_DIR/cbrd_99999.sql"
expect "a doubled apostrophe is the fix" evaluate_quotes true

# The label ends with an apostrophe and a semicolon, in that order. `concat(...)` puts `)` between
# them, which is the corpus's second form (379 of 1,577 label lines) and must pass.
seed_manifest "Correct Error"
{ good_header CBRD-99999; body_with "evaluate 'Case 1. The thing'"; } > "$BUG_DIR/cbrd_99999.sql"
lint "$BUG_DIR/cbrd_99999.sql"
expect "label without the semicolon" evaluate_terminator false
says   "label without the semicolon" "runs into the statement after it"

seed_manifest "Correct Error"
{ good_header CBRD-99999; body_with "evaluate 'Case 1. The thing;'"; } > "$BUG_DIR/cbrd_99999.sql"
lint "$BUG_DIR/cbrd_99999.sql"
expect "semicolon inside the literal" evaluate_terminator false

seed_manifest "Correct Error"
{ good_header CBRD-99999; body_with "evaluate concat('1. ', 'The thing');"; } > "$BUG_DIR/cbrd_99999.sql"
lint "$BUG_DIR/cbrd_99999.sql"
expect "the concat label form" evaluate_terminator true
expect "the concat label form" evaluate_quotes true

# A prepared name left allocated leaks into the cases after it. Both release spellings and the
# release-per-name shape are pinned here because the corpus needs all three; the counts are in the hook.
prepare_body() {  # prepare_body [release line]
  printf -- '--+ server-message on\n\nDROP TABLE IF EXISTS t1;\nCREATE TABLE t1(c1 int);\n\n'
  printf "evaluate 'Case 1. The thing';\n"
  printf "PREPARE st FROM 'SELECT 1 FROM t1';\nEXECUTE st;\n"
  [ $# -eq 1 ] && printf '%s\n' "$1"
  printf '\nDROP TABLE t1;\n\n'
  printf -- '--+ server-message off\n'
}
seed_manifest "Correct Error"
{ good_header CBRD-99999; prepare_body; } > "$BUG_DIR/cbrd_99999.sql"
lint "$BUG_DIR/cbrd_99999.sql"
expect "PREPARE never released" prepare_released false
says   "PREPARE never released" "never released: st"

seed_manifest "Correct Error"
{ good_header CBRD-99999; prepare_body 'DEALLOCATE PREPARE st;'; } > "$BUG_DIR/cbrd_99999.sql"
lint "$BUG_DIR/cbrd_99999.sql"
expect "DEALLOCATE PREPARE releases it" prepare_released true

seed_manifest "Correct Error"
{ good_header CBRD-99999; prepare_body 'drop prepare st;'; } > "$BUG_DIR/cbrd_99999.sql"
lint "$BUG_DIR/cbrd_99999.sql"
expect "DROP PREPARE releases it too" prepare_released true

# Re-preparing one name and releasing it once is legitimate — two corpus testcases prepare `st` a
# dozen times over — so the rule is per name, not a count that has to balance.
seed_manifest "Correct Error"
{ good_header CBRD-99999
  printf -- '--+ server-message on\n\nDROP TABLE IF EXISTS t1;\nCREATE TABLE t1(c1 int);\n\n'
  printf "evaluate 'Case 1. The thing';\n"
  printf "PREPARE st FROM 'SELECT TO_CHAR(?,?)';\nPREPARE st FROM 'SELECT TO_DATE(?,?)';\n"
  printf 'DEALLOCATE PREPARE st;\n\nDROP TABLE t1;\n\n'
  printf -- '--+ server-message off\n'
} > "$BUG_DIR/cbrd_99999.sql"
lint "$BUG_DIR/cbrd_99999.sql"
expect "one name prepared twice, released once" prepare_released true

# A line-leading `@`, `$` or `--+` is a directive to CTP, so a typo in one is silent: the line is
# dropped, mangled, or aborts the parse of everything after it.
seed_manifest "Correct Error"
{ good_header CBRD-99999; printf -- '--+ server message on\n'; body; } > "$BUG_DIR/cbrd_99999.sql"
lint "$BUG_DIR/cbrd_99999.sql"
expect "misspelt --+ directive" directives false
says   "misspelt --+ directive" "never applies"

seed_manifest "Correct Error"
{ good_header CBRD-99999; printf '$varchar, $1, $varchar\n'; body; } > "$BUG_DIR/cbrd_99999.sql"
lint "$BUG_DIR/cbrd_99999.sql"
expect "unpaired \$ parameter list" directives false
says   "unpaired \$ parameter list" "after it is dropped"

seed_manifest "Correct Error"
{ good_header CBRD-99999; printf '$varchar, $1, $varchar, $2\n'; body; } > "$BUG_DIR/cbrd_99999.sql"
lint "$BUG_DIR/cbrd_99999.sql"
expect "a paired \$ parameter list" directives true

seed_manifest "Correct Error"
{ good_header CBRD-99999; body_with "evaluate 'Case 1. The thing';"
  printf '@j = %s{ "a": 1 }%s;\n' "'" "'"; } > "$BUG_DIR/cbrd_99999.sql"
lint "$BUG_DIR/cbrd_99999.sql"
expect "@ before a colon CTP eats" directives false
says   "@ before a colon CTP eats" "connection id"

# `@i = 1;` has no colon, so CTP leaves it alone; `@t1:` is the connection prefix it is there for.
seed_manifest "Correct Error"
# CTP takes any text between the `@` and the colon as the id, so a hyphen or a dot in the name is a
# connection prefix like any other.
{ good_header CBRD-99999; body; printf '@i = 1;\n@t1: SELECT 1 FROM t1;\n@node-1: SELECT 1 FROM t1;\n'; } > "$BUG_DIR/cbrd_99999.sql"
lint "$BUG_DIR/cbrd_99999.sql"
expect "a session variable and a real conn prefix" directives true

# CTP reads `@` as a connection id only where a statement STARTS, so a session variable on a
# continuation line keeps its text — flagging it would fail `select @a, @b:=@a+1 from db_root;` split
# over two lines, which the corpus writes on one.
seed_manifest "Correct Error"
{ good_header CBRD-99999; body
  printf 'SELECT @a,\n@b:=@a+1\nFROM t1;\n'; } > "$BUG_DIR/cbrd_99999.sql"
lint "$BUG_DIR/cbrd_99999.sql"
expect "@ continuing a statement" directives true

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

# ── the session mark ─────────────────────────────────────────────────────────────────────────────
# gate-stop.sh reads $HOME state, so it needs to know whether THIS session touched a testcase. This
# hook is where that is first known. Marking a session that only wrote unrelated files would put the
# reminder back into every project on the machine.
MARKS="$HOME/.cubrid-agent/sessions"
rm -rf "$MARKS"
seed_manifest
printf '{"session_id":"sess-A","tool_input":{"file_path":"%s"}}' "$BUG_DIR/cbrd_99999.sql" > "$T/in"
: > "$BUG_DIR/cbrd_99999.sql"
bash "$HOOK" < "$T/in" > /dev/null 2>&1
[ -f "$MARKS/sess-A" ] && T_PASS=$((T_PASS+1)) || note_fail "linting a TC .sql marks the session"

rm -rf "$MARKS"
printf '%s\n' "x" > "$T/notes.txt"
printf '{"session_id":"sess-B","tool_input":{"file_path":"%s"}}' "$T/notes.txt" \
  | bash "$HOOK" > /dev/null 2>&1
[ -e "$MARKS/sess-B" ] && note_fail "a write outside the testcases tree must not mark the session" \
  || T_PASS=$((T_PASS+1))

if [ "$T_FAIL" -eq 0 ]; then
  printf 'lint-sql-tc: %d/%d\n' "$T_PASS" "$T_PASS"
  exit 0
else
  printf 'lint-sql-tc: %d passed, %d FAILED%s\n' "$T_PASS" "$T_FAIL" "$FAILURES"
  exit 1
fi
