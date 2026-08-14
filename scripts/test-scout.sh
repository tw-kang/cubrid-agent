#!/bin/bash
# Behavioural test for scout.sh — the one prep call. What it must get right is not the happy line but
# the two ways it can mislead: reporting a capability that is absent, and deciding something that is
# the caller's to decide.
#
# Dev-only, run by check-invariants.sh. Deterministic and offline: $HOME is a throwaway, the corpus
# is synthetic, and `gh`/`cubrid-jira`/`git ls-remote` are stubbed so a network touch would be
# recorded — the scout must make none.
set -u

SRC=$(cd "$(dirname "$(readlink -f "$0")")/../skills/qa/setup-cubrid-agent/bin" && pwd)/scout.sh
[ -f "$SRC" ] || { echo "test-scout: script not found at $SRC" >&2; exit 1; }
REAL_GIT=$(command -v git) || { echo "test-scout: git is required" >&2; exit 1; }

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
BIN="$T/stub"; mkdir -p "$BIN"
export PATH="$BIN:$PATH"
export HOME="$T/home"; mkdir -p "$HOME"
export REAL_GIT NETLOG="$T/net.log"

# Any use of these is a network touch. They exist so the scout would *find* them, and record the call
# so the test can assert it never made one. The one exception is `gh auth token`, which reads the
# local credential store — that is why the scout may use it where `gh auth status` would be a call.
cat > "$BIN/cubrid-jira" <<'STUB'
#!/bin/bash
echo "cubrid-jira $*" >> "$NETLOG"
exit 0
STUB
cat > "$BIN/gh" <<'STUB'
#!/bin/bash
if [ "${1:-} ${2:-}" = "auth token" ]; then
  [ -n "${STUB_NO_GH_TOKEN:-}" ] && exit 1
  echo "gho_notarealtoken"; exit 0
fi
echo "gh $*" >> "$NETLOG"
exit 0
STUB
# git is real except for ls-remote, which is the one subcommand that goes out to the network.
cat > "$BIN/git" <<'STUB'
#!/bin/bash
[ "$1" = ls-remote ] && { echo "git ls-remote $*" >> "$NETLOG"; exit 0; }
exec "$REAL_GIT" "$@"
STUB
chmod +x "$BIN"/*

# ── synthetic corpus ─────────────────────────────────────────────────────────────────────────────
TCD="$T/tc"; export CUBRID_TESTCASES="$TCD"
CURHY="_$(date +%y)_$([ "$(date +%-m)" -le 6 ] && echo 1 || echo 2)h"
mkdir -p "$TCD/sql/_13_issues/$CURHY/cases" "$TCD/sql/_13_issues/_24_1h/cases" \
         "$TCD/sql/_36_guava" "$TCD/sql/_35_ordinary"
for n in 26401 26402 26404; do
  printf '/**\n * This test case verifies CBRD-%s\n */\nCREATE TABLE t1(a int);\n' "$n" \
    > "$TCD/sql/_13_issues/$CURHY/cases/cbrd_$n.sql"
done
printf 'PREPARE st FROM %s;\n' "'SELECT 1'" > "$TCD/sql/_13_issues/_24_1h/cases/cbrd_20001.sql"
# The corpus is not shaped like a cbrd_* directory: 16,540 of its 17,394 case files are named for a
# feature, not an issue, and those are exactly the testcases a coverage search exists to find. The
# answers and docs beside them are exactly what it must not read. A synthetic corpus holding only
# cbrd_*.sql cannot tell a correct filter from a broken one.
mkdir -p "$TCD/sql/_05_feature/cases" "$TCD/sql/_13_issues/_24_1h/answers"
printf 'PREPARE st FROM %s;\n' "'SELECT 2'" > "$TCD/sql/_05_feature/cases/_03_iss_700000.sql"
printf 'PREPARE st\n' > "$TCD/sql/_13_issues/_24_1h/answers/cbrd_20001.answer"
printf 'PREPARE is documented here\n' > "$TCD/sql/README.md"
"$REAL_GIT" init -q "$TCD"
"$REAL_GIT" -C "$TCD" remote add origin https://github.com/CUBRID/cubrid-testcases.git
"$REAL_GIT" -C "$TCD" remote add fork https://github.com/octo/cubrid-testcases.git
"$REAL_GIT" -C "$TCD" add -A >/dev/null 2>&1
"$REAL_GIT" -C "$TCD" -c user.email=t@t -c user.name=t commit -q -m init
"$REAL_GIT" -C "$TCD" branch -M develop

