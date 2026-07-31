#!/bin/bash
# Behavioural test for debug-check.sh — offline, with the build install and CTP stubbed.
#
# Dev-only, run by check-invariants.sh. Same stubbed world as test-failpass-run.sh: throwaway $HOME,
# $CUBRID and $CTP_HOME, an installer that rewrites a version file, a ctp.sh that prints CTP's output
# shape, and a curl that answers from a fixture list.
#
# The case that shapes this script: a debug build reports the SAME version as its release twin, so the
# post-install assertion that protects every other swap ("cubrid_rel now says the version I asked for")
# passes even when nothing was installed. The build TYPE is the only thing that can be asserted here,
# and a run that silently stayed on release would report "debug is clean" — a claim about a build that
# was never under test.
set -u

BIN_DIR=$(cd "$(dirname "$(readlink -f "$0")")/../skills/qa/setup-cubrid-agent/bin" && pwd)
SRC="$BIN_DIR/debug-check.sh"
[ -f "$SRC" ] || { echo "test-debug-check: script not found at $SRC" >&2; exit 1; }

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
export STATE="$T/state"
mkdir -p "$HOME" "$STATE"
KEY=CBRD-99999
VER=11.5.0.2378-0dd8912

# ── stubbed world ────────────────────────────────────────────────────────────────────────────────
export CUBRID="$T/CUBRID"; mkdir -p "$CUBRID/bin" "$CUBRID/lib"
cat > "$CUBRID/bin/cubrid_rel" <<'STUB'
#!/bin/bash
[ -s "$STATE/installed" ] || exit 1
printf 'CUBRID 11.5 (%s) (64bit %s build for Linux)\n' "$(cat "$STATE/installed")" "$(cat "$STATE/type" 2>/dev/null || echo release)"
STUB
touch "$CUBRID/lib/libcubrid_all_locales.so"

export CTP_HOME="$T/CTP"; mkdir -p "$CTP_HOME/bin" "$CTP_HOME/common/script" "$CTP_HOME/conf"
cat > "$CTP_HOME/common/script/run_cubrid_install" <<'STUB'
#!/bin/bash
_url=$1
_ver=$(printf '%s' "$_url" | grep -oE 'CUBRID-[0-9.]+-[0-9a-f]+' | sed 's/^CUBRID-//' | head -1)
case "$_url" in *-debug.sh|*-debug.tar.gz) _type=debug ;; *) _type=release ;; esac
# The no-op an installer really performs when the download fails: exits 0, changes nothing.
if [ "${STUB_INSTALL_NOOP:-}" = "$_type" ]; then echo "[ERROR] pretend download failed"; exit 0; fi
printf '%s' "$_ver" > "$STATE/installed"; printf '%s' "$_type" > "$STATE/type"
echo "installed $_ver ($_type)"
STUB
cat > "$CTP_HOME/bin/ctp.sh" <<'STUB'
#!/bin/bash
cat > "$STATE/ctp-stdin"
_t=$(cat "$STATE/type" 2>/dev/null || echo release)
mkdir -p "$STATE/result/sql"
printf 'engine output for %s\n' "$_t" > "$STATE/result/sql/cbrd_99999.result"
# A debug build that trips an assert prints it into the run log, which is what the script greps.
[ -f "$STATE/assert" ] && [ "$_t" = debug ] && printf 'assertion "pgptr != NULL" failed at file page_buffer.c line 4242\n'
if grep -qx "$_t" "$STATE/failing" 2>/dev/null; then printf 'Fail:1\n'; else printf 'Success:1\n'; fi
printf 'Elapse Time:17\n'
printf 'Test Result Directory:%s\n' "$STATE/result"
STUB
printf 'scenario=/nowhere/sql\n' > "$CTP_HOME/conf/sql.conf"
chmod +x "$CUBRID/bin/cubrid_rel" "$CTP_HOME/common/script/run_cubrid_install" "$CTP_HOME/bin/ctp.sh"

STUBBIN="$T/stub"; mkdir -p "$STUBBIN"; export PATH="$STUBBIN:$PATH"
cat > "$STUBBIN/curl" <<'STUB'
#!/bin/bash
for a in "$@"; do case "$a" in http*) _u=$a ;; esac; done
grep -qxF "$_u" "$STATE/reachable" 2>/dev/null && exit 0
exit 22
STUB
chmod +x "$STUBBIN/curl"

