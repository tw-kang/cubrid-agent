#!/bin/bash
# TC convention lint — after a TC .sql write, lint mechanical rules and record them
# into the run manifest so the PreToolUse submit gate can't be silently bypassed.
# Event: PostToolUse / Write|Edit. Non-blocking (feedback only).
set -u

INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Only lint cubrid-testcases TC .sql under a cases/ dir.
case "$FILE" in */cases/cbrd_*.sql) ;; *) exit 0 ;; esac
[ -f "$FILE" ] || exit 0

KEY=$(printf '%s' "$FILE" | grep -oiE 'cbrd_[0-9]+' | head -1 | sed 's/_/-/' | tr '[:lower:]' '[:upper:]')

# Mechanical rules (hook-checkable). answer_not_handwritten is provenance — orchestrator records it.
# The key has to be INSIDE the header block, not on the `/**` line: the corpus convention opens the
# block on its own line and names the issue on the next one ("* This test case verifies CBRD-XXXXX:").
# The single-line regex this replaces matched 0 of the 47 corpus TCs that have a header block, while
# all 47 name the key inside it — so `lint.header` was false for every correctly authored testcase, and
# the submit gate blocks on that field. The only thing it rewarded was a shape the corpus does not use.
header=false
awk '/^\/\*\*/{f=1} f{print} /\*\//{if(f)exit}' "$FILE" | grep -qE 'CBRD-[0-9]+' && header=true
evaluate=false; grep -qE "evaluate[[:space:]]+'[Cc]ase" "$FILE" && evaluate=true
cleanup=true
grep -qiE 'create[[:space:]]+table' "$FILE" && { grep -qiE 'drop[[:space:]]+table[[:space:]]+if[[:space:]]+exists' "$FILE" || cleanup=false; }
english=true
grep -E '^[[:space:]]*--' "$FILE" | LC_ALL=C grep -q '[^[:print:][:blank:]]' && english=false

# The header says what the test verifies. Instructions aimed at a later pipeline stage must not be
# frozen into a corpus file that outlives the run; they belong in the report, the PR Remarks or
# verify.preconditions. Two bounds, because the header serves a reviewer and a later skill:
#   header_scope — vocabulary; fires on 0 of 58 human-authored corpus headers.
#   header_size  — 20 lines. Corpus, measured 2026-08-03: median 9, p75 16, p90 24, 52/59 within 20.
header_scope=true
awk '/^\/\*\*/{f=1} f{print} /\*\//{if(f)exit}' "$FILE" \
  | grep -qEi '(Verify|Review) lane|MUST check|manifest|fail->pass|fail→pass|subagent|Draft PR|the report' \
  && header_scope=false

# `--` inside the /** */ header breaks the run: CTP reads the header line by line and treats `--` as
# a SQL line comment, so the statements after it are swallowed. Write " - ", not " -- ".
header_no_dashdash=true
awk '/^\/\*\*/{f=1} f{print} /\*\//{if(f)exit}' "$FILE" | grep -q -- '--' && header_no_dashdash=false

header_size=true
hlines=$(awk '/^\/\*\*/{f=1} f{c++} /\*\//{if(f){print c; exit}}' "$FILE")
[ -n "$hlines" ] && [ "$hlines" -gt 20 ] && header_size=false

# Advice, not a gate: length has a long tail, so there is no honest threshold to fail on, but writing
# to the 20-line ceiling lands well above practice. Thresholds are corpus p75s; `--` comments across
# 380 cases: median 1, p75 4, and 189 have none.
advice=""
[ -n "$hlines" ] && [ "$hlines" -gt 16 ] \
  && advice="$advice header is $hlines lines against a corpus p75 of 16 (median 9) — the Coverage list is the usual cause, and the evaluate labels already name every case;"
_cmt=$(grep -cE '^[[:space:]]*--[^+]' "$FILE")
[ "${_cmt:-0}" -gt 4 ] \
  && advice="$advice $_cmt inline \`--\` comments against a corpus p75 of 4 (median 1; half the corpus has none) — drop what the statement already says, keep only a reason that would not survive a rewrite;"

MDIR="$HOME/.cubrid-agent/$KEY"
MANIFEST="$MDIR/manifest.json"
mkdir -p "$MDIR"
[ -f "$MANIFEST" ] || printf '{}' > "$MANIFEST"