# ── environment the happy path expects ───────────────────────────────────────────────────────────
export CUBRID="$T/cub"; mkdir -p "$CUBRID/bin"
cat > "$CUBRID/bin/cubrid_rel" <<'STUB'
#!/bin/bash
echo "CUBRID 11.4 (11.4.0.1234-abcdef) (64bit release build for linux)"
STUB
export CTP_HOME="$T/ctp"; mkdir -p "$CTP_HOME/bin"
# The engine clone Ground reads the fix diff from. $HOME is a throwaway, so it has to be named.
export CUBRID_SRC="$T/engine"; mkdir -p "$CUBRID_SRC"; "$REAL_GIT" init -q "$CUBRID_SRC"
printf '#!/bin/bash\nexit 0\n' > "$CTP_HOME/bin/ctp.sh"
chmod +x "$CUBRID/bin/cubrid_rel" "$CTP_HOME/bin/ctp.sh"
export CUBRID_JIRA_USER=qauser
unset CUBRID_GH_FORK GH_TOKEN

HELPERS='common.sh ground-issue.sh select-queue.sh prepare-tc-workspace.sh render-pr-body.sh verify-run.sh build-swap.sh failpass-run.sh debug-check.sh render-report.sh scout.sh'
install_helpers() { mkdir -p "$HOME/.cubrid-agent/bin"; for h in $HELPERS; do : > "$HOME/.cubrid-agent/bin/$h"; done; }
install_helpers

