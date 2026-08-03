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
# The answer half of the same argument (S1): the empty-answer trick was five prose steps — seed an
# empty .answer, run, hunt the .result, eyeball it, `cp` it over — and each was its own model turn even
# though only the eyeballing is judgment. --generate does the seeding, the run, and PRINTS the produced
# output so the judging happens in the same turn; --promote does the copy and records that the answer
# came from CTP rather than a keyboard (which is exactly what lint.answer_not_handwritten claims).
# They are deliberately two calls: the judgment between them is the whole point of the trick.
#
# Usage: verify-run.sh CBRD-XXXXX [--runs N] [--category sql|sql_by_cci] [--tc-path PATH]
#                                 [--timeout SECONDS] [--generate | --promote [--from PATH]]
set -u

SELF_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
# shellcheck source=common.sh disable=SC1091
. "$SELF_DIR/common.sh" || { printf 'verify-run: common.sh is not next to me (%s) — re-run /setup-cubrid-agent.\n' "$SELF_DIR" >&2; exit 1; }

USAGE='verify-run.sh CBRD-XXXXX [--runs N] [--category sql|sql_by_cci] [--tc-path PATH] [--timeout SECONDS] [--generate|--promote [--from PATH]] [--no-manifest] [--log-label S]'
KEY=""; RUNS=3; CATEGORY=sql; TCPATH=""; TIMEOUT=900; GENERATE=0; PROMOTE=0; FROM=""; NORECORD=0; LABEL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --runs)     RUNS=${2:-3}; shift 2 ;;
    --category) CATEGORY=${2:-sql}; shift 2 ;;
    --tc-path)  TCPATH=${2:-}; shift 2 ;;
    --timeout)  TIMEOUT=${2:-900}; shift 2 ;;
    --generate) GENERATE=1; shift ;;
    --promote)  PROMOTE=1; shift ;;
    --from)     FROM=${2:-}; shift 2 ;;
    # For a run whose result must NOT become the record: failpass-run.sh runs this testcase on a
    # PRE-FIX build, where a Fail is the desired outcome. Recording it would delete verify.status and
    # overwrite determinism with the deliberate failure — the submit gate would then read the pre-fix
    # run as the verification.
    --no-manifest) NORECORD=1; shift ;;
    # Without a label every run of the same category writes verify-<category>.log, so the pre-fix run,
    # the debug run and the release verification each overwrote the evidence of the one before — and a
    # caller that greps that log for engine markers would then read a different run's output.
    --log-label)   LABEL=${2:-}; shift 2 ;;
    -h|--help)  printf '%s\n' "$USAGE"; exit 0 ;;
    -*)         reject_unknown "$USAGE" "$1" ;;
    *)          KEY=$(parse_issue_key "$1"); shift ;;
  esac
done
[ -n "$KEY" ] || { printf 'verify-run: need an issue key\n%s\n' "$USAGE" >&2; exit 1; }
if [ "$GENERATE" = 1 ] && [ "$PROMOTE" = 1 ]; then
  printf 'verify-run: --generate and --promote cannot be combined — you must read the generated output and decide it matches the issue'"'"'s stated post-fix behavior before promoting it. That judgment is the reason the answer is generated instead of written.\n' >&2
  exit 1
fi
[ "$GENERATE" = 1 ] && RUNS=1
case "$RUNS" in ''|*[!0-9]*) printf 'verify-run: --runs must be a number\n' >&2; exit 1 ;; esac
[ "$RUNS" -ge 1 ] || RUNS=1

RUN_DIR="$HOME/.cubrid-agent/$KEY"
MANIFEST="$RUN_DIR/manifest.json"
mkdir -p "$RUN_DIR"

# env.sh (sourced by common.sh) is what setup.sh resolved once for this machine (CUBRID, CTP_HOME, JAVA_HOME).
CTP_HOME=${CTP_HOME:-}
[ -n "$CTP_HOME" ] || { for d in "$HOME/CTP" "$HOME/cubrid-testtools/CTP"; do [ -x "$d/bin/ctp.sh" ] && CTP_HOME=$d && break; done; }

# jq patches the manifest in place; without it the run still happens but nothing is recorded, and a
# silently unrecorded verify is exactly what the submit gate cannot distinguish from a skipped one.
HAVE_JQ=0; command -v jq >/dev/null 2>&1 && HAVE_JQ=1
# Values go in through --arg, never string-interpolated into the filter: a result directory or a
# note carrying a quote would otherwise produce a malformed jq program and lose the whole record.
patch_manifest() {  # patch_manifest <jq filter> [--arg k v ...]
  _filter=$1; shift
  [ "$NORECORD" = 0 ] || return 0
  [ "$HAVE_JQ" = 1 ] || { printf '  (jq missing — manifest NOT updated; install jq and re-run)\n'; return 0; }
  [ -f "$MANIFEST" ] || printf '{}\n' > "$MANIFEST"
  jq "$@" "$_filter" "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"
}

