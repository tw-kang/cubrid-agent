#!/bin/bash
# Behavioural test for record-preconditions.sh — the lane report -> manifest transfer.
#
# Dev-only, run by check-invariants.sh. Offline: a throwaway $HOME, nothing else on the machine is
# touched.
#
# What it pins: R1 opens each precondition unverified, R2 closes it with its evidence, neither can
# do the other's half, and a malformed report fails loudly instead of recording nothing. The last
# case runs render-report.sh for real, because "an unverified precondition means the result is
# inconclusive" is only true if it actually reaches the artefact a human reads.
set -u

BIN_DIR=$(cd "$(dirname "$(readlink -f "$0")")/../skills/qa/setup-cubrid-agent/bin" && pwd)
SRC="$BIN_DIR/record-preconditions.sh"
[ -f "$SRC" ] || { echo "test-record-preconditions: script not found at $SRC" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "test-record-preconditions: jq is required." >&2; exit 1; }

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
KEY=CBRD-99999
RUN="$HOME/.cubrid-agent/$KEY"
MANIFEST="$RUN/manifest.json"
mkdir -p "$RUN"

T_PASS=0; T_FAIL=0; FAILURES=""
note_fail() { T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    $1"; }
ok() { T_PASS=$((T_PASS+1)); }

# The report path is an argument, so every case names its own file — a stale one must never be what
# the next assertion reads.
report() {  # report <name> <json>
  printf '%s\n' "$2" > "$RUN/$1"
  printf '%s' "$RUN/$1"
}
reset_manifest() { printf '{"issue":"%s"}\n' "$KEY" > "$MANIFEST"; }

run() {  # run <args...> -> stdout+stderr, sets RC
  OUT=$(bash "$SRC" "$@" 2>&1); RC=$?
}

expect_rc() {  # expect_rc <name> <wanted rc>
  [ "$RC" -eq "$2" ] && { ok; return; }
  note_fail "$1: exit $RC, expected $2 — output: $OUT"
}
expect_out() {  # expect_out <name> <fragment>
  case "$OUT" in *"$2"*) ok ;; *) note_fail "$1: output does not mention \"$2\" — got: $OUT" ;; esac
}
expect_jq() {  # expect_jq <name> <jq filter> <wanted>
  _got=$(jq -r "$2" "$MANIFEST" 2>/dev/null)
  [ "$_got" = "$3" ] && { ok; return; }
  note_fail "$1: \`$2\` is \"$_got\", expected \"$3\""
}

R1_TWO='{"lane":"review-r1","round":1,"verdict":"NEEDS-WORK","preconditions":[
  {"id":"server-parallelism","cond":"parallelism >= 2, else the sort runs serial and never enters the fixed path"},
  {"id":"heap-page-threshold","cond":"t heap spans >= 2048 data pages"}]}'

# ── R1 opens the preconditions, always unverified ────────────────────────────────────────────────
reset_manifest
run "$KEY" --from "$(report review-r1-1.json "$R1_TWO")"
expect_rc "R1 records two preconditions" 0
expect_jq "R1: both landed" '.verify.preconditions | length' 2
expect_jq "R1: first id" '.verify.preconditions[0].id' server-parallelism
expect_jq "R1: cond is carried verbatim" '.verify.preconditions[0].cond' \
  'parallelism >= 2, else the sort runs serial and never enters the fixed path'
# R1 runs before Verify, so it cannot know the answer — verified is the script's to set, not R1's.
expect_jq "R1: opens unverified" '[.verify.preconditions[] | select(.verified == false)] | length' 2
expect_out "R1: reports what is still open" "2 unverified"

# Re-running the same round must not duplicate: the id is the identity.
run "$KEY" --from "$RUN/review-r1-1.json"
expect_rc "R1 re-run succeeds" 0
expect_jq "R1 re-run does not duplicate" '.verify.preconditions | length' 2

# ── R2 closes them, with its evidence ────────────────────────────────────────────────────────────
R2_ONE='{"lane":"review-r2","round":1,"verdict":"NEEDS-WORK","preconditions":[
  {"id":"server-parallelism","verified":true,"evidence":"queryplan shows the parallel sort node on all 3 runs"}]}'
