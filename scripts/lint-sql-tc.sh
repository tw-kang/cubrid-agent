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
# Length is deliberately NOT checked: measured on the corpus, human-authored cbrd_* headers reach
# 34 lines (median 7, p90 19), so length does not separate good from bad. This vocabulary does —
# it fires on 0 of 58 human-authored headers and on the two worst lines of the leak above.
header_scope=true
awk '/^\/\*\*/{f=1} f{print} /\*\//{if(f)exit}' "$FILE" \
  | grep -qEi '(Verify|Review) lane|MUST check|manifest|fail->pass|fail→pass|subagent|Draft PR|the report' \
  && header_scope=false

# Record into manifest.lint (create skeleton if absent).
MDIR="$HOME/.cubrid-agent/$KEY"
MANIFEST="$MDIR/manifest.json"
mkdir -p "$MDIR"
[ -f "$MANIFEST" ] || printf '{}' > "$MANIFEST"
tmp=$(mktemp)
if jq --arg k "$KEY" --argjson h "$header" --argjson e "$evaluate" --argjson c "$cleanup" \
      --argjson en "$english" --argjson hs "$header_scope" \
   '.issue=(.issue//$k) | .lint.header=$h | .lint.evaluate=$e | .lint.cleanup=$c | .lint.english_comments=$en | .lint.header_scope=$hs' \
   "$MANIFEST" > "$tmp" 2>/dev/null; then mv "$tmp" "$MANIFEST"; else rm -f "$tmp"; fi

probs=""
[ "$header" = true ]   || probs="$probs missing header block (/** …CBRD-XXXXX… */);"
[ "$evaluate" = true ] || probs="$probs missing evaluate 'Case N' label;"
[ "$cleanup" = true ]  || probs="$probs missing DROP TABLE IF EXISTS before CREATE TABLE;"
[ "$english" = true ]  || probs="$probs non-English text in comments (comments must be English);"
[ "$header_scope" = true ] || probs="$probs header talks to the pipeline instead of describing the test — move stage instructions to the report, reviewer constraints to the PR Remarks, and run-validity preconditions to verify.preconditions;"
[ -z "$probs" ] || jq -n --arg f "$FILE" --arg p "$probs" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:("[Stage2 lint] "+$f+" convention violations:"+$p+" (recorded in manifest.lint — the submit gate will block)")}}'
exit 0
