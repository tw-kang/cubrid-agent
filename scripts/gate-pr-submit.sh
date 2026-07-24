#!/bin/bash
# Stage 2 hard gate — block TC PR submission until the run manifest confirms every gate.
# Event: PreToolUse / Bash. Manifest: $HOME/.cubrid-agent/<CBRD-XXXXX>/manifest.json (written by author-testcase).
# Trusted-teammate guardrail: catches a skipped gate, not adversarial bypass.
set -u

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Gate only TC PR creation against cubrid-testcases; leave every other command alone.
printf '%s' "$COMMAND" | grep -qE 'gh[[:space:]]+pr[[:space:]]+create' || exit 0
printf '%s' "$COMMAND" | grep -q 'cubrid-testcases' || exit 0

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' >&2
  exit 2
}

KEY=$(printf '%s' "$COMMAND" | grep -oiE 'tc/cbrd-[0-9]+' | head -1 | grep -oiE 'cbrd-[0-9]+' | tr '[:lower:]' '[:upper:]')
[ -n "$KEY" ] || deny "TC PR submission gate: could not find a tc/cbrd-XXXXX branch in the command (expects the --head <your-fork>:tc/cbrd-XXXXX form)."

MANIFEST="$HOME/.cubrid-agent/$KEY/manifest.json"
[ -f "$MANIFEST" ] || deny "TC PR submission gate: no manifest for $KEY ($MANIFEST). author-testcase must record the gate results before submission is allowed."

det=$(jq -r '.verify.determinism.all_pass // false' "$MANIFEST")
ftp=$(jq -r '.verify.fail_to_pass.status // "missing"' "$MANIFEST")
note=$(jq -r '.verify.fail_to_pass.note // ""' "$MANIFEST")
appr=$(jq -r '.review.failpass_approved // false' "$MANIFEST")
verdict=$(jq -r '.review.verdict // "missing"' "$MANIFEST")
cci=$(jq -r '.verify.cci.checked // false' "$MANIFEST")
lint=$(jq -r '[.lint.header,.lint.evaluate,.lint.cleanup,.lint.answer_not_handwritten,.lint.english_comments]|all' "$MANIFEST" 2>/dev/null)

p=""
[ "$det" = true ] || p="$p\n- determinism not confirmed (verify.determinism.all_pass≠true)"
if [ "$ftp" = confirmed ] || { [ "$ftp" = best_effort ] && [ "$appr" = true ] && [ -n "$note" ]; }; then :; else
  p="$p\n- fail→pass not satisfied (status=$ftp, approved=$appr, note=$([ -n "$note" ] && echo present || echo absent)) — needs confirmed, or best_effort + review approval + note"
fi
[ "$verdict" = PASS ] || p="$p\n- review not passed (review.verdict=$verdict)"
[ "$cci" = true ] || p="$p\n- CCI cross-check not run (verify.cci.checked≠true) — cross-check with sql_by_cci; if it differs from the default sql (JDBC) output, add .answer_cci"
[ "$lint" = true ] || p="$p\n- convention lint not satisfied (some lint.* is false — see the PostToolUse lint hook)"

[ -z "$p" ] || deny "$(printf 'TC PR submission gate: %s not satisfied:%b' "$KEY" "$p")"
exit 0