run "$KEY" --from "$(report review-r2-1.json "$R2_ONE")"
expect_rc "R2 closes one precondition" 0
expect_jq "R2: closed one" '[.verify.preconditions[] | select(.verified == true)] | length' 1
expect_jq "R2: evidence is recorded" '.verify.preconditions[0].evidence' \
  'queryplan shows the parallel sort node on all 3 runs'
expect_jq "R2: the untouched one stays open" '.verify.preconditions[1].verified' false
expect_jq "R2: R1's cond survives the merge" '.verify.preconditions[0].cond' \
  'parallelism >= 2, else the sort runs serial and never enters the fixed path'
# An unverified precondition means the result is inconclusive — the caller has to be told, not left
# to notice.
expect_out "R2: still-open preconditions are named" "heap-page-threshold"

# A later R1 round must not undo what R2 established.
run "$KEY" --from "$RUN/review-r1-1.json"
expect_rc "R1 after R2 succeeds" 0
expect_jq "a later R1 round does not reopen a verified precondition" '.verify.preconditions[0].verified' true

# ── Everything closed: no warning ────────────────────────────────────────────────────────────────
R2_BOTH='{"lane":"review-r2","round":2,"verdict":"PASS","preconditions":[
  {"id":"server-parallelism","verified":true,"evidence":"queryplan"},
  {"id":"heap-page-threshold","verified":true,"evidence":"6 byte-identical runs"}]}'
run "$KEY" --from "$(report review-r2-2.json "$R2_BOTH")"
expect_rc "R2 closes the rest" 0
expect_jq "all verified" '[.verify.preconditions[] | select(.verified == true)] | length' 2
case "$OUT" in
  *unverified*) note_fail "all preconditions verified, yet the output still warns: $OUT" ;;
  *) ok ;;
esac

# R2 may also record a negative result — that is a finding, not an error.
R2_NEG='{"lane":"review-r2","round":3,"verdict":"NEEDS-WORK","preconditions":[
  {"id":"heap-page-threshold","verified":false,"evidence":"heap was 1200 pages, under the 2048 threshold"}]}'
run "$KEY" --from "$(report review-r2-3.json "$R2_NEG")"
expect_rc "R2 may report a precondition as not met" 0
expect_jq "the negative result is recorded" '.verify.preconditions[1].verified' false
expect_jq "and so is why" '.verify.preconditions[1].evidence' 'heap was 1200 pages, under the 2048 threshold'

# ── Malformed input fails loudly — recording nothing must never read as success ──────────────────
reset_manifest
run "$KEY" --from "$RUN/does-not-exist.json"
expect_rc "missing report is an error" 1

run "$KEY" --from "$(report broken.json '{"lane":"review-r1", "preconditions": [')"
expect_rc "unparseable JSON is an error" 1
expect_out "unparseable JSON says so" "JSON"

# An empty file passes `jq -e 'type == "object"'` (jq exits 0 on no output), so without its own
# check it is diagnosed as "no .lane field" — a right refusal for the wrong reason, which sends the
# reader to fix a field that is not the problem. Each case asserts the diagnosis, not just the exit.
# The filename must not contain the word being asserted — it reaches the message through the path.
: > "$RUN/blank.json"
run "$KEY" --from "$RUN/blank.json"
expect_rc "an empty report is an error" 1
expect_out "an empty report is diagnosed as empty" "is empty"

# The field being absent is the failure this exists to catch: a lane that forgot the block would
# otherwise record zero preconditions and look like a clean run.
run "$KEY" --from "$(report no-field.json '{"lane":"review-r1","round":1,"verdict":"PASS"}')"
expect_rc "a missing preconditions field is an error" 1
expect_out "a missing preconditions field is diagnosed as missing" ".preconditions"
expect_out "and the report is told what to write instead" "[]"

# An explicit empty list is a judgment ("this run needs none"), not an omission.
run "$KEY" --from "$(report empty.json '{"lane":"review-r1","round":1,"verdict":"PASS","preconditions":[]}')"
expect_rc "an explicit empty list is allowed" 0
expect_jq "empty list records nothing" '.verify.preconditions | length' 0

run "$KEY" --from "$(report r1-no-cond.json '{"lane":"review-r1","round":1,"preconditions":[{"id":"x"}]}')"
expect_rc "R1 without cond is an error" 1
run "$KEY" --from "$(report r1-no-id.json '{"lane":"review-r1","round":1,"preconditions":[{"cond":"x"}]}')"
expect_rc "R1 without id is an error" 1

