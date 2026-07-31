#!/bin/bash
# Behavioural test for failpass-run.sh — offline, with the build install and CTP stubbed.
#
# Dev-only, run by check-invariants.sh. Nothing here touches a real build: $HOME, $CUBRID and $CTP_HOME
# are throwaways, `run_cubrid_install` is a script that rewrites a version file, `ctp.sh` prints CTP's
# output shape, and `curl` answers reachability from a fixture list.
#
# This is the script whose failure costs the most: it swaps the engine under a machine, and every later
# verify silently trusts whatever is installed. So the cases that matter are not the happy path but the
# four ways it can strand a machine — an unreachable fixed build, an install that exits 0 without
# installing, a failed restore, and a pre-fix result overwriting the record the submit gate reads.
set -u

BIN_DIR=$(cd "$(dirname "$(readlink -f "$0")")/../skills/qa/setup-cubrid-agent/bin" && pwd)
SRC="$BIN_DIR/failpass-run.sh"
[ -f "$SRC" ] || { echo "test-failpass-run: script not found at $SRC" >&2; exit 1; }

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
export STATE="$T/state"
mkdir -p "$HOME" "$STATE"
KEY=CBRD-99999

# ── stubbed world ────────────────────────────────────────────────────────────────────────────────
export CUBRID="$T/CUBRID"; mkdir -p "$CUBRID/bin" "$CUBRID/lib"
cat > "$CUBRID/bin/cubrid_rel" <<'STUB'
#!/bin/bash
[ -s "$STATE/installed" ] || exit 1
printf 'CUBRID 11.5 (%s) (64bit release build for linux)\n' "$(cat "$STATE/installed")"
STUB
touch "$CUBRID/lib/libcubrid_all_locales.so"

export CTP_HOME="$T/CTP"; mkdir -p "$CTP_HOME/bin" "$CTP_HOME/common/script" "$CTP_HOME/conf"
cat > "$CTP_HOME/common/script/run_cubrid_install" <<'STUB'
#!/bin/bash
# The real installer can exit 0 having failed, which is why the caller asserts the version instead of
# trusting the exit code — STUB_INSTALL_SILENT_FAIL reproduces exactly that.
_url=$1
_ver=$(printf '%s' "$_url" | grep -oE 'CUBRID-[0-9.]+-[0-9a-f]+' | sed 's/^CUBRID-//' | head -1)
# An installer given something whose name carries no version does nothing and still exits 0 — the
# no-op case a version-less URL produces in real life (a local installer path, a renamed file).
[ -n "$_ver" ] || { echo "[ERROR] nothing to install from $_url"; exit 0; }
if [ "${STUB_INSTALL_SILENT_FAIL:-}" = "$_ver" ]; then echo "[ERROR] pretend download failed"; exit 0; fi
printf '%s' "$_ver" > "$STATE/installed"
echo "installed $_ver"
STUB
cat > "$CTP_HOME/bin/ctp.sh" <<'STUB'
#!/bin/bash
cat > /dev/null            # consume the run/quit commands
_v=$(cat "$STATE/installed" 2>/dev/null)
mkdir -p "$STATE/result/sql"
printf 'engine output for %s\n' "$_v" > "$STATE/result/sql/cbrd_99999.result"
if grep -qx "$_v" "$STATE/failing" 2>/dev/null; then printf 'Fail:1\n'; else printf 'Success:1\n'; fi
printf 'Elapse Time:17\n'
printf 'Test Result Directory:%s\n' "$STATE/result"
STUB
printf 'scenario=/nowhere/sql\n' > "$CTP_HOME/conf/sql.conf"
chmod +x "$CUBRID/bin/cubrid_rel" "$CTP_HOME/common/script/run_cubrid_install" "$CTP_HOME/bin/ctp.sh"

# curl answers only for URLs the case declared reachable.
STUBBIN="$T/stub"; mkdir -p "$STUBBIN"; export PATH="$STUBBIN:$PATH"
cat > "$STUBBIN/curl" <<'STUB'
#!/bin/bash
for a in "$@"; do case "$a" in http*) _u=$a ;; esac; done
grep -qxF "$_u" "$STATE/reachable" 2>/dev/null && exit 0
exit 22
STUB
chmod +x "$STUBBIN/curl"

