#!/bin/bash
# Behavioural test for gate-pr-submit.sh — both directions: what must pass, what must be denied.
#
# Dev-only, run by check-invariants.sh. Deterministic and offline: bash, jq, grep, sed, mktemp.
# It builds a throwaway $HOME with a synthetic manifest and PR body, so it never reads or writes
# the real ~/.cubrid-agent.
#
# This gate is the last step of a ~1-hour pipeline, so a wrong check costs more than a missing one:
# a false deny strands finished work. The passing cases below are that guardrail — every spelling of
# the body flag a human or skill actually types (-F, --body-file=, quoted, ~, an unexpanded $HOME)
# must survive, and every command the gate has no business touching must fall straight through.
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

# `gh` is stubbed for every case, not just the ones about it: the gate's re-author check calls
# `gh pr list`, and with the real binary on PATH this suite would query GitHub 30 times and change
# answer depending on what exists upstream. The fixture decides; STUB_GH_FAIL covers the failure path,
# which must never turn into a deny.
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
# CUBRID_TESTCASES is exported only for this block, so the cases above keep exercising the
# "clone not found -> skip" path regardless of where these tests are appended.
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
run "stray file outside the TC"  deny "outside cbrd_99999/"     "$BASE --body-file $GEN"
$G reset -q --hard HEAD~1

$G update-ref -d refs/remotes/origin/develop
run "origin/develop not fetched" deny "origin/develop is not in" "$BASE --body-file $GEN"
$G update-ref refs/remotes/origin/develop "$BASESHA"

unset CUBRID_TESTCASES

# --- re-authoring over an existing upstream PR: a decision, not an accident --------------------
# A targeted call skips Select's already-processed screen on purpose, so the gate asks for the reason
# rather than forbidding the re-author. The PR here is on someone ELSE's fork — the case a branch check
# cannot see, and the one that ends in two PRs for one issue.
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
m '.verify.debug = {checked:true, result:"clean"}'

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
