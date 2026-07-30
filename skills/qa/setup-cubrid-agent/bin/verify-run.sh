#!/bin/bash
# Run one CTP testcase N times in ONE session, judge answer-consistency + determinism, and record the
# mechanical result in the run manifest. Installed to ~/.cubrid-agent/bin/ by /setup-cubrid-agent.
#
# Why this is a script and not skill prose (DP6): the rehearsal spent 13 Bash round-trips on this one
# chain — source env, copy conf, launch CTP, tail the log, hunt the result directory, diff, patch the
# manifest — and paid it again on every review round. Each round-trip is a model turn (~4 s fixed plus
# generation), so the sequence cost far more than the ~85 s of CTP setup it wraps. The steps are fully
# determined by the skill's own procedure, so the model has nothing to decide here.
#
# It deliberately does NOT decide: whether the build contains the fix, fail->pass attribution, or
# whether a mismatch means the testcase or the engine is wrong. Those are judgments; this only reports
# what CTP did and writes the facts a hook can gate on.
#
# Usage: verify-run.sh CBRD-XXXXX [--runs N] [--category sql|sql_by_cci] [--tc-path PATH]
#                                 [--timeout SECONDS] [--keep-conf]
set -u

USAGE='verify-run.sh CBRD-XXXXX [--runs N] [--category sql|sql_by_cci] [--tc-path PATH] [--timeout SECONDS]'
KEY=""; RUNS=3; CATEGORY=sql; TCPATH=""; TIMEOUT=900
while [ $# -gt 0 ]; do
  case "$1" in
    --runs)     RUNS=${2:-3}; shift 2 ;;
    --category) CATEGORY=${2:-sql}; shift 2 ;;
    --tc-path)  TCPATH=${2:-}; shift 2 ;;
    --timeout)  TIMEOUT=${2:-900}; shift 2 ;;
    -h|--help)  printf '%s\n' "$USAGE"; exit 0 ;;
    -*)         printf 'verify-run: unknown option: %s\n%s\n' "$1" "$USAGE" >&2; exit 1 ;;
    *)          KEY=$(printf '%s' "$1" | grep -oiE '[A-Z]+-[0-9]+' | head -1 | tr '[:lower:]' '[:upper:]'); shift ;;
  esac
done
[ -n "$KEY" ] || { printf 'verify-run: need an issue key\n%s\n' "$USAGE" >&2; exit 1; }
case "$RUNS" in ''|*[!0-9]*) printf 'verify-run: --runs must be a number\n' >&2; exit 1 ;; esac
[ "$RUNS" -ge 1 ] || RUNS=1

RUN_DIR="$HOME/.cubrid-agent/$KEY"
MANIFEST="$RUN_DIR/manifest.json"
mkdir -p "$RUN_DIR"

# env.sh is what setup.sh resolved once for this machine (CUBRID, CTP_HOME, JAVA_HOME).
# shellcheck disable=SC1090
[ -f "$HOME/.cubrid-agent/env.sh" ] && . "$HOME/.cubrid-agent/env.sh"
CTP_HOME=${CTP_HOME:-}
[ -n "$CTP_HOME" ] || { for d in "$HOME/CTP" "$HOME/cubrid-testtools/CTP"; do [ -x "$d/bin/ctp.sh" ] && CTP_HOME=$d && break; done; }
TC=${CUBRID_TESTCASES:-$HOME/cubrid-testcases}

# jq patches the manifest in place; without it the run still happens but nothing is recorded, and a
# silently unrecorded verify is exactly what the submit gate cannot distinguish from a skipped one.
HAVE_JQ=0; command -v jq >/dev/null 2>&1 && HAVE_JQ=1
# Values go in through --arg, never string-interpolated into the filter: a result directory or a
# note carrying a quote would otherwise produce a malformed jq program and lose the whole record.
patch_manifest() {  # patch_manifest <jq filter> [--arg k v ...]
  _filter=$1; shift
  [ "$HAVE_JQ" = 1 ] || { printf '  (jq missing — manifest NOT updated; install jq and re-run)\n'; return 0; }
  [ -f "$MANIFEST" ] || printf '{}\n' > "$MANIFEST"
  jq "$@" "$_filter" "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"
}

