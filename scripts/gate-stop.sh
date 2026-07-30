#!/bin/bash
# Stage 2 stop reminder — if a run manifest exists whose gates are incomplete and that was not
# submitted, remind. The reminder is injected as `additionalContext`, and injected context
# re-invokes the model: `exit 0` alone does NOT prevent a stop loop — honouring `stop_hook_active`
# does. Without that guard the model wakes, stops, fires this hook again, and idles in a loop.
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
  key=$(jq -r '.issue // "?"' "$m" 2>/dev/null)
  # Sanctioned "cannot verify" terminal state (e.g. no fix-including build on this machine):
  # verify.status=blocked_* plus a note plus a written report. Those gates can never close, so
  # nagging is noise — see scripts/manifest.blocked.example.json.
  vstatus=$(jq -r '.verify.status // ""' "$m" 2>/dev/null)
  vnote=$(jq -r '.verify.note // ""' "$m" 2>/dev/null)
  case "$vstatus" in
    blocked_*) [ -n "$vnote" ] && [ -f "$DIR/reports/author-testcase/$key.md" ] && continue ;;
  esac
  det=$(jq -r '.verify.determinism.all_pass // false' "$m" 2>/dev/null)
  verdict=$(jq -r '.review.verdict // "?"' "$m" 2>/dev/null)
  if [ "$det" != true ] || [ "$verdict" != PASS ]; then
    # The lint hook counts every TC .sql write, so a run that keeps rewriting without closing a
    # gate is visible here rather than needing a round counter the agent maintains by hand.
    # Past the loop bound, name the sanctioned exit instead of nagging to keep going: a run that
    # cannot pass has one, and without it this reminder fires forever (CUBRIDQA-1487).
    _w=$(jq -r '.author.sql_writes // 0' "$m" 2>/dev/null)
    if [ "$_w" -ge 6 ] 2>/dev/null; then stuck="$stuck $key($_w writes)"; else pending="$pending $key"; fi
  fi
done
[ -n "$pending$stuck" ] && jq -n --arg p "$pending" --arg s "$stuck" \
  '{hookSpecificOutput:{hookEventName:"Stop",additionalContext:(
     (if $p != "" then "[Stage2] Incomplete TC manifest(s) (gates not passed):"+$p+" — finish passing the remaining determinism/review gates before submitting." else "" end)
   + (if $s != "" then (if $p != "" then " " else "" end)+"[Stage2] Past the loop bound with gates still open:"+$s+" — stop iterating and record the sanctioned terminal state instead: verify.status=\"blocked_review_unresolved\" + verify.note=<what still fails> + the written report. The branch keeps the work." else "" end))}}'
exit 0
