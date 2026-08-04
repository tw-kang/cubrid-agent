#!/bin/bash
# TC stop reminder — remind when a run manifest has incomplete gates and was not submitted.
# The reminder is injected as `additionalContext`, which re-invokes the model: `exit 0` alone does NOT
# prevent a stop loop, honouring `stop_hook_active` does.
set -u
INPUT=$(cat 2>/dev/null || true)
# Already inside a stop chain this hook started → stay silent, or the reminder never ends.
[ "$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)" = true ] && exit 0
DIR="$HOME/.cubrid-agent"
[ -d "$DIR" ] || exit 0
pending=""
stuck=""
for m in "$DIR"/CBRD-*/manifest.json; do
  [ -f "$m" ] || continue
  [ "$(jq -r '.submitted // false' "$m" 2>/dev/null)" = true ] && continue
  # Grounding alone is not an in-flight run: ground-issue.sh writes a manifest for every candidate a
  # Select sweep screened, and those have no gate to close.
  jq -e 'has("author") or has("verify") or has("review")' "$m" >/dev/null 2>&1 || continue
  key=$(jq -r '.issue // "?"' "$m" 2>/dev/null)
  # Sanctioned "cannot verify" terminal state: verify.status=blocked_* + note + report. Those gates
  # can never close (scripts/manifest.blocked.example.json).
  vstatus=$(jq -r '.verify.status // ""' "$m" 2>/dev/null)
  vnote=$(jq -r '.verify.note // ""' "$m" 2>/dev/null)
  case "$vstatus" in
    blocked_*) [ -n "$vnote" ] && [ -f "$DIR/reports/author-testcase/$key.md" ] && continue ;;
  esac
  det=$(jq -r '.verify.determinism.all_pass // false' "$m" 2>/dev/null)
  verdict=$(jq -r '.review.verdict // "?"' "$m" 2>/dev/null)
  if [ "$det" != true ] || [ "$verdict" != PASS ]; then
    # The lint hook counts every TC .sql write, so a rewrite loop is visible without a counter the
    # agent maintains by hand. Past the bound, name the sanctioned exit or this fires forever.
    _w=$(jq -r '.author.sql_writes // 0' "$m" 2>/dev/null)
    if [ "$_w" -ge 6 ] 2>/dev/null; then stuck="$stuck $key($_w writes)"; else pending="$pending $key"; fi
  fi
done
[ -n "$pending$stuck" ] && jq -n --arg p "$pending" --arg s "$stuck" \
  '{hookSpecificOutput:{hookEventName:"Stop",additionalContext:(
     (if $p != "" then "[TC gate] Incomplete TC manifest(s) (gates not passed):"+$p+" — finish passing the remaining determinism/review gates before submitting." else "" end)
   + (if $s != "" then (if $p != "" then " " else "" end)+"[TC gate] Past the loop bound with gates still open:"+$s+" — stop iterating and record the sanctioned terminal state instead: verify.status=\"blocked_review_unresolved\" + verify.note=<what still fails> + the written report. The branch keeps the work." else "" end))}}'
exit 0