export CUBRID_TESTCASES="$T/tc"
D="$CUBRID_TESTCASES/sql/_36_guava/cbrd_99999"; mkdir -p "$D/cases" "$D/answers"
printf "evaluate 'Case 1';\nselect 1;\n" > "$D/cases/cbrd_99999.sql"
printf 'engine output for release\n' > "$D/answers/cbrd_99999.answer"
RUN="$HOME/.cubrid-agent/$KEY"; mkdir -p "$RUN"

BASE=https://ftp.cubrid.org/CUBRID_Engine/nightly/daily_build
rel_url() { printf '%s/%s/drop/CUBRID-%s-Linux.x86_64.sh' "$BASE" "$1" "$1"; }
dbg_url() { printf '%s/%s/drop/CUBRID-%s-Linux.x86_64-debug.sh' "$BASE" "$1" "$1"; }

T_PASS=0; T_FAIL=0; FAILURES=""
note_fail() { T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    $1"; }
reset_state() {  # [failing type...]
  printf '%s' "$VER" > "$STATE/installed"; printf 'release' > "$STATE/type"
  : > "$STATE/failing"; for t in "$@"; do printf '%s\n' "$t" >> "$STATE/failing"; done
  printf '%s\n%s\n' "$(rel_url "$VER")" "$(dbg_url "$VER")" > "$STATE/reachable"
  rm -f "$STATE/assert"; unset STUB_INSTALL_NOOP
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
# NOT `// "none"`: jq's // substitutes for `false` as well as null, so a recorded checked=false
# would read back as "none" and the assertion would pass for the wrong reason.
dbg() { jq -r --arg k "$1" '(.verify.debug // {}) | if has($k) then (.[$k]|tostring) else "none" end' "$RUN/manifest.json" 2>/dev/null; }
inst() { printf '%s/%s' "$(cat "$STATE/installed" 2>/dev/null)" "$(cat "$STATE/type" 2>/dev/null)"; }
expect() { [ "$3" = "$4" ] && T_PASS=$((T_PASS+1)) || note_fail "$1: $2 is \"$3\", expected \"$4\""; }

# ── preconditions ─────────────────────────────────────────────────────────────────────────────────
reset_state
: > "$STATE/installed"                                    # nothing installed
run "no build installed" 3 "must already be installed"

reset_state
printf '%s\n' "$(rel_url "$VER")" > "$STATE/reachable"    # the debug artifact is missing
run "debug build unreachable" 3 "Nothing was installed" \
  && expect "debug build unreachable" "installed" "$(inst)" "$VER/release"

reset_state
printf '%s\n' "$(dbg_url "$VER")" > "$STATE/reachable"    # the release build cannot be reinstalled
run "release build unreachable" 3 "Refusing to install anything" \
  && expect "release build unreachable" "installed" "$(inst)" "$VER/release"
expect "release build unreachable" "result"  "$(dbg result)"  inconclusive
expect "release build unreachable" "checked" "$(dbg checked)" false

# ── clean debug run ───────────────────────────────────────────────────────────────────────────────
reset_state
if run "clean" 0 "verify.debug.result=clean"; then
  expect "clean" "result"            "$(dbg result)"  clean
  expect "clean" "checked"           "$(dbg checked)" true
  expect "clean" "build type tested" "$(dbg type)"    debug
  expect "clean" "restored to release" "$(inst)"      "$VER/release"
  # The release verification must survive: the debug run passes --no-manifest, like the pre-fix run.
  expect "clean" "verify.status survived" "$(jq -r '.verify.status' "$RUN/manifest.json")" passed
  expect "clean" "determinism survived" "$(jq -r '.verify.determinism.all_pass' "$RUN/manifest.json")" true
fi

# ── an assert is the finding, and it blocks ───────────────────────────────────────────────────────
reset_state
: > "$STATE/assert"
run "assert trips" 1 "assertion" \
  && expect "assert trips" "restored to release" "$(inst)" "$VER/release"
expect "assert trips" "result" "$(dbg result)" assert
expect "assert trips" "marker recorded" "$(dbg marker | grep -c 'page_buffer.c')" 1
grep -qiF "developer" "$OUTF" && T_PASS=$((T_PASS+1)) \
  || note_fail "assert trips: the output does not say this belongs to the developer, not the answer"

# An assert while the case still passes must NOT be reported as clean.
reset_state
: > "$STATE/assert"
run "assert beats a passing run" 1 "verify.debug.result=assert"
expect "assert beats a passing run" "result" "$(dbg result)" assert

# ── output differs without an assert: judgment, and never promote the debug output ────────────────
reset_state debug
run "output differs" 1 "verify.debug.result=differs" \
  && expect "output differs" "restored to release" "$(inst)" "$VER/release"
expect "output differs" "result" "$(dbg result)" differs
grep -qF "promote" "$OUTF" && T_PASS=$((T_PASS+1)) \
  || note_fail "output differs: the output does not warn against promoting debug output into .answer"

# ── the install that changes nothing: the version alone cannot catch it ───────────────────────────
# A debug build reports the same version as its release twin, so only the TYPE assertion sees this.
reset_state
STUB_INSTALL_NOOP=debug run "silent no-op install is caught" 3 "install debug FAILED" \
  && expect "silent no-op install" "installed" "$(inst)" "$VER/release"
expect "silent no-op install" "result"  "$(dbg result)"  inconclusive
expect "silent no-op install" "checked" "$(dbg checked)" false

# ── a failed restore is the loudest path ──────────────────────────────────────────────────────────
reset_state
STUB_INSTALL_NOOP=release run "restore fails" 3 "STILL ON A DEBUG BUILD"
expect "restore fails" "result" "$(dbg result)" inconclusive
grep -q "run_cubrid_install" "$OUTF" && T_PASS=$((T_PASS+1)) \
  || note_fail "restore fails: the recovery command is not printed"

# ── two ways to record an assert that never happened ──────────────────────────────────────────────
# Both were found by review, and both pass the rest of this suite, so they get their own cases: `assert`
# is the one result with no note that can clear it, so a false one blocks the testcase permanently.

# (1) A blocked run must not inherit a marker from an earlier run's log. The log lives at a fixed path,
# so whatever ran before is still sitting in it when the debug run cannot start.
reset_state
printf 'assertion "pgptr != NULL" failed at file page_buffer.c line 1\n' > "$RUN/verify-sql.debug.log"
mv "$CTP_HOME/conf/sql.conf" "$CTP_HOME/conf/sql.conf.away"     # verify-run blocks before running CTP
run "blocked run does not inherit a stale marker" 3 "inconclusive"
expect "blocked run" "result"  "$(dbg result)"  inconclusive
expect "blocked run" "restored to release" "$(inst)" "$VER/release"
mv "$CTP_HOME/conf/sql.conf.away" "$CTP_HOME/conf/sql.conf"
rm -f "$RUN/verify-sql.debug.log"

# (2) The testcase's own output is not evidence about the engine. verify-run.sh prints the first 20 lines
# of the answer diff to stdout, so a TC written for an assert bug — whose expected output contains the
# word — used to be recorded as tripping one.
reset_state debug
printf 'assertion count after recovery: 3\n' > "$D/answers/cbrd_99999.answer"
run "diff text is not an engine marker" 1 "verify.debug.result=differs"
expect "diff text" "result" "$(dbg result)" differs
printf 'engine output for release\n' > "$D/answers/cbrd_99999.answer"

# ── the case FILE is what gets run, not its directory ─────────────────────────────────────────────
# Every bug-fix TC shares `_13_issues/<half>/cases/` with its siblings, so a directory argument runs
# their cases too and folds their results into this verdict (measured: Total:2 instead of Total:1).
reset_state
run "runs the case file" 0 "clean"
grep -q 'cases/cbrd_99999.sql' "$STATE/ctp-stdin" && T_PASS=$((T_PASS+1)) \
  || note_fail "runs the case file: CTP was asked to run $(head -1 "$STATE/ctp-stdin"), not the case file"

# ── an explicit version is accepted ──────────────────────────────────────────────────────────────
reset_state
run "explicit --version" 0 "clean" --version "$VER"

if [ "$T_FAIL" -eq 0 ]; then
  printf 'debug-check: %d/%d\n' "$T_PASS" "$T_PASS"
  exit 0
else
  printf 'debug-check: %d passed, %d FAILED%s\n' "$T_PASS" "$T_FAIL" "$FAILURES"
  exit 1
fi
