#!/bin/bash
# Stage 2 convention lint — after a TC .sql write, lint mechanical rules and record them
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
header=false;   grep -qE '/\*\*.*CBRD-[0-9]+' "$FILE" && header=true
evaluate=false; grep -qE "evaluate[[:space:]]+'[Cc]ase" "$FILE" && evaluate=true
cleanup=true
grep -qiE 'create[[:space:]]+table' "$FILE" && { grep -qiE 'drop[[:space:]]+table[[:space:]]+if[[:space:]]+exists' "$FILE" || cleanup=false; }
english=true
grep -E '^[[:space:]]*--' "$FILE" | LC_ALL=C grep -q '[^[:print:][:blank:]]' && english=false

# Header scope (CUBRIDQA-1481): the header says what the test verifies. Instructions aimed at a
# later pipeline stage must not be frozen into a corpus file that outlives the run — CBRD-26799's
# TC shipped "the Verify lane MUST check …" and "document the limit rather than claim
# guaranteed fail->pass" in its header. Those belong in the report, the PR Remarks, or
# verify.preconditions.
# Two independent bounds, because a header serves both a reviewer and a later skill
# (review-testcase judges from it; the next author greps the corpus through it):
#
#   header_scope — vocabulary. Measured on the corpus, it fires on 0 of 58 human-authored cbrd_*
#     headers and on the two worst lines of the leak above, so it separates run-talk from
#     test-description without flagging legitimate prose.
#   header_size  — 20 lines, so both audiences can scan it. 90% of existing corpus headers already
#     fit (median 7, p90 19). Three do not (25, 32, 34 lines, all human-authored); they are not
#     retroactively wrong because this hook only fires on a file being written.
header_scope=true
awk '/^\/\*\*/{f=1} f{print} /\*\//{if(f)exit}' "$FILE" \
  | grep -qEi '(Verify|Review) lane|MUST check|manifest|fail->pass|fail→pass|subagent|Draft PR|the report' \
  && header_scope=false

header_size=true
hlines=$(awk '/^\/\*\*/{f=1} f{c++} /\*\//{if(f){print c; exit}}' "$FILE")
[ -n "$hlines" ] && [ "$hlines" -gt 20 ] && header_size=false

MDIR="$HOME/.cubrid-agent/$KEY"
MANIFEST="$MDIR/manifest.json"
mkdir -p "$MDIR"
[ -f "$MANIFEST" ] || printf '{}' > "$MANIFEST"

# Placement (CUBRIDQA-1486): a bug fix belongs under _13_issues, a release dir is for every other
# kind of change. Both TCs the pipeline produced went to `sql/_36_guava/cbrd_XXXXX/` and both drew
# the same review objection — the orchestrator hardcoded that path and create-sql's example cited
# one of them, so nothing in the run could notice.
#
# The rule is the issue type alone: `Correct Error` (the only bug type in CBRD) -> _13_issues,
# whatever its version fields say. A shipped bug fix is still a bug fix. No version is consulted,
# neither the Planned Version the queue filters on nor fixVersions. The hook cannot see the type
# from the file, so Select records it; an unrecorded type is reported as unverifiable, not a pass.
#
# Deliberately narrow: it fires only on the per-issue release dir (`sql/_NN_name/cbrd_XXXXX/cases/`),
# the shape that was rejected. Adding a bug case to an existing feature-group dir (e.g.
# `sql/_19_apricot/_03_index_skip_scan/cases/`) is legitimate and must not be flagged.
case "$FILE" in
  */sql/_13_issues/*/cases/*)                 _tree=issues ;;
  */sql/_[0-9][0-9]_*/cbrd_[0-9]*/cases/*)    _tree=release_per_issue ;;
  *)                                          _tree=other ;;
esac
_itype=$(jq -r '.select.issue_type // empty' "$MANIFEST" 2>/dev/null)
if [ -z "$_itype" ]; then
  placement=null   # cannot decide — Select did not record the issue type
elif [ "$_itype" = "Correct Error" ] && [ "$_tree" = release_per_issue ]; then
  placement=false
else
  placement=true
fi
tmp=$(mktemp)
if jq --arg k "$KEY" --argjson h "$header" --argjson e "$evaluate" --argjson c "$cleanup" \
      --argjson en "$english" --argjson hs "$header_scope" --argjson hz "$header_size" \
      --argjson pl "$placement" \
   '.issue=(.issue//$k) | .lint.header=$h | .lint.evaluate=$e | .lint.cleanup=$c | .lint.english_comments=$en | .lint.header_scope=$hs | .lint.header_size=$hz | .lint.placement=$pl' \
   "$MANIFEST" > "$tmp" 2>/dev/null; then mv "$tmp" "$MANIFEST"; else rm -f "$tmp"; fi

probs=""
[ "$header" = true ]   || probs="$probs missing header block (/** …CBRD-XXXXX… */);"
[ "$evaluate" = true ] || probs="$probs missing evaluate 'Case N' label;"
[ "$cleanup" = true ]  || probs="$probs missing DROP TABLE IF EXISTS before CREATE TABLE;"
[ "$english" = true ]  || probs="$probs non-English text in comments (comments must be English);"
[ "$header_scope" = true ] || probs="$probs header talks to the pipeline instead of describing the test — move stage instructions to the report, reviewer constraints to the PR Remarks, and run-validity preconditions to verify.preconditions;"
[ "$header_size" = true ]  || probs="$probs header is $hlines lines (max 20) — compress the wording, don't drop coverage items;"
[ "$placement" = false ] && probs="$probs wrong tree: a bug fix (Correct Error) belongs in sql/_13_issues/_{yy}_{1|2}h/cases/ regardless of its version fields, not in a release dir (create the half-year dir if it does not exist yet) — see create-sql's directory convention;"
[ "$placement" = null ]  && probs="$probs placement unverifiable: record select.issue_type in the manifest during Select, so the tree can be checked against the issue type;"
[ -z "$probs" ] || jq -n --arg f "$FILE" --arg p "$probs" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:("[Stage2 lint] "+$f+" convention violations:"+$p+" (recorded in manifest.lint — the submit gate will block)")}}'
exit 0
