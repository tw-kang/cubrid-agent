#!/bin/bash
# Behavioural test for gate-pr-submit.sh — both directions: what must pass, what must be denied.
#
# Dev-only, run by check-invariants.sh. Deterministic and offline: bash, jq, grep, sed, mktemp.
# It builds a throwaway $HOME with a synthetic manifest and PR body, so it never reads or writes
# the real ~/.cubrid-agent.
#
# A false deny strands an hour of finished work, so the passing cases are the guardrail: every
# spelling of the body flag must survive, and unrelated commands must fall straight through.
set -u

GATE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)/gate-pr-submit.sh
[ -f "$GATE" ] || { echo "test-gate-pr-submit: gate not found at $GATE" >&2; exit 1; }

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
export HOME="$T"
KEY=CBRD-99999
RUN="$T/.cubrid-agent/$KEY"
mkdir -p "$RUN"
GEN="$RUN/pr-body.md"

# `gh` is stubbed for every case: the re-author check calls `gh pr list`, and the real binary would
# make this suite depend on what exists upstream. STUB_GH_FAIL covers the failure path.
STUBBIN="$T/stub"; mkdir -p "$STUBBIN"; export PATH="$STUBBIN:$PATH"
cat > "$STUBBIN/gh" <<'STUB'
#!/bin/bash
[ -n "${STUB_GH_FAIL:-}" ] && { echo "gh: not authenticated" >&2; exit 4; }
if [ -n "${STUB_GH_PRS:-}" ] && [ -f "${STUB_GH_PRS}" ]; then cat "$STUB_GH_PRS"; else echo '[]'; fi
STUB
chmod +x "$STUBBIN/gh"

# Every artifact condition satisfied, so only the body checks decide the outcome.
cat > "$RUN/manifest.json" <<'JSON'
{"verify":{"determinism":{"all_pass":true},"fail_to_pass":{"status":"confirmed"},"cci":{"checked":true},
           "debug":{"checked":true,"result":"clean"}},
 "review":{"verdict":"PASS"},
 "lint":{"header":true,"evaluate":true,"cleanup":true,"answer_not_handwritten":true,
         "english_comments":true,"header_scope":true,"header_size":true,"placement":true}}
JSON

# The shape render-pr-body.sh emits once the author has written the two TODO sections.
good_body() {
  cat > "$GEN" <<'MD'
<http://jira.cubrid.org/browse/CBRD-99999>

### Purpose

컬렉션 안 서브쿼리가 서버를 죽였다.

### Implementation

거부되는지와 정상 컬렉션이 여전히 성공하는지를 검증한다.

### Remarks

- 케이스 7개(`.sql` 헤더의 Coverage 참조), 전제 검증됨
- 검증: `11.4.0.1234`, 결정성 3회 PASS, CCI 동일, .answer 생성됨
- fail→pass **confirmed**: pre-fix `11.4.0.1200` FAIL → `11.4.0.1234` PASS
MD
}

T_PASS=0; T_FAIL=0
FAILURES=""

# run <name> <ok|deny> <expected reason fragment, or ""> <command>
run() {
  _name=$1; _want=$2; _frag=$3; _cmd=$4
  _out=$(printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$_cmd" | jq -Rs .)" | bash "$GATE" 2>&1)
  _rc=$?
  _got=ok; [ "$_rc" -ne 0 ] && _got=deny
  if [ "$_got" != "$_want" ]; then
    T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    $_name: expected $_want, got $_got"
    return
  fi
  if [ -n "$_frag" ] && ! printf '%s' "$_out" | grep -qF -- "$_frag"; then
    T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    $_name: denied, but the reason never says \"$_frag\""
    return
  fi
  T_PASS=$((T_PASS+1))
}

BASE="gh pr create --repo CUBRID/cubrid-testcases --base develop --head tw-kang:tc/cbrd-99999"

# --- must pass: every body-flag spelling, and commands outside the gate's business -------------
good_body
run "absolute --body-file"      ok "" "$BASE --body-file $GEN"
run "-F short flag"             ok "" "$BASE -F $GEN"
run "unexpanded \$HOME"         ok "" "$BASE --body-file \$HOME/.cubrid-agent/$KEY/pr-body.md"
run "tilde path"                ok "" "$BASE --body-file ~/.cubrid-agent/$KEY/pr-body.md"
run "--body-file=path"          ok "" "$BASE --body-file=$GEN"
run "quoted path"               ok "" "$BASE --body-file \"$GEN\""
run "not a pr create"           ok "" "gh pr list --repo CUBRID/cubrid-testcases"
run "another repo"              ok "" "gh pr create --repo CUBRID/cubrid --head x:tc/cbrd-99999"

# --- must be denied ----------------------------------------------------------------------------
run "no body flag"              deny "no --body-file/-F"     "$BASE"
run "inline --body"             deny "--body/--fill instead" "$BASE --body 'hand written'"
run "--fill"                    deny "--body/--fill instead" "$BASE --fill"
run "some other path"           deny "not the generated"     "$BASE --body-file /tmp/body.md"