# The summary line has to answer the same question patch_manifest just did. Saying "recorded:" after a
# --no-manifest run is the same contradiction as naming the wrong field, pointed the other way: the
# reader either trusts a record that does not exist, or stops to check whether one was overwritten.
rec() {  # rec <what the manifest patch above would have written>
  if [ "$NORECORD" = 0 ]; then printf '  recorded: %s\n' "$1"
  else printf '  not recorded (--no-manifest): %s\n' "$1"; fi
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

# CTP's interactive `run` takes a path relative to the conf's scenario root, and it accepts the CASE FILE
# itself — measured: `run _13_issues/_26_2h/cases/cbrd_25913.sql` reports Total:1 while
# `run _13_issues/_26_2h` reports Total:2. Passing the directory was wrong in both directions. Every
# bug-fix TC lives in `_13_issues/<half>/cases/` alongside its siblings (that is the corpus convention,
# not a per-issue directory), so the directory form ran unrelated cases and folded their results into
# this verdict: the pass count stopped being 1, so `Success:1` never matched and all_pass was false
# forever, while two failing cases reported `Fail:2` and the failure became invisible.
REL=$(printf '%s' "$SQL" | sed -E "s|^$TC/sql/||")
ANSWER=$(printf '%s' "$SQL" | sed 's|/cases/|/answers/|; s|\.sql$|.answer|')

# The CCI cross-check keeps its answer in a sidecar: promoting CCI output over .answer would replace
# the JDBC-confirmed answer with another driver's output, and the two differ on purpose when they do.
ANSWER_TARGET=$ANSWER
[ "$CATEGORY" = sql_by_cci ] && ANSWER_TARGET="${ANSWER}_cci"

if [ "$PROMOTE" = 1 ]; then
  SRC=$FROM
  [ -n "$SRC" ] || SRC=$([ "$HAVE_JQ" = 1 ] && [ -f "$MANIFEST" ] && jq -r '.verify.answer.result // empty' "$MANIFEST" 2>/dev/null)
  [ -n "$SRC" ] || { printf 'verify-run: nothing to promote — run --generate first (it records the .result path), or pass --from PATH.\n' >&2; exit 1; }
  [ -f "$SRC" ] || { printf 'verify-run: %s no longer exists. CTP overwrites its result on every run, so re-run --generate.\n' "$SRC" >&2; exit 1; }
  mkdir -p "$(dirname "$ANSWER_TARGET")" && cp "$SRC" "$ANSWER_TARGET" || exit 1
  printf '[verify] %s  promoted CTP output → %s (%s lines)\n' "$KEY" "$ANSWER_TARGET" "$(wc -l < "$ANSWER_TARGET" | tr -d ' ')"
  # lint.answer_not_handwritten is a claim about provenance, so the step that establishes it writes it:
  # this file is a byte copy of what the engine printed. An agent asserting the same field about its own
  # work is the weakest possible evidence for the one thing the field exists to rule out.
  patch_manifest '.verify.answer = ((.verify.answer // {}) + {result: $s, promoted: true, target: $t})
    | .lint = ((.lint // {}) + {answer_not_handwritten: true})' --arg s "$SRC" --arg t "$ANSWER_TARGET"
  rec 'verify.answer.promoted, lint.answer_not_handwritten=true (byte copy of CTP output)'
  printf '  next : confirm it — verify-run.sh %s --runs 3 — then commit the answer alongside the case.\n' "$KEY"
  exit 0
fi

if [ "$GENERATE" = 1 ]; then
  if [ -s "$ANSWER_TARGET" ]; then
    printf 'verify-run: %s already has content (%s lines) — generation is for an answer that does not exist yet, and overwriting one that does would destroy a confirmed answer. Move it aside first if you really mean to regenerate.\n' \
      "$ANSWER_TARGET" "$(wc -l < "$ANSWER_TARGET" | tr -d ' ')" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$ANSWER_TARGET")" && : > "$ANSWER_TARGET" \
    || { printf 'verify-run: could not seed an empty answer at %s\n' "$ANSWER_TARGET" >&2; exit 1; }
  # Measured, because the prose had it wrong: an empty answer file does not make CTP *skip* the case —
  # nothing can match an empty answer, so it reports Fail:1 and writes the engine's real output to the
  # result directory. That Fail is the expected outcome of generation, not a problem to report.
  printf '  seeded : empty %s — nothing matches an empty answer, so CTP reports Fail and writes the real output to the result dir (that Fail is expected here)\n' "$ANSWER_TARGET"
fi

[ -f "$ANSWER" ] || printf '  warning: no answer file at %s — CTP will SKIP the case (Total:1 Success:0 Fail:0)\n' "$ANSWER"

CONF_SRC="$CTP_HOME/conf/$CATEGORY.conf"
[ -f "$CONF_SRC" ] || blocked blocked_no_ctp "$CONF_SRC missing — cannot run category '$CATEGORY'"
CONF="$RUN_DIR/$CATEGORY.conf"
sed "s|^scenario=.*|scenario=$TC/sql|" "$CONF_SRC" > "$CONF"

RUN_CMD=run
[ "$CATEGORY" = sql_by_cci ] && RUN_CMD=run_cci
LOG="$RUN_DIR/verify-$CATEGORY${LABEL:+.$LABEL}.log"

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

# Generation ends here: with an empty answer CTP reports Success:0 Fail:0 by design, so the pass/fail
# bookkeeping below would call the expected outcome a failure. What matters is the output itself, and it
# is printed rather than pointed at — the judgment ("is this the post-fix behavior the issue states?")
# then happens in the same turn instead of costing another read.
if [ "$GENERATE" = 1 ]; then
  RESULT_FILE=""
  [ -n "$RESULT_DIR" ] && RESULT_FILE=$(find "$RESULT_DIR" -name '*.result' 2>/dev/null | head -1)
  if [ -z "$RESULT_FILE" ]; then
    printf '  no .result under %s — nothing was produced to promote. Log: %s\n' "${RESULT_DIR:-<the log names no result directory>}" "$LOG"
    patch_manifest '.verify.answer = ((.verify.answer // {}) + {promoted: false, log: $l}) | del(.verify.answer.result)' --arg l "$LOG"
    exit 1
  fi
  _n=$(wc -l < "$RESULT_FILE" | tr -d ' ')
  printf '  result : %s (%s lines)\n' "$RESULT_FILE" "$_n"
  patch_manifest '.verify.answer = ((.verify.answer // {}) + {result: $r, promoted: false})' --arg r "$RESULT_FILE"
  if [ "$_n" -gt 80 ]; then printf '  ---- CTP output, first 80 of %s lines (read the file for the rest) ----\n' "$_n"
  else printf '  ---- CTP output (whole file) ----\n'; fi
  sed -n '1,80p' "$RESULT_FILE" | sed 's/^/  | /'
  printf '  ---- end ----\n'
  printf '  YOUR call: does this match the post-fix behavior the issue states (error code, row count, message)?\n'
  printf '  yes → verify-run.sh %s --promote%s   ·   no → fix the .sql and regenerate; never edit this output by hand\n' \
    "$KEY" "$([ "$CATEGORY" != sql ] && printf ' --category %s' "$CATEGORY")"
  exit 0
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

# The CCI cross-check is a DIFFERENT question from the run that produced the answer, so it gets its own
# field instead of overwriting this one's. It used to write verify.determinism/status/category, which
# turned "3 runs, all pass" into "1 run" the moment the cross-check ran — the evidence still said passed,
# but it no longer described the run it claimed to. And since this helper already knows whether CCI
# matched, it records verify.cci itself rather than asking the agent to retype what it just measured.
if [ "$CATEGORY" = sql_by_cci ]; then
  patch_manifest '.verify.cci = {checked: true, matches_jdbc: ($p == "true"), runs: ($r|tonumber), log: $l}
    | (if $df != "" then .verify.cci.diff = $df else . end)' \
    --arg r "$RUNS" --arg p "$ALL_PASS" --arg l "$LOG" --arg df "$DIFF"
else
patch_manifest '.verify = ((.verify // {}) + {build: $b, category: $c,
                             determinism: {runs: ($r|tonumber), all_pass: ($p == "true")}, log: $l})
  | (if $rd != "" then .verify.result_dir = $rd else del(.verify.result_dir) end)
  | (if $df != "" then .verify.diff = $df else del(.verify.diff) end)
  | (if $p == "true" then .verify.status = "passed" else del(.verify.status) end)' \
  --arg b "$BUILD" --arg c "$CATEGORY" --arg r "$RUNS" --arg p "$ALL_PASS" \
  --arg l "$LOG" --arg rd "$RESULT_DIR" --arg df "$DIFF"
fi

if [ "$ALL_PASS" = true ]; then
  # The message has to name the field that was actually written, or it becomes another record that
  # contradicts the run it describes.
  if [ "$CATEGORY" = sql_by_cci ]; then
    rec 'verify.cci(checked=true, matches_jdbc=true) — the CCI output matches the answer, so no .answer_cci sidecar is needed'
    printf '  NOT recorded (your judgment): fail_to_pass attribution, whether this build contains the fix\n'
  else
    rec 'verify.build, verify.determinism(all_pass=true), verify.status=passed'
    printf '  NOT recorded (your judgment): fail_to_pass attribution, whether this build contains the fix, cci cross-check\n'
  fi
  exit 0
else
  if [ "$CATEGORY" = sql_by_cci ]; then
    rec "verify.cci(checked=true, matches_jdbc=false)$([ -n "$DIFF" ] && printf ', verify.cci.diff') — the CCI output differs, so promote it to the .answer_cci sidecar with --promote --category sql_by_cci"
  else
    rec "verify.build, verify.determinism(all_pass=false)$([ -n "$DIFF" ] && printf ', verify.diff') — verify.status left unset"
  fi
  printf '  A mismatch is not automatically the testcase being wrong. Read the diff before deciding.\n'
  exit 1
fi
