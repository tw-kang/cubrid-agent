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

# Record into manifest.lint (create skeleton if absent).
MDIR="$HOME/.cubrid-agent/$KEY"
MANIFEST="$MDIR/manifest.json"
mkdir -p "$MDIR"
[ -f "$MANIFEST" ] || printf '{}' > "$MANIFEST"
tmp=$(mktemp)
if jq --arg k "$KEY" --argjson h "$header" --argjson e "$evaluate" --argjson c "$cleanup" --argjson en "$english" \
   '.issue=(.issue//$k) | .lint.header=$h | .lint.evaluate=$e | .lint.cleanup=$c | .lint.english_comments=$en' \
   "$MANIFEST" > "$tmp" 2>/dev/null; then mv "$tmp" "$MANIFEST"; else rm -f "$tmp"; fi

probs=""
[ "$header" = true ]   || probs="$probs missing header block (/** …CBRD-XXXXX… */);"
[ "$evaluate" = true ] || probs="$probs missing evaluate 'Case N' label;"
[ "$cleanup" = true ]  || probs="$probs missing DROP TABLE IF EXISTS before CREATE TABLE;"
[ "$english" = true ]  || probs="$probs non-English text in comments (comments must be English);"
[ -z "$probs" ] || jq -n --arg f "$FILE" --arg p "$probs" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:("[Stage2 lint] "+$f+" convention violations:"+$p+" (recorded in manifest.lint — the submit gate will block)")}}'
exit 0
