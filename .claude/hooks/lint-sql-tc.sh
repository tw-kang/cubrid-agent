#!/bin/bash
# Stage 2 convention lint — after a TC .sql write, lint mechanical rules and record them
# into the run manifest so the PreToolUse submit gate can't be silently bypassed.
# Event: PostToolUse / Write|Edit. Non-blocking (feedback only). stage2-design §3/§8 Q3.
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
MDIR="${CLAUDE_PROJECT_DIR:-$(pwd)}/work/$KEY"
MANIFEST="$MDIR/manifest.json"
mkdir -p "$MDIR"
[ -f "$MANIFEST" ] || printf '{}' > "$MANIFEST"
tmp=$(mktemp)
if jq --arg k "$KEY" --argjson h "$header" --argjson e "$evaluate" --argjson c "$cleanup" --argjson en "$english" \
   '.issue=(.issue//$k) | .lint.header=$h | .lint.evaluate=$e | .lint.cleanup=$c | .lint.english_comments=$en' \
   "$MANIFEST" > "$tmp" 2>/dev/null; then mv "$tmp" "$MANIFEST"; else rm -f "$tmp"; fi

probs=""
[ "$header" = true ]   || probs="$probs 헤더블록(/** …CBRD-XXXXX… */) 없음;"
[ "$evaluate" = true ] || probs="$probs evaluate 'Case N' 라벨 없음;"
[ "$cleanup" = true ]  || probs="$probs CREATE TABLE 앞 DROP TABLE IF EXISTS 없음;"
[ "$english" = true ]  || probs="$probs 주석에 비영문(영문이어야);"
[ -z "$probs" ] || jq -n --arg f "$FILE" --arg p "$probs" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:("[Stage2 lint] "+$f+" 컨벤션 위반:"+$p+" (manifest.lint 기록됨 — 제출 게이트가 차단)")}}'
exit 0
