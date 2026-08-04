#!/bin/bash
# Behavioural test for select-queue.sh — the screens, and (more important) what happens when a screen
# cannot run.
#
# Dev-only, run by check-invariants.sh. Deterministic and offline: the three network commands
# (cubrid-jira, git ls-remote, gh) are stubbed on PATH, and $HOME is a throwaway, so it never touches
# the real ~/.cubrid-agent or JIRA.
#
# A lookup that FAILED must not read as a lookup that found nothing: "no branch exists" is what makes
# two operators author the same TC, and only a stub can pin that path.
set -u

SRC=$(cd "$(dirname "$(readlink -f "$0")")/../skills/qa/setup-cubrid-agent/bin" && pwd)/select-queue.sh
[ -f "$SRC" ] || { echo "test-select-queue: script not found at $SRC" >&2; exit 1; }
REAL_GIT=$(command -v git) || { echo "test-select-queue: git is required" >&2; exit 1; }

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
BIN="$T/stub"; mkdir -p "$BIN"
export PATH="$BIN:$PATH"
export HOME="$T/home"; mkdir -p "$HOME"
export REAL_GIT

# ── stubs ────────────────────────────────────────────────────────────────────────────────────────
# Each reads its behaviour from the environment, so a case is one export away.
cat > "$BIN/cubrid-jira" <<'STUB'
#!/bin/bash
[ "$1" = jql ] || { echo "stub cubrid-jira: unexpected subcommand $1" >&2; exit 9; }
printf '%s\n' "$*" > "$STUB_DIR/jql.seen"
[ -n "${STUB_JIRA_RC:-}" ] && { echo "stub jira error" >&2; exit "$STUB_JIRA_RC"; }
cat "$STUB_DIR/jql.json"
STUB
cat > "$BIN/git" <<'STUB'
#!/bin/bash
if [ "$1" = ls-remote ]; then
  _url=""; for a in "$@"; do case "$a" in https://*) _url=$a ;; esac; done
  case "$_url" in
    *"/$STUB_FORK/"*) [ -n "${STUB_FORK_FAIL:-}" ] && exit 128; cat "$STUB_DIR/fork.refs" 2>/dev/null; exit 0 ;;
    *CUBRID/*)        [ -n "${STUB_UP_FAIL:-}" ]   && exit 128; cat "$STUB_DIR/up.refs" 2>/dev/null;   exit 0 ;;
  esac
  exit 0
fi
exec "$REAL_GIT" "$@"
STUB
cat > "$BIN/gh" <<'STUB'
#!/bin/bash
case "$1 $2" in
  "api user") [ -n "${STUB_NO_GH_USER:-}" ] && exit 1; printf '%s\n' "$STUB_FORK"; exit 0 ;;
  "pr list")  [ -n "${STUB_GH_FAIL:-}" ] && { echo "gh: not authenticated" >&2; exit 4; }
              # Per head ref, like the real --head filter: a stub that answers for every key would
              # make one fixture drop the whole queue and hide which key was actually screened.
              _h=""; _n=0; for a in "$@"; do _n=$((_n+1)); [ "$a" = --head ] && eval "_h=\${$((_n+1))}"; done
              cat "$STUB_DIR/pr.${_h##*/}.json" 2>/dev/null || echo '[]'; exit 0 ;;