T_PASS=0; T_FAIL=0; FAILURES=""
OUTF="$T/out"
note_fail() { T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    $1"; }
# run <name> <expected exit> <fragment that must appear> [fragment that must NOT appear]
run() {
  _name=$1; _want=$2; _yes=$3; _no=${4:-}
  # Unquoted on purpose: $ARGS is this harness's argv, and an empty one must reach the script as no
  # argument at all — the case that proves it asks for a key.
  # shellcheck disable=SC2086
  bash "$SRC" $ARGS > "$OUTF" 2>&1; _rc=$?
  if [ "$_rc" != "$_want" ]; then note_fail "$_name: expected exit $_want, got $_rc"; return; fi
  if [ -n "$_yes" ] && ! grep -qF -- "$_yes" "$OUTF"; then note_fail "$_name: output never says \"$_yes\""; return; fi
  if [ -n "$_no" ] && grep -qF -- "$_no" "$OUTF"; then note_fail "$_name: output must not say \"$_no\" but does"; return; fi
  T_PASS=$((T_PASS+1))
}
manifest() { mkdir -p "$HOME/.cubrid-agent/CBRD-25913"; printf '%s' "$1" > "$HOME/.cubrid-agent/CBRD-25913/manifest.json"; }
reset_state() { rm -rf "$HOME/.cubrid-agent"; install_helpers; ARGS=CBRD-25913; : > "$NETLOG"
                export CUBRID_JIRA_USER=qauser CTP_HOME="$T/ctp" CUBRID="$T/cub" CUBRID_SRC="$T/engine"
                unset CUBRID_GH_FORK GH_TOKEN STUB_NO_GH_TOKEN; }

# ── the scout cannot answer: a stop, not a finding ───────────────────────────────────────────────
reset_state
ARGS="--nope CBRD-25913" run "unknown option" 1 "this installed copy is stale"
CUBRID_TESTCASES="$T/not-a-clone" ARGS=CBRD-25913 run "no clone" 1 "is not a git clone"

# ── happy path: every section answers, in one call ───────────────────────────────────────────────
reset_state
manifest '{"issue":"CBRD-25913","select":{"issue_type":"Correct Error"}}'
run "env line"        0 "helpers 11/11"
run "build reported"  0 "11.4.0.1234-abcdef (release)"
run "ctp reported"    0 "$T/ctp"
run "identity"        0 "jira qauser · fork octo"
run "tc line"         0 "origin https://github.com/CUBRID/cubrid-testcases.git, on develop"
run "target dir"      0 "sql/_13_issues/$CURHY/cases/ — exists, 3 case(s)"
run "sibling named"   0 "cbrd_26404.sql"
run "no coverage yet" 0 "no cbrd_25913 file or directory"
run "no pattern note" 0 "no --grep pattern given"
run "run state"       0 "type Correct Error"
run "hands back judgment" 0 "whether this build contains the issue's fix"

# The whole point of the helper: no network, so both the orchestrator and the author lane may call it.
if [ -s "$NETLOG" ]; then note_fail "the scout touched the network: $(tr '\n' ';' < "$NETLOG")"; else T_PASS=$((T_PASS+1)); fi

# ── an absent capability is named, and stops ─────────────────────────────────────────────────────
reset_state
manifest '{"select":{"issue_type":"Correct Error"}}'
CUBRID="$T/none" run "no build stops"    3 "MISSING: CUBRID build"
CUBRID="$T/none" run "and says the cost" 3 'blocked_no_build'
CTP_HOME="$T/none" run "no CTP stops"    3 "MISSING: CTP"
rm -f "$HOME/.cubrid-agent/bin/render-report.sh" "$HOME/.cubrid-agent/bin/verify-run.sh"
run "missing helpers named" 3 "MISSING: helper(s) verify-run.sh render-report.sh"
install_helpers
CUBRID_JIRA_USER="" run "no jira user"        3 "MISSING: JIRA username"
CUBRID_JIRA_USER=jira.cubrid.org run "hostname as user" 3 "looks like a hostname"
# An unauthenticated gh fails at the very end of the run, on the one command the whole run is for.
STUB_NO_GH_TOKEN=1 run "gh holds no token"        3 "MISSING: gh credentials"
STUB_NO_GH_TOKEN=1 GH_TOKEN=x run "GH_TOKEN counts" 0 "" "MISSING: gh credentials"
# Still a full report: the caller decides whether the reduced path is acceptable, so it needs the rest.
CUBRID="$T/none" run "report is still complete" 3 "cover  :"

reset_state
"$REAL_GIT" -C "$TCD" remote remove fork
run "no fork owner" 3 "MISSING: fork owner"
CUBRID_GH_FORK=someone run "env var supplies it" 0 "fork someone"
"$REAL_GIT" -C "$TCD" remote add fork https://github.com/octo/cubrid-testcases.git

reset_state
"$REAL_GIT" -C "$TCD" remote set-url origin https://github.com/octo/cubrid-testcases.git
run "origin is a fork" 3 "MISSING: upstream origin"
"$REAL_GIT" -C "$TCD" remote set-url origin https://github.com/CUBRID/cubrid-testcases.git

# ── placement: reported from the issue type, never guessed ───────────────────────────────────────
reset_state
run "ungrounded issue names the gap" 0 "issue type not recorded"
run "and names no tree"              0 "" "sql/_13_issues/$CURHY/cases/ — exists"
manifest '{"select":{"issue_type":"Improve Function/Performance"}}'
run "non-bug goes to a release dir" 0 "release dir, sql/_NN_<release>/cbrd_25913/cases/"
run "and lists the ones present"    0 "_35_ordinary _36_guava"
run "release choice stays create-sql's" 0 "create-sql's convention picks the release"

# ── existing coverage ────────────────────────────────────────────────────────────────────────────
reset_state
manifest '{"select":{"issue_type":"Correct Error"}}'
mkdir -p "$TCD/sql/_36_guava/cbrd_25913/cases"
run "name hit is reported" 0 "cbrd_25913 already exists in the corpus"
rm -rf "$TCD/sql/_36_guava/cbrd_25913"
# Two hits, not one and not four: both testcases carry the repro, the answer and the README do not
# count. Finding the one filed under a feature name is the whole reason a content search exists —
# §2's own example of a duplicate hiding under another name is `_03_iss_700000`.
ARGS="CBRD-25913 --grep PREPARE" run "grep finds the repro under another name" 0 "--grep 'PREPARE' → 2 file(s)"
ARGS="CBRD-25913 --grep PREPARE" run "including the feature-named case" 0 "_03_iss_700000.sql"
ARGS="CBRD-25913 --grep PREPARE" run "but not the answer file"          0 "" ".answer"
ARGS="CBRD-25913 --grep PREPARE" run "and not the docs"                 0 "" "README.md"
ARGS="CBRD-25913 --grep PREPARE" run "path is relative to the clone"  0 "sql/_13_issues/_24_1h/cases/cbrd_20001.sql" "$TCD/sql"
ARGS="CBRD-25913 --grep no_such_token" run "a miss is a count, not silence" 0 "→ 0 file(s)"
# A pattern matching a large slice of the corpus is not prior art, and listing the first few would
# read as if it were. Measured against the real corpus: `EXECUTE .* USING` hits 857 of 17,394 cases.
for n in $(seq 30001 30015); do printf 'CREATE TABLE broad%s(a int);\n' "$n" > "$TCD/sql/_13_issues/_24_1h/cases/cbrd_$n.sql"; done
ARGS="CBRD-25913 --grep CREATE.TABLE" run "a too-broad pattern is a count and an instruction" 0 "too broad to be prior art"
rm -f "$TCD"/sql/_13_issues/_24_1h/cases/cbrd_300*.sql

# ── no key: create-sql is reachable without a CBRD number, and still needs the environment ───────
reset_state
ARGS="" run "keyless call still answers the env" 0 "helpers 11/11"
ARGS="" run "and searches by pattern"            0 "name CBRD-XXXXX to have its own TC looked for"
ARGS="--grep PREPARE" run "pattern works without a key" 0 "--grep 'PREPARE' → 2 file(s)"
ARGS="" run "the tree needs a key, and says so"  0 "no issue key given — the tree follows from the issue type"
ARGS="" run "so does the run state"              0 "no issue key given — no run directory to read"
ARGS="" run "and no run dir is claimed"          0 "" "run dir:"

# ── the engine clone Ground reads the fix from ───────────────────────────────────────────────────
reset_state
CUBRID_SRC="$T/no-engine" run "no cubrid source stops"  3 "MISSING: cubrid source"
CUBRID_SRC="$T/no-engine" run "and says what goes wrong" 3 "reports the fix commit as simply not found"
run "a clone satisfies it" 0 "" "MISSING: cubrid source"

# ── run state comes from the manifest, not from the caller retyping it ───────────────────────────
reset_state
manifest '{"select":{"issue_type":"Correct Error","queue":{"summary":"x"}},"ground":{"fix_commit":"deadbee some subject"},"lint":{"header":true,"evaluate":false,"placement":null},"verify":{"status":"passed"},"review":{"verdict":"PASS"},"submitted":true}'
run "gate summary" 0 "select queued · type Correct Error · fix deadbee · lint 1/2 · verify passed · review PASS · submitted true"
reset_state
run "fresh run says so" 0 "no manifest yet"

# ── a retry must not author into the clone ───────────────────────────────────────────────────────
reset_state
manifest '{"select":{"issue_type":"Correct Error"}}'
WT="$T/wt"; "$REAL_GIT" -C "$TCD" worktree add -q -b tc/cbrd-25913 "$WT" >/dev/null 2>&1
run "branch checkout is reported" 0 "tc/cbrd-25913 is already checked out at $WT"
"$REAL_GIT" -C "$TCD" worktree remove --force "$WT" >/dev/null 2>&1
"$REAL_GIT" -C "$TCD" branch -D tc/cbrd-25913 >/dev/null 2>&1

reset_state
manifest '{"select":{"issue_type":"Correct Error"}}'
: > "$TCD/dirty.txt"
run "uncommitted work is reported" 0 "uncommitted work — prepare-tc-workspace.sh will cut a worktree"
rm -f "$TCD/dirty.txt"

if [ "$T_FAIL" -eq 0 ]; then
  printf 'scout: %d/%d\n' "$T_PASS" "$T_PASS"
  exit 0
else
  printf 'scout: %d passed, %d FAILED%s\n' "$T_PASS" "$T_FAIL" "$FAILURES"
  exit 1
fi
