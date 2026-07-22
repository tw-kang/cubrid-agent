#!/bin/bash
# Stage 2 hard gate — block TC PR submission until the run manifest confirms every gate.
# Event: PreToolUse / Bash. Manifest: $HOME/.cubrid-agent/<CBRD-XXXXX>/manifest.json (written by tc-author).
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
[ -n "$KEY" ] || deny "TC PR 제출 게이트: 명령에서 tc/cbrd-XXXXX 브랜치를 못 찾음(--head tw-kang:tc/cbrd-XXXXX 형식 필요)."

MANIFEST="$HOME/.cubrid-agent/$KEY/manifest.json"
[ -f "$MANIFEST" ] || deny "TC PR 제출 게이트: $KEY manifest 없음($MANIFEST). tc-author가 게이트 결과를 기록해야 제출 가능."

det=$(jq -r '.verify.determinism.all_pass // false' "$MANIFEST")
ftp=$(jq -r '.verify.fail_to_pass.status // "missing"' "$MANIFEST")
note=$(jq -r '.verify.fail_to_pass.note // ""' "$MANIFEST")
appr=$(jq -r '.review.failpass_approved // false' "$MANIFEST")
verdict=$(jq -r '.review.verdict // "missing"' "$MANIFEST")
cci=$(jq -r '.verify.cci.checked // false' "$MANIFEST")
lint=$(jq -r '[.lint.header,.lint.evaluate,.lint.cleanup,.lint.answer_not_handwritten,.lint.english_comments]|all' "$MANIFEST" 2>/dev/null)

p=""
[ "$det" = true ] || p="$p\n- 결정성 미확인(verify.determinism.all_pass≠true)"
if [ "$ftp" = confirmed ] || { [ "$ftp" = best_effort ] && [ "$appr" = true ] && [ -n "$note" ]; }; then :; else
  p="$p\n- fail→pass 미충족(status=$ftp, approved=$appr, note=$([ -n "$note" ] && echo 있음 || echo 없음)) — confirmed 또는 best_effort+리뷰승인+note 필요"
fi
[ "$verdict" = PASS ] || p="$p\n- 리뷰 미통과(review.verdict=$verdict)"
[ "$cci" = true ] || p="$p\n- CCI 교차 미수행(verify.cci.checked≠true) — sql_by_cci로 교차, 기본 sql(JDBC) 출력과 다르면 .answer_cci"
[ "$lint" = true ] || p="$p\n- 컨벤션 린트 미충족(lint.* 중 false — PostToolUse lint hook 참고)"

[ -z "$p" ] || deny "$(printf 'TC PR 제출 게이트: %s 미충족:%b' "$KEY" "$p")"
exit 0