esac
exit 9
STUB
chmod +x "$BIN"/*
export STUB_DIR="$T/fixtures"; mkdir -p "$STUB_DIR"
export STUB_FORK=octo

# Three candidates, oldest first — the order the JQL guarantees and the script must preserve.
cat > "$STUB_DIR/jql.json" <<'JSON'
{"total":3,"issues":[
 {"key":"CBRD-11111","fields":{"summary":"oldest","issuetype":{"name":"Correct Error"},"resolutiondate":"2025-01-02T03:04:05.000+0900","customfield_210565":{"value":"Required"}}},
 {"key":"CBRD-22222","fields":{"summary":"middle","issuetype":{"name":"Correct Error"},"resolutiondate":"2025-06-02T03:04:05.000+0900","customfield_210565":{"value":"Not Yet"}}},
 {"key":"CBRD-33333","fields":{"summary":"newest","issuetype":{"name":"Improve Function/Performance"},"resolutiondate":"2026-01-02T03:04:05.000+0900","customfield_210565":{"value":"Required"}}}]}
JSON
: > "$STUB_DIR/fork.refs"; : > "$STUB_DIR/up.refs"

# A synthetic $TC so the local screens have something real to read.
TCD="$T/tc"; mkdir -p "$TCD/sql/_13_issues"
export CUBRID_TESTCASES="$TCD"
"$REAL_GIT" init -q "$TCD" && "$REAL_GIT" -C "$TCD" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init

export CUBRID_JIRA_USER=qauser
export CUBRID_GH_FORK=""
unset CUBRID_PLANNED_VERSION

T_PASS=0; T_FAIL=0; FAILURES=""
OUTF="$T/out"
# run <name> <expected exit> <fragment that must appear> [fragment that must NOT appear]
run() {
  _name=$1; _want=$2; _yes=$3; _no=${4:-}
  bash "$SRC" ${EXTRA:-} > "$OUTF" 2>&1; _rc=$?
  if [ "$_rc" != "$_want" ]; then
    T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    $_name: expected exit $_want, got $_rc"; return
  fi
  if [ -n "$_yes" ] && ! grep -qF -- "$_yes" "$OUTF"; then
    T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    $_name: output never says \"$_yes\""; return
  fi
  if [ -n "$_no" ] && grep -qF -- "$_no" "$OUTF"; then
    T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    $_name: output must not say \"$_no\" but does"; return
  fi
  T_PASS=$((T_PASS+1))
}
reset_state() { rm -rf "$HOME/.cubrid-agent"; : > "$STUB_DIR/fork.refs"; : > "$STUB_DIR/up.refs"
                rm -f "$STUB_DIR"/pr.*.json; unset STUB_FORK_FAIL STUB_UP_FAIL STUB_GH_FAIL STUB_NO_GH_USER
                export CUBRID_GH_FORK=$STUB_FORK; EXTRA=""; }

# ── identity guard: a doubtful username returns an empty queue, not an error, so it must stop here ──
reset_state
CUBRID_JIRA_USER="" run "no username"        1 "/setup-cubrid-agent"
CUBRID_JIRA_USER=jira.cubrid.org run "hostname as username" 1 "looks like a hostname"
CUBRID_JIRA_USER=a@b.com         run "e-mail as username"   1 "looks like a hostname"

# ── JIRA failure: one 401 must not become many ────────────────────────────────────────────────────
STUB_JIRA_RC=2 run "jira 401" 2 "Do NOT retry"
STUB_JIRA_RC=5 run "jira 400" 5 "Planned Version"

# ── happy path ────────────────────────────────────────────────────────────────────────────────────
run "no drops"        0 "3 candidate(s) from JQL, 0 screened out, 3 left"
run "order preserved" 0 "1 CBRD-11111"
run "head named"      0 "next   : ground-issue.sh CBRD-11111"
grep -q 'cf\[213834\] = "qauser"' "$STUB_DIR/jql.seen" \
  && grep -q 'cf\[210441\] = guava' "$STUB_DIR/jql.seen" \
  && T_PASS=$((T_PASS+1)) || { T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    JQL carries the resolved assignee and default version"; }
if jq -e '.queue|length == 3' "$HOME/.cubrid-agent/select-queue.json" >/dev/null 2>&1 \
   && jq -e '.select.queue.summary|test("판단 대기 3건")' "$HOME/.cubrid-agent/CBRD-11111/manifest.json" >/dev/null 2>&1; then
  T_PASS=$((T_PASS+1))
else
  T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    queue file + head manifest are written"
fi
# Only the head: run directories for candidates nobody processes are litter in someone's $HOME.
if [ -d "$HOME/.cubrid-agent/CBRD-22222" ]; then
  T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    a run directory was created for a candidate that is not the head"
else T_PASS=$((T_PASS+1)); fi
EXTRA=--json run "--json emits the queue" 0 '"candidates": 3'
EXTRA="--version marmot" run "version override" 0 "version=marmot"
grep -q 'cf\[210441\] = marmot' "$STUB_DIR/jql.seen" && T_PASS=$((T_PASS+1)) \
  || { T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    --version reaches the JQL"; }

# ── the four drops ────────────────────────────────────────────────────────────────────────────────
reset_state
printf 'sha\trefs/heads/tc/cbrd-11111\n' > "$STUB_DIR/fork.refs"
run "fork branch drops"   0 "drop CBRD-11111  branch tc/cbrd-11111 exists on your fork (octo)"
run "next head moves on"  0 "ground-issue.sh CBRD-22222"

reset_state
printf 'sha\trefs/heads/tc/cbrd-22222\n' > "$STUB_DIR/up.refs"
run "upstream branch drops" 0 "drop CBRD-22222  branch tc/cbrd-22222 exists upstream"

reset_state
mkdir -p "$TCD/sql/_13_issues/cbrd_33333"
run "local TC dir drops" 0 "a cbrd_33333 TC directory already exists"
rmdir "$TCD/sql/_13_issues/cbrd_33333"

reset_state
"$REAL_GIT" -C "$TCD" branch tc/cbrd-11111 >/dev/null 2>&1
run "local branch drops" 0 "local branch tc/cbrd-11111 exists"
"$REAL_GIT" -C "$TCD" branch -D tc/cbrd-11111 >/dev/null 2>&1

reset_state
echo '[{"number":3049,"state":"OPEN","isDraft":true}]' > "$STUB_DIR/pr.cbrd-22222.json"
run "PR drops (any fork)"  0 "PR #3049 (OPEN, draft) already exists upstream"
run "only that key drops"  0 "2 left to judge"
for k in 11111 22222 33333; do echo '[{"number":9,"state":"MERGED","isDraft":false}]' > "$STUB_DIR/pr.cbrd-$k.json"; done
run "every candidate has a PR" 3 "queue is empty"

# Precedence: a free branch hit must not spend a gh call, and must be the reason reported.
reset_state
printf 'sha\trefs/heads/tc/cbrd-11111\n' > "$STUB_DIR/fork.refs"
echo '[{"number":1,"state":"OPEN","isDraft":false}]' > "$STUB_DIR/pr.cbrd-11111.json"
run "branch beats PR as the reason" 0 "branch tc/cbrd-11111 exists on your fork" "PR #1 already exists upstream for tc/cbrd-11111"

# ── a screen that could not run is NOT a screen that found nothing ────────────────────────────────
reset_state
STUB_FORK_FAIL=1 run "fork lookup failure is reported" 0 "INCOMPLETE: fork branch check failed"
STUB_FORK_FAIL=1 run "and does not drop anything"      0 "3 left to judge"
STUB_UP_FAIL=1   run "upstream lookup failure"         0 "INCOMPLETE: upstream branch check failed"
STUB_GH_FAIL=1   run "gh unauthenticated"              0 "INCOMPLETE: PR check unavailable"
STUB_GH_FAIL=1   run "still yields a queue"            0 "3 left to judge"
CUBRID_GH_FORK="" STUB_NO_GH_USER=1 run "fork owner unknown" 0 "your own pushed branches were NOT checked"
reset_state
STUB_FORK_FAIL=1 bash "$SRC" >/dev/null 2>&1
if jq -e '.select.queue.checks_incomplete|length == 1' "$HOME/.cubrid-agent/CBRD-11111/manifest.json" >/dev/null 2>&1; then
  T_PASS=$((T_PASS+1))
else
  T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    an incomplete check reaches the manifest, so the report can say the screen was partial"
fi

# ── empty queue: say so and stop, never widen ─────────────────────────────────────────────────────
reset_state
printf 'sha\trefs/heads/tc/cbrd-11111\nsha\trefs/heads/tc/cbrd-22222\nsha\trefs/heads/tc/cbrd-33333\n' > "$STUB_DIR/fork.refs"
run "everything processed" 3 "broadening Select"
echo '{"total":0,"issues":[]}' > "$STUB_DIR/jql.json"
reset_state
run "JQL returns nothing" 3 "queue is empty"

# ── an existing manifest must survive the patch ────────────────────────────────────────────────────
cat > "$STUB_DIR/jql.json" <<'JSON'
{"total":1,"issues":[{"key":"CBRD-11111","fields":{"summary":"s","issuetype":{"name":"Correct Error"},"resolutiondate":"2025-01-02T03:04:05.000+0900","customfield_210565":{"value":"Required"}}}]}
JSON
reset_state
mkdir -p "$HOME/.cubrid-agent/CBRD-11111"
echo '{"issue":"CBRD-11111","author":{"path":"sql/x/cbrd_11111/cases/a.sql"}}' > "$HOME/.cubrid-agent/CBRD-11111/manifest.json"
bash "$SRC" >/dev/null 2>&1
if jq -e '.author.path == "sql/x/cbrd_11111/cases/a.sql" and (.select.queue|has("summary"))' \
     "$HOME/.cubrid-agent/CBRD-11111/manifest.json" >/dev/null 2>&1; then
  T_PASS=$((T_PASS+1))
else
  T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    patching select.queue destroyed the rest of an existing manifest"
fi

if [ "$T_FAIL" -eq 0 ]; then
  printf 'select-queue: %d/%d\n' "$T_PASS" "$T_PASS"
  exit 0
else
  printf 'select-queue: %d passed, %d FAILED%s\n' "$T_PASS" "$T_FAIL" "$FAILURES"
  exit 1
fi