blocked() {  # blocked <status> <note>
  printf '[verify] %s — BLOCKED: %s\n  %s\n' "$KEY" "$1" "$2"
  patch_manifest '.verify = ((.verify // {}) + {status: $s, note: $n})' --arg s "$1" --arg n "$2"
  exit 3
}

[ -n "$CTP_HOME" ] && [ -x "$CTP_HOME/bin/ctp.sh" ] \
  || blocked blocked_no_ctp "CTP not found (tried \$CTP_HOME, ~/CTP, ~/cubrid-testtools/CTP) — install it, then re-run"

BUILD=""
if [ -x "${CUBRID:-$HOME/CUBRID}/bin/cubrid_rel" ]; then
  BUILD=$("${CUBRID:-$HOME/CUBRID}/bin/cubrid_rel" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-[0-9a-f]+' | head -1)
fi
[ -n "$BUILD" ] || blocked blocked_no_build "no CUBRID build under ${CUBRID:-$HOME/CUBRID} (cubrid_rel did not report a version) — install the build under test, then re-run"

# The testcase path comes from the manifest so the script verifies what the run actually authored.
[ -n "$TCPATH" ] || TCPATH=$([ "$HAVE_JQ" = 1 ] && [ -f "$MANIFEST" ] && jq -r '.author.path // empty' "$MANIFEST" 2>/dev/null)
[ -n "$TCPATH" ] || { printf 'verify-run: no testcase path — manifest has no .author.path and --tc-path was not given\n' >&2; exit 1; }
case "$TCPATH" in /*) SQL=$TCPATH ;; *) SQL="$TC/$TCPATH" ;; esac
[ -f "$SQL" ] || { printf 'verify-run: testcase not found: %s\n' "$SQL" >&2; exit 1; }

# CTP's interactive `run` takes the case directory relative to the conf's scenario root:
# .../sql/_36_guava/cbrd_26431/cases/x.sql -> _36_guava/cbrd_26431
REL=$(printf '%s' "$SQL" | sed -E "s|^$TC/sql/||; s|/cases/[^/]*$||")
ANSWER=$(printf '%s' "$SQL" | sed 's|/cases/|/answers/|; s|\.sql$|.answer|')
[ -f "$ANSWER" ] || printf '  warning: no answer file at %s — CTP will SKIP the case (Total:1 Success:0 Fail:0)\n' "$ANSWER"

CONF_SRC="$CTP_HOME/conf/$CATEGORY.conf"
[ -f "$CONF_SRC" ] || blocked blocked_no_ctp "$CONF_SRC missing — cannot run category '$CATEGORY'"
CONF="$RUN_DIR/$CATEGORY.conf"
sed "s|^scenario=.*|scenario=$TC/sql|" "$CONF_SRC" > "$CONF"

RUN_CMD=run
[ "$CATEGORY" = sql_by_cci ] && RUN_CMD=run_cci
LOG="$RUN_DIR/verify-$CATEGORY.log"

printf '[verify] %s  build %s  %s x%d\n  case : %s\n  conf : %s\n' "$KEY" "$BUILD" "$CATEGORY" "$RUNS" "$REL" "$CONF"

# One invocation, N runs inside it. Each invocation pays ~85 s of setup (JVM + DB + server) while an
# extra in-session run is ~1.5 s, so N separate invocations would waste (N-1)x85 s for nothing.
{ i=0; while [ "$i" -lt "$RUNS" ]; do printf '%s %s\n' "$RUN_CMD" "$REL"; i=$((i+1)); done; printf 'quit\n'; } \
  | timeout "$TIMEOUT" "$CTP_HOME/bin/ctp.sh" "$CATEGORY" -c "$CONF" --interactive > "$LOG" 2>&1
CTP_RC=$?

OK=$(grep -c '^Success:1' "$LOG" 2>/dev/null); OK=${OK:-0}
BAD=$(grep -c '^Fail:1' "$LOG" 2>/dev/null); BAD=${BAD:-0}
ELAPSE=$(grep -oE '^Elapse Time:[0-9]+' "$LOG" 2>/dev/null | grep -oE '[0-9]+' | tr '\n' ' ')
RESULT_DIR=$(grep -oE '^Test Result Directory:.*' "$LOG" 2>/dev/null | tail -1 | sed 's|^Test Result Directory:||')

ALL_PASS=false
[ "$OK" -eq "$RUNS" ] && [ "$BAD" -eq 0 ] && ALL_PASS=true

printf '  runs : %d/%d Success' "$OK" "$RUNS"
[ "$BAD" -gt 0 ] && printf ', %d Fail' "$BAD"
printf '   elapse: %s\n' "${ELAPSE:-?}"   # CTP prints no unit; do not assert one

if [ "$CTP_RC" -eq 124 ]; then
  blocked blocked_no_ctp "ctp.sh exceeded ${TIMEOUT}s and was killed — see $LOG"
fi
if [ "$OK" -eq 0 ] && [ "$BAD" -eq 0 ]; then
  printf '  CTP reported neither Success nor Fail — the case was skipped or the run died. Log: %s\n' "$LOG"
  patch_manifest '.verify = ((.verify // {}) + {build: $b, determinism: {runs: ($r|tonumber), all_pass: false}, log: $l})
    | del(.verify.status)' \
    --arg b "$BUILD" --arg r "$RUNS" --arg l "$LOG"
  exit 3
fi

# A mismatch is the interesting case, so hand over the diff rather than a pointer to go hunting.
# Every field this writes is set-or-deleted, never left behind: the manifest must describe THIS run.
# Both directions bit us in testing — a failing run inherited the previous "status": "passed", and a
# passing run kept the previous run's "diff" path. A record that contradicts the run it claims to
# describe is worse than no record, and gate-stop reads status.
DIFF=""
if [ "$ALL_PASS" != true ] && [ -n "$RESULT_DIR" ] && [ -f "$ANSWER" ]; then
  RESULT_FILE=$(find "$RESULT_DIR" -name '*.result' 2>/dev/null | head -1)
  if [ -n "$RESULT_FILE" ]; then
    DIFF="$RUN_DIR/verify-$CATEGORY.diff"
    diff "$ANSWER" "$RESULT_FILE" > "$DIFF" 2>&1
    printf '  diff : %s (%s lines)\n' "$DIFF" "$(grep -c . "$DIFF" 2>/dev/null || echo 0)"
    sed -n '1,20p' "$DIFF" | sed 's/^/    /'
  fi
fi

patch_manifest '.verify = ((.verify // {}) + {build: $b, category: $c,
                             determinism: {runs: ($r|tonumber), all_pass: ($p == "true")}, log: $l})
  | (if $rd != "" then .verify.result_dir = $rd else del(.verify.result_dir) end)
  | (if $df != "" then .verify.diff = $df else del(.verify.diff) end)
  | (if $p == "true" then .verify.status = "passed" else del(.verify.status) end)' \
  --arg b "$BUILD" --arg c "$CATEGORY" --arg r "$RUNS" --arg p "$ALL_PASS" \
  --arg l "$LOG" --arg rd "$RESULT_DIR" --arg df "$DIFF"

if [ "$ALL_PASS" = true ]; then
  printf '  recorded: verify.build, verify.determinism(all_pass=true), verify.status=passed\n'
  printf '  NOT recorded (your judgment): fail_to_pass attribution, whether this build contains the fix, cci cross-check\n'
  exit 0
else
  printf '  recorded: verify.build, verify.determinism(all_pass=false)%s — verify.status left unset\n' "$([ -n "$DIFF" ] && printf ', verify.diff')"
  printf '  A mismatch is not automatically the testcase being wrong. Read the diff before deciding.\n'
  exit 1
fi
