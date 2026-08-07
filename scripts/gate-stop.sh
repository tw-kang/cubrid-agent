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
# Speak only in a session that actually did TC work. This hook reads $HOME state rather than the
# working directory, so without this it fires in every project on this machine — the sessions that
# use this plugin and the ones that never touch a testcase alike. lint-sql-tc.sh and gate-pr-submit.sh
# do the marking, at the point where each has already confirmed the work is a TC.
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -n "$SID" ] && [ -f "$DIR/sessions/$SID" ] || exit 0
pending=""
stuck=""
for m in "$DIR"/CBRD-*/manifest.json; do
  [ -f "$m" ] || continue
  [ "$(jq -r '.submitted // false' "$m" 2>/dev/null)" = true ] && continue
  # An in-flight run is one that authored something. Grounding alone is not: ground-issue.sh writes a
  # manifest for every candidate a Select sweep screened, and those have no gate to close. A standalone
  # verify is not either — verify-sql runs against an existing testcase (verify-run.sh takes --tc-path
  # instead of reading .author.path), so its manifest carries `verify` and nothing that could ever
  # close. Counting those fired this reminder on every stop for seven days.
  jq -e 'has("author") or has("review")' "$m" >/dev/null 2>&1 || continue
  # The run directory is named for the issue, so it names the manifest even when the file does not.
  # Reporting "?" left the operator with no way to find which manifest was complaining.
  key=$(jq -r '.issue // empty' "$m" 2>/dev/null); [ -n "$key" ] || key=$(basename "$(dirname "$m")")
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
