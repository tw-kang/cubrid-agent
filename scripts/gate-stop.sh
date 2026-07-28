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
  { [ "$det" != true ] || [ "$verdict" != PASS ]; } && pending="$pending $key"
done
[ -n "$pending" ] && jq -n --arg p "$pending" \
  '{hookSpecificOutput:{hookEventName:"Stop",additionalContext:("[Stage2] Incomplete TC manifest(s) (gates not passed):"+$p+" — finish passing the remaining determinism/review gates before submitting.")}}'
exit 0