# Placement: a bug fix belongs under _13_issues, a release dir is for every other
# kind of change. Both TCs the pipeline produced went to `sql/_36_guava/cbrd_XXXXX/` and both drew
# the same review objection — the orchestrator hardcoded that path and create-sql's example cited
# one of them, so nothing in the run could notice.
#
# The rule is the issue type alone: `Correct Error` (the only bug type in CBRD) -> _13_issues,
# whatever its version fields say. A shipped bug fix is still a bug fix. No version is consulted,
# neither the Planned Version the queue filters on nor fixVersions. The hook cannot see the type
# from the file, so Select records it; an unrecorded type is reported as unverifiable, not a pass.
#
# Narrow on purpose: only the per-issue release dir (`sql/_NN_name/cbrd_XXXXX/cases/`). A bug case
# added to an existing feature-group dir is legitimate.
case "$FILE" in
  */sql/_13_issues/*/cases/*)                 _tree=issues ;;
  */sql/_[0-9][0-9]_*/cbrd_[0-9]*/cases/*)    _tree=release_per_issue ;;
  *)                                          _tree=other ;;
esac
# Half-year sub-dir. `_13_issues/_{yy}_{1|2}h` is the half-year the TC is WRITTEN in, not any date on
# the issue — the corpus is unambiguous (each dir's first commit falls inside its own label: _24_2h
# 2024-07-30, _25_1h 2025-01-15, _25_2h 2025-08-07, _26_1h 2026-01-19) while the issues inside span
# other years. The rule as written said only "{yy} = 2-digit year" and a run put a 2026-07 TC in
# _25_2h, the same ambiguity that once sent bug TCs to a release dir.
# Only a NEW case file has to land in the current half-year: old dirs keep receiving edits to
# existing TCs long after they stop receiving new cases, and flagging those would be noise.
halfyear=true
_curhy="_$(date +%y)_$([ "$(date +%-m)" -le 6 ] && echo 1 || echo 2)h"
if [ "$_tree" = issues ]; then
  _hy=$(printf '%s' "$FILE" | sed -n 's#.*/sql/_13_issues/\([^/]*\)/cases/.*#\1#p')
  if [ -n "$_hy" ] && [ "$_hy" != "$_curhy" ] \
     && ! git -C "$(dirname "$FILE")" ls-files --error-unmatch "$FILE" >/dev/null 2>&1; then
    halfyear=false
  fi
fi

_itype=$(jq -r '.select.issue_type // empty' "$MANIFEST" 2>/dev/null)
_pwhy=""
if [ -z "$_itype" ]; then
  placement=null   # cannot decide — Select did not record the issue type
elif [ "$_itype" = "Correct Error" ] && [ "$_tree" = release_per_issue ]; then
  placement=false; _pwhy=tree
elif [ "$halfyear" = false ]; then
  placement=false; _pwhy=halfyear
else
  placement=true
fi
tmp=$(mktemp)
if jq --arg k "$KEY" --argjson h "$header" --argjson e "$evaluate" --argjson c "$cleanup" \
      --argjson en "$english" --argjson hs "$header_scope" --argjson hz "$header_size" \
      --argjson pl "$placement" --argjson hd "$header_no_dashdash" \
   '.issue=(.issue//$k) | .author.sql_writes=((.author.sql_writes // 0) + 1) | .lint.header=$h | .lint.evaluate=$e | .lint.cleanup=$c | .lint.english_comments=$en | .lint.header_scope=$hs | .lint.header_size=$hz | .lint.header_no_dashdash=$hd | .lint.placement=$pl' \
   "$MANIFEST" > "$tmp" 2>/dev/null; then mv "$tmp" "$MANIFEST"; else rm -f "$tmp"; fi

probs=""
[ "$header" = true ]   || probs="$probs missing header block (/** …CBRD-XXXXX… */);"
[ "$evaluate" = true ] || probs="$probs missing evaluate 'Case N' label;"
[ "$cleanup" = true ]  || probs="$probs missing DROP TABLE IF EXISTS before CREATE TABLE;"
[ "$english" = true ]  || probs="$probs non-English text in comments (comments must be English);"
[ "$header_scope" = true ] || probs="$probs header talks to the pipeline instead of describing the test — move stage instructions to the report, reviewer constraints to the PR Remarks, and run-validity preconditions to verify.preconditions;"
[ "$header_size" = true ]  || probs="$probs header is $hlines lines (max 20) — compress the wording, don't drop coverage items;"
[ "$header_no_dashdash" = true ] || probs="$probs header contains \`--\`, which CTP reads as a SQL line comment so the case stops running — use a single hyphen;"
[ "$_pwhy" = tree ]     && probs="$probs wrong tree: a bug fix (Correct Error) belongs in sql/_13_issues/_{yy}_{1|2}h/cases/ regardless of its version fields, not in a release dir (create the half-year dir if it does not exist yet) — see create-sql's directory convention;"
[ "$_pwhy" = halfyear ] && probs="$probs wrong half-year dir: a new case goes in $_curhy (the half-year you are writing it in), not $_hy — no date on the issue selects this dir; create $_curhy if it does not exist yet;"
[ "$placement" = null ]  && probs="$probs placement unverifiable: record select.issue_type in the manifest during Select, so the tree can be checked against the issue type;"
_msg=""
[ -z "$probs" ]  || _msg="[TC lint] $FILE convention violations:$probs (recorded in manifest.lint — the submit gate will block)"
if [ -n "$advice" ]; then
  [ -n "$_msg" ] && _msg="$_msg
"
  _msg="$_msg[TC lint] $FILE reads long against the corpus:$advice Advice only — nothing records or blocks on this."
fi
[ -z "$_msg" ] || jq -n --arg m "$_msg" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}'
exit 0