mv "$GEN" "$GEN.away"
run "right path, no file"       deny "does not exist"        "$BASE --body-file $GEN"
mv "$GEN.away" "$GEN"

good_body; printf '\nTODO\n' >> "$GEN"
run "TODO left in"              deny "TODO placeholder"      "$BASE --body-file $GEN"
run "TODO left in, --draft"     deny "TODO placeholder"      "$BASE --draft --body-file $GEN"

good_body; sed -i 's/^### Remarks$//' "$GEN"
run "section missing"           deny "missing section(s): Remarks" "$BASE --body-file $GEN"

good_body; sed -i 's/케이스 7개/케이스 ?개/' "$GEN"
run "case count is ?"           deny "case count is '?'"     "$BASE --body-file $GEN"

good_body; sed -i '1d' "$GEN"
run "no jira link"              deny "no jira link"          "$BASE --body-file $GEN"

# --- base sanity: a synthetic clone, so no network and no dependence on this machine's checkout ---
# CUBRID_TESTCASES is exported only for this block, so the cases above keep the "no clone -> skip" path.
good_body
TCD="$T/tc"
git init -q "$TCD"
G="git -C $TCD -c user.email=t@t -c user.name=t"
mkdir -p "$TCD/sql/_36_guava/cbrd_99999/cases"
echo "-- tc" > "$TCD/sql/_36_guava/cbrd_99999/cases/cbrd_99999.sql"
$G add -A >/dev/null; $G commit -qm base
$G update-ref refs/remotes/origin/develop HEAD          # what a fetched origin/develop looks like
BASESHA=$($G rev-parse HEAD)
$G remote add origin https://github.com/CUBRID/cubrid-testcases.git
$G checkout -q -b tc/cbrd-99999
echo "evaluate 'Case 1';" >> "$TCD/sql/_36_guava/cbrd_99999/cases/cbrd_99999.sql"
$G add -A >/dev/null; $G commit -qm tc
export CUBRID_TESTCASES="$TCD"

run "base ok: only the TC dir"   ok   ""                       "$BASE --body-file $GEN"

$G remote set-url origin https://github.com/someone/cubrid-testcases.git
run "origin is a fork"           deny "not CUBRID/cubrid-testcases" "$BASE --body-file $GEN"
$G remote set-url origin https://github.com/CUBRID/cubrid-testcases.git

$G remote remove origin        # note: this also drops refs/remotes/origin/*, so restore the ref after
run "no origin remote"           deny "no 'origin' remote"      "$BASE --body-file $GEN"
$G remote add origin https://github.com/CUBRID/cubrid-testcases.git
$G update-ref refs/remotes/origin/develop "$BASESHA"

echo stray > "$TCD/unrelated.txt"; $G add -A >/dev/null; $G commit -qm stray
run "stray file outside the TC"  deny "not this TC's"          "$BASE --body-file $GEN"
$G reset -q --hard HEAD~1

$G update-ref -d refs/remotes/origin/develop
run "origin/develop not fetched" deny "origin/develop is not in" "$BASE --body-file $GEN"
$G update-ref refs/remotes/origin/develop "$BASESHA"

# --- the same base sanity in the layout every bug fix uses --------------------------------------
# Under _13_issues/_YY_Nh/ the whole half-year shares cases/ and answers/, so a directory-scoped
# filter counts the TC's OWN files as strays. Every Correct Error goes here — the common case.
TCD2="$T/tc13"
git init -q "$TCD2"
G2="git -C $TCD2 -c user.email=t@t -c user.name=t"
mkdir -p "$TCD2/sql/_13_issues/_26_2h/cases" "$TCD2/sql/_13_issues/_26_2h/answers"
echo "-- sibling TC of the same half-year" > "$TCD2/sql/_13_issues/_26_2h/cases/cbrd_99998.sql"
$G2 add -A >/dev/null; $G2 commit -qm base
$G2 update-ref refs/remotes/origin/develop HEAD
BASESHA2=$($G2 rev-parse HEAD)
$G2 remote add origin https://github.com/CUBRID/cubrid-testcases.git
$G2 checkout -q -b tc/cbrd-99999
echo "evaluate 'Case 1';" > "$TCD2/sql/_13_issues/_26_2h/cases/cbrd_99999.sql"
echo "ok" > "$TCD2/sql/_13_issues/_26_2h/answers/cbrd_99999.answer"
$G2 add -A >/dev/null; $G2 commit -qm tc
export CUBRID_TESTCASES="$TCD2"

run "bug-fix layout: only the TC's files" ok "" "$BASE --body-file $GEN"

echo stray > "$TCD2/unrelated.txt"; $G2 add -A >/dev/null; $G2 commit -qm stray
run "bug-fix layout: a real stray"        deny "not this TC's" "$BASE --body-file $GEN"
$G2 reset -q --hard HEAD~1

export CUBRID_TESTCASES="$TCD"
$G update-ref refs/remotes/origin/develop "$BASESHA"

