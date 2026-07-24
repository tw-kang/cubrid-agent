#!/bin/bash
# Stage 2 stop reminder — if a run manifest exists but its gates are incomplete and it
# hasn't been submitted, remind. Non-blocking (exit 0) to avoid stop loops. 
set -u
DIR="$HOME/.cubrid-agent"
[ -d "$DIR" ] || exit 0
pending=""
for m in "$DIR"/CBRD-*/manifest.json; do
  [ -f "$m" ] || continue
  [ "$(jq -r '.submitted // false' "$m" 2>/dev/null)" = true ] && continue
  key=$(jq -r '.issue // "?"' "$m" 2>/dev/null)
  det=$(jq -r '.verify.determinism.all_pass // false' "$m" 2>/dev/null)
  verdict=$(jq -r '.review.verdict // "?"' "$m" 2>/dev/null)
  { [ "$det" != true ] || [ "$verdict" != PASS ]; } && pending="$pending $key"
done
[ -n "$pending" ] && jq -n --arg p "$pending" \
  '{hookSpecificOutput:{hookEventName:"Stop",additionalContext:("[Stage2] Incomplete TC manifest(s) (gates not passed):"+$p+" — finish passing the remaining determinism/review gates before submitting.")}}'
exit 0