# The lane field decides which half of the contract applies, so an unknown one cannot be guessed.
run "$KEY" --from "$(report author.json '{"lane":"author","round":1,"summary":"wrote the sql"}')"
expect_rc "an author report is not a precondition source" 1
run "$KEY" --from "$(report no-lane.json '{"round":1,"preconditions":[]}')"
expect_rc "a report with no lane is an error" 1

# R2 judges what R1 raised. An id R1 never opened means the two lanes disagree about what was
# checked, and silently adding it would hide that.
reset_manifest
run "$KEY" --from "$(report review-r1-1.json "$R1_TWO")"
run "$KEY" --from "$(report r2-unknown.json '{"lane":"review-r2","round":1,"preconditions":[{"id":"never-raised","verified":true,"evidence":"e"}]}')"
expect_rc "R2 cannot close a precondition R1 never raised" 1
expect_out "R2 names the unknown id" "never-raised"

# "verified" without evidence is an assertion, not a verification.
run "$KEY" --from "$(report r2-no-ev.json '{"lane":"review-r2","round":1,"preconditions":[{"id":"server-parallelism","verified":true}]}')"
expect_rc "R2 cannot mark verified without evidence" 1

run "$KEY" --from "$(report r2-no-verified.json '{"lane":"review-r2","round":1,"preconditions":[{"id":"server-parallelism","evidence":"e"}]}')"
expect_rc "R2 without a verified flag is an error" 1

# ── Arguments ────────────────────────────────────────────────────────────────────────────────────
run
expect_rc "no arguments is an error" 1
run "$KEY"
expect_rc "no --from is an error" 1
run --from "$RUN/review-r1-1.json"
expect_rc "no issue key is an error" 1

# A run directory that does not exist yet is normal on a first call, not a failure.
NEWKEY=CBRD-99998
mkdir -p "$HOME/.cubrid-agent/$NEWKEY"
cp "$RUN/review-r1-1.json" "$HOME/.cubrid-agent/$NEWKEY/"
run "$NEWKEY" --from "$HOME/.cubrid-agent/$NEWKEY/review-r1-1.json"
expect_rc "a manifest that does not exist yet is created" 0
_n=$(jq -r '.verify.preconditions | length' "$HOME/.cubrid-agent/$NEWKEY/manifest.json" 2>/dev/null)
[ "$_n" = 2 ] && ok || note_fail "new manifest: got $_n preconditions, expected 2"

# ── The point of all of it: an unverified precondition reaches the human-read report ─────────────
# render-report.sh is the artefact a reviewer reads. If "inconclusive" does not surface there, the
# transfer above is bookkeeping with no consequence.
RENDER="$BIN_DIR/render-report.sh"
if [ -f "$RENDER" ]; then
  reset_manifest
  run "$KEY" --from "$(report review-r1-1.json "$R1_TWO")"
  rm -f "$HOME/.cubrid-agent/reports/author-testcase/$KEY.md"
  bash "$RENDER" "$KEY" --force >/dev/null 2>&1
  _rep="$HOME/.cubrid-agent/reports/author-testcase/$KEY.md"
  if grep -q 'server-parallelism' "$_rep" 2>/dev/null && grep -q '전제 2건' "$_rep" 2>/dev/null; then ok
  else note_fail "render-report does not show the recorded preconditions — $(grep -c . "$_rep" 2>/dev/null) lines rendered"; fi
  # verified=false must be visibly distinct from verified=true, or "inconclusive" is unreadable.
  if grep -qE '\[ \] server-parallelism' "$_rep" 2>/dev/null; then ok
  else note_fail "render-report does not mark the unverified precondition as open: $(grep -m1 'server-parallelism' "$_rep" 2>/dev/null)"; fi
else
  note_fail "render-report.sh missing at $RENDER — the artefact assertion could not run"
fi

if [ "$T_FAIL" -eq 0 ]; then
  printf 'record-preconditions: %d/%d\n' "$T_PASS" "$T_PASS"
  exit 0
else
  printf 'record-preconditions: %d passed, %d FAILED%s\n' "$T_PASS" "$T_FAIL" "$FAILURES"
  exit 1
fi