# --- the variable travels in the command, not in the hook's env -----------------------------------
# An inline CUBRID_TESTCASES=<path> reaches the command's child, never a PreToolUse hook, so the gate
# must read it out of the command string. The deny below fires only if the embedded path was honoured.
echo stray > "$TCD2/unrelated.txt"; $G2 add -A >/dev/null; $G2 commit -qm stray
_saved_tc=$CUBRID_TESTCASES; unset CUBRID_TESTCASES
run "embedded CUBRID_TESTCASES is honoured" deny "not this TC's" \
    "CUBRID_TESTCASES=$TCD2 $BASE --body-file $GEN"
# The command text reaches the hook pre-expansion, exactly like the body path above — an unexpanded
# $HOME must not make the base check silently skip.
run "embedded value with unexpanded \$HOME"  deny "not this TC's" \
    "CUBRID_TESTCASES=\$HOME/${TCD2##*/} $BASE --body-file $GEN"
export CUBRID_TESTCASES="$_saved_tc"
# When both speak, the command wins: the inline assignment is what the command will actually run
# under, while the hook's env is whatever the harness happened to inherit.
run "embedded value beats the hook's env"    deny "not this TC's" \
    "CUBRID_TESTCASES=$TCD2 $BASE --body-file $GEN"
$G2 reset -q --hard HEAD~1

unset CUBRID_TESTCASES

# --- re-authoring over an existing upstream PR: a decision, not an accident --------------------
# The gate asks for the reason rather than forbidding the re-author. This PR is on someone ELSE's
# fork — the case a branch check cannot see.
good_body
PRFIX="$T/prs.json"
echo '[{"number":3049,"state":"OPEN","author":{"login":"another-operator"}}]' > "$PRFIX"
STUB_GH_PRS="$PRFIX" run "existing PR, no reason"   deny "PR #3049 (OPEN, another-operator) already exists" "$BASE --body-file $GEN"
run "no PR upstream"                                ok   ""  "$BASE --body-file $GEN"
STUB_GH_PRS="$PRFIX" STUB_GH_FAIL=1 \
  run "gh failure is not a deny"                    ok   ""  "$BASE --body-file $GEN"
jq '.select.reauthor_reason = "PoC PR #3049 predates the pipeline; redoing it with a generated answer"' \
  "$RUN/manifest.json" > "$RUN/m.tmp" && mv "$RUN/m.tmp" "$RUN/manifest.json"
STUB_GH_PRS="$PRFIX" run "existing PR + recorded reason" ok "" "$BASE --body-file $GEN"
jq 'del(.select.reauthor_reason)' "$RUN/manifest.json" > "$RUN/m.tmp" && mv "$RUN/m.tmp" "$RUN/manifest.json"

# --- the debug build: an assert blocks outright, a difference can be explained -----------------
good_body
m() { jq "$1" "$RUN/manifest.json" > "$RUN/m.tmp" && mv "$RUN/m.tmp" "$RUN/manifest.json"; }
m 'del(.verify.debug)'
run "debug never checked"        deny "debug build not checked"      "$BASE --body-file $GEN"
m '.verify.debug = {checked:false, result:"inconclusive"}'
run "debug run was blocked"      deny "debug build not checked"      "$BASE --body-file $GEN"
m '.verify.debug = {checked:true, result:"assert", marker:"assertion failed at page_buffer.c"}'
run "assert blocks outright"     deny "engine finding for the developer" "$BASE --body-file $GEN"
m '.verify.debug = {checked:true, result:"differs"}'
run "unexplained difference"     deny "never promote debug output"   "$BASE --body-file $GEN"
m '.verify.debug = {checked:true, result:"differs", note:"debug-only warning line, absent in release"}'
run "explained difference"       ok   ""                             "$BASE --body-file $GEN"
# An assert clears only through a reviewer and only with the note, like review.failpass_approved.
m '.verify.debug = {checked:true, result:"assert", marker:"assertion failed at page_buffer.c"} | .review.debug_approved = true'
run "assert, approved but unexplained" deny "review.debug_approved=true plus verify.debug.note" "$BASE --body-file $GEN"
m '.verify.debug.note = "CBRD-27000: known assert on this path, developer accepted it as out of scope"'
run "assert, reviewer-approved with a note" ok "" "$BASE --body-file $GEN"
m 'del(.review.debug_approved) | .verify.debug = {checked:true, result:"clean"}'

# --- the artifact conditions still gate, and they report first ---------------------------------
good_body
jq '.review.verdict = "NEEDS-WORK"' "$RUN/manifest.json" > "$RUN/m.tmp" && mv "$RUN/m.tmp" "$RUN/manifest.json"
run "review not passed"         deny "review not passed"     "$BASE --body-file $GEN"

if [ "$T_FAIL" -eq 0 ]; then
  printf 'gate-pr-submit: %d/%d\n' "$T_PASS" "$T_PASS"
  exit 0
else
  printf 'gate-pr-submit: %d passed, %d FAILED%s\n' "$T_PASS" "$T_FAIL" "$FAILURES"
  exit 1
fi