# A testcase for verify-run.sh to find, and a manifest that already holds a real verify result — the
# pre-fix run must not be able to overwrite it.
export CUBRID_TESTCASES="$T/tc"
D="$CUBRID_TESTCASES/sql/_36_guava/cbrd_99999"; mkdir -p "$D/cases" "$D/answers"
printf "evaluate 'Case 1';\nselect 1;\n" > "$D/cases/cbrd_99999.sql"
printf 'engine output for FIXVER\n' > "$D/answers/cbrd_99999.answer"
RUN="$HOME/.cubrid-agent/$KEY"; mkdir -p "$RUN"

FIX=11.5.0.2300-04192d6
PRE=11.4.0.1000-deadbee
url() { printf 'http://192.168.1.91:8080/REPO_ROOT/store_01/%s/drop/CUBRID-%s-Linux.x86_64.sh' "$1" "$1"; }

T_PASS=0; T_FAIL=0; FAILURES=""
note_fail() { T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    $1"; }

reset_state() {  # <installed version> [failing versions...]
  printf '%s' "$1" > "$STATE/installed"; shift
  : > "$STATE/failing"; for v in "$@"; do printf '%s\n' "$v" >> "$STATE/failing"; done
  printf '%s\n%s\n' "$(url "$FIX")" "$(url "$PRE")" > "$STATE/reachable"
  unset STUB_INSTALL_SILENT_FAIL
  cat > "$RUN/manifest.json" <<JSON
{"issue":"$KEY","author":{"path":"sql/_36_guava/cbrd_99999/cases/cbrd_99999.sql"},
 "verify":{"status":"passed","determinism":{"runs":3,"all_pass":true}}}
JSON
  rm -rf "$STATE/result"
}
OUTF="$T/out"
run() {  # run <name> <expected exit> <fragment> [args...]
  _name=$1; _want=$2; _frag=$3; shift 3
  bash "$SRC" "$KEY" "$@" > "$OUTF" 2>&1; _rc=$?
  [ "$_rc" = "$_want" ] || { note_fail "$_name: expected exit $_want, got $_rc"; return 1; }
  if [ -n "$_frag" ] && ! grep -qF -- "$_frag" "$OUTF"; then
    note_fail "$_name: output never says \"$_frag\""; return 1
  fi
  T_PASS=$((T_PASS+1)); return 0
}
st() { jq -r '.verify.fail_to_pass.status // "none"' "$RUN/manifest.json" 2>/dev/null; }
inst() { cat "$STATE/installed" 2>/dev/null; }
expect() { # expect <name> <what> <got> <want>
  [ "$3" = "$4" ] && T_PASS=$((T_PASS+1)) || note_fail "$1: $2 is \"$3\", expected \"$4\""; }

# ── arguments and preconditions ───────────────────────────────────────────────────────────────────
reset_state "$FIX"
run "no --prefix-build" 1 "--prefix-build is required"
run "prefix equals installed" 1 "proves nothing" --prefix-build "$FIX"

reset_state "$FIX"
printf '%s\n' "$(url "$PRE")" > "$STATE/reachable"        # the FIXED build is gone from the server
run "fixed build unreachable" 3 "Refusing to install anything" --prefix-build "$PRE" \
  && expect "fixed build unreachable" "installed build" "$(inst)" "$FIX"
expect "fixed build unreachable" "status" "$(st)" inconclusive

reset_state "$FIX"
printf '%s\n' "$(url "$FIX")" > "$STATE/reachable"        # the pre-fix build is gone
run "prefix build unreachable" 3 "Nothing was installed" --prefix-build "$PRE" \
  && expect "prefix build unreachable" "installed build" "$(inst)" "$FIX"

reset_state ""                                            # nothing installed at all
run "no build installed" 3 "must already be installed" --prefix-build "$PRE"

# ── the happy path, and the record it must not damage ─────────────────────────────────────────────
reset_state "$FIX" "$PRE"                                 # the case fails on the pre-fix build only
if run "confirmed" 0 "verify.fail_to_pass.status=confirmed" --prefix-build "$PRE"; then
  expect "confirmed" "status" "$(st)" confirmed
  expect "confirmed" "installed build afterwards" "$(inst)" "$FIX"
  expect "confirmed" "prefix_run" "$(jq -r '.verify.fail_to_pass.prefix_run' "$RUN/manifest.json")" FAIL
  expect "confirmed" "fixed_run"  "$(jq -r '.verify.fail_to_pass.fixed_run'  "$RUN/manifest.json")" PASS
  # The whole reason verify-run.sh grew --no-manifest: a deliberate pre-fix Fail must not become the
  # verification the submit gate reads.
  expect "confirmed" "verify.status survived" "$(jq -r '.verify.status' "$RUN/manifest.json")" passed
  expect "confirmed" "determinism survived" "$(jq -r '.verify.determinism.all_pass' "$RUN/manifest.json")" true
fi

# ── the testcase does not catch the bug ───────────────────────────────────────────────────────────
reset_state "$FIX"                                        # nothing fails anywhere
run "contradicted" 1 "status=contradicted" --prefix-build "$PRE" \
  && expect "contradicted" "installed build afterwards" "$(inst)" "$FIX"
expect "contradicted" "best_effort is left to the human" \
  "$(grep -c 'YOUR call' "$OUTF")" 1

# ── the fixed build does not pass either ──────────────────────────────────────────────────────────
reset_state "$FIX" "$PRE" "$FIX"                          # fails on both
run "fixed run fails" 1 "status=inconclusive" --prefix-build "$PRE" \
  && expect "fixed run fails" "status" "$(st)" inconclusive

# ── an install that exits 0 without installing ────────────────────────────────────────────────────
reset_state "$FIX" "$PRE"
STUB_INSTALL_SILENT_FAIL=$PRE run "silent install failure" 3 "install prefix FAILED" --prefix-build "$PRE" \
  && expect "silent install failure" "installed build" "$(inst)" "$FIX"
expect "silent install failure" "status" "$(st)" inconclusive

# ── the restore fails: the loudest path there is ──────────────────────────────────────────────────
reset_state "$FIX" "$PRE"
STUB_INSTALL_SILENT_FAIL=$FIX run "restore fails" 3 "THIS MACHINE IS STILL ON A PRE-FIX BUILD" --prefix-build "$PRE"
expect "restore fails" "status" "$(st)" inconclusive
grep -q "sh $CTP_HOME/common/script/run_cubrid_install" "$OUTF" \
  && T_PASS=$((T_PASS+1)) || note_fail "restore fails: the recovery command is not printed"
expect "restore fails" "manifest names the stranded build" \
  "$(jq -r '.verify.fail_to_pass.note | test("RESTORE FAILED")' "$RUN/manifest.json")" true

# ── a bare version is accepted where a URL is ─────────────────────────────────────────────────────
reset_state "$FIX" "$PRE"
run "bare version resolves to the build-server URL" 0 "confirmed" --prefix-build "$PRE"

# ── a URL with no parsable version must not disable the install check ─────────────────────────────
# The first version asserted the installed version only when the URL named one, so a version-less URL
# skipped the check, ran the testcase on the FIXED build, saw it pass, and recorded `contradicted` —
# "this TC has no regression value" — which is a false verdict rather than an error.
reset_state "$FIX" "$PRE"
LOCAL_INSTALLER="$T/installer.sh"; : > "$LOCAL_INSTALLER"
run "version-less URL is caught, not believed" 3 "nothing was installed" --prefix-build "$LOCAL_INSTALLER"
expect "version-less URL" "status" "$(st)" inconclusive
expect "version-less URL" "installed build" "$(inst)" "$FIX"
grep -qF 'contradicted' "$OUTF" && note_fail "version-less URL: reported contradicted instead of failing the install" \
  || T_PASS=$((T_PASS+1))

if [ "$T_FAIL" -eq 0 ]; then
  printf 'failpass-run: %d/%d\n' "$T_PASS" "$T_PASS"
  exit 0
else
  printf 'failpass-run: %d passed, %d FAILED%s\n' "$T_PASS" "$T_FAIL" "$FAILURES"
  exit 1
fi
