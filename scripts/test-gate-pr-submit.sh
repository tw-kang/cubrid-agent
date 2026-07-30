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

# Every artifact condition satisfied, so only the body checks decide the outcome.
cat > "$RUN/manifest.json" <<'JSON'
{"verify":{"determinism":{"all_pass":true},"fail_to_pass":{"status":"confirmed"},"cci":{"checked":true}},
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
