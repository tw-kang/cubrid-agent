#!/bin/bash
# Behavioural test for verify-run.sh's run directory. Dev-only, run by check-invariants.sh.
#
# Narrow on purpose: with no CTP present verify-run blocks before running anything, which is enough to
# pin WHERE it writes.
set -u

BIN_DIR=$(cd "$(dirname "$(readlink -f "$0")")/../skills/qa/setup-cubrid-agent/bin" && pwd)
SRC="$BIN_DIR/verify-run.sh"
[ -f "$SRC" ] || { echo "test-verify-run: script not found at $SRC" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "test-verify-run: jq is required." >&2; exit 1; }

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
KEY=CBRD-99999

T_PASS=0; T_FAIL=0; FAILURES=""
note_fail() { T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    $1"; }
# timeout, because the failure this pins is a hang: `shift 2` with one argument left does not shift,
# so a value-less flag spins the parser forever.
run() { OUT=$(env -u CTP_HOME -u CUBRID -u CUBRID_TESTCASES HOME="$T/home" timeout 20 bash "$SRC" "$@" 2>&1); RC=$?; }

# ── --run-dir decides where the record lands ─────────────────────────────────────────────────────
PRDIR="$T/home/.cubrid-agent/PR-3091"
run "$KEY" --run-dir "$PRDIR"
[ -f "$PRDIR/manifest.json" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "--run-dir: nothing was written to $PRDIR (rc=$RC out=$OUT)"
# The authoring run for the same issue must be left alone — that is the whole point of the flag.
[ -e "$T/home/.cubrid-agent/$KEY" ] \
  && note_fail "--run-dir: it wrote to the issue's own run directory as well" || T_PASS=$((T_PASS+1))

# ── without it, the issue's run directory, exactly as before ─────────────────────────────────────
rm -rf "$T/home"
run "$KEY"
[ -f "$T/home/.cubrid-agent/$KEY/manifest.json" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "no --run-dir: expected the record under the issue key (rc=$RC out=$OUT)"

# ── a relative --run-dir would land under whatever cwd the caller had ────────────────────────────
run "$KEY" --run-dir relative-dir
case "$OUT" in *'must be an absolute path'*) [ "$RC" -ne 0 ] && T_PASS=$((T_PASS+1)) ;;
  *) note_fail "--run-dir relative: expected a refusal, got rc=$RC out=$OUT" ;; esac
[ ! -e "relative-dir" ] && T_PASS=$((T_PASS+1)) || { rm -rf relative-dir; note_fail "--run-dir relative: it created a directory in the cwd"; }

# ── the conf must point CTP at the tree the caller named ─────────────────────────────────────────
# A conf left on the default clone verifies a different branch and still reports Success.
CTP="$T/ctp"; mkdir -p "$CTP/bin" "$CTP/conf"
printf '#!/bin/sh\nexit 0\n' > "$CTP/bin/ctp.sh"; chmod +x "$CTP/bin/ctp.sh"
printf 'scenario=/somewhere/else/sql\nport=33000\n' > "$CTP/conf/sql.conf"
CU="$T/cubrid"; mkdir -p "$CU/bin"
printf '#!/bin/sh\necho "CUBRID 11.5.0.2300-04192d6 (Linux)"\n' > "$CU/bin/cubrid_rel"; chmod +x "$CU/bin/cubrid_rel"
WT="$T/wt/sql/_13_issues/_26_2h"; mkdir -p "$WT/cases" "$WT/answers"
printf "evaluate 'Case 1. x';\nSELECT 1;\n" > "$WT/cases/cbrd_99999.sql"
printf 'ok\n' > "$WT/answers/cbrd_99999.answer"
PRDIR2="$T/home/.cubrid-agent/PR-1"
HOME="$T/home" CTP_HOME="$CTP" CUBRID="$CU" CUBRID_TESTCASES="$T/wt" timeout 30 bash "$SRC" "$KEY" \
  --tc-path sql/_13_issues/_26_2h/cases/cbrd_99999.sql --run-dir "$PRDIR2" --no-manifest --runs 1 >/dev/null 2>&1
_scen=$(grep -m1 '^scenario=' "$PRDIR2/sql.conf" 2>/dev/null)
[ "$_scen" = "scenario=$T/wt/sql" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "conf scenario: expected scenario=$T/wt/sql, got \"$_scen\""
# --no-manifest must stay a promise about the record, not about the log.
[ -f "$PRDIR2/verify-sql.log" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "the run log did not land in --run-dir"
[ ! -f "$PRDIR2/manifest.json" ] && T_PASS=$((T_PASS+1)) \
  || note_fail "--no-manifest still wrote a manifest"

# ── every value-taking flag must refuse a missing value, not spin ────────────────────────────────
for f in --run-dir --runs --category --tc-path --timeout --from --log-label; do
  run "$KEY" "$f"
  if [ "$RC" -eq 124 ]; then note_fail "$f with no value: it hung (the parser never terminated)"
  elif [ "$RC" -eq 0 ]; then note_fail "$f with no value: accepted silently"
  else T_PASS=$((T_PASS+1)); fi
done

if [ "$T_FAIL" -eq 0 ]; then
  printf 'verify-run: %d/%d\n' "$T_PASS" "$T_PASS"
  exit 0
else
  printf 'verify-run: %d passed, %d FAILED%s\n' "$T_PASS" "$T_FAIL" "$FAILURES"
  exit 1
fi
