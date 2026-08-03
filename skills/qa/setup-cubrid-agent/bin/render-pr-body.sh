#!/bin/bash
# Render the TC PR body from the run manifest and the testcase itself, into the run directory.
#
# Why a script: the numbers in a PR body were being typed from memory, and reviewers caught it.
# On PR #3041 the body claimed "8개 케이스" against 7 in the file; on #3049 two P2 findings were
# both "this TC assumes X and the body never says so". Counting and copying are mechanical, so
# they belong here — the agent writes Purpose, Implementation and any judgment in Remarks, and
# nothing it writes has to be a number it counted by hand (DP6).
#
# Deliberately NOT new sections: the body keeps CUBRID/cubrid's three-heading shape
# (.github/PULL_REQUEST_TEMPLATE.md), and the generated facts land as Remarks bullets. A TC PR has
# no upstream template — CUBRID/cubrid-testcases ships none — so this is the whole definition.
#
# usage: render-pr-body.sh <KEY> [--run-dir DIR] [--force]
set -u

SELF_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
# shellcheck source=common.sh disable=SC1091
. "$SELF_DIR/common.sh" || { printf 'render-pr-body: common.sh is not next to me (%s) — re-run /setup-cubrid-agent.\n' "$SELF_DIR" >&2; exit 1; }

USAGE="usage: render-pr-body.sh <CBRD-XXXXX> [--run-dir DIR] [--force]"
KEY=""; RUN_DIR=""; FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --run-dir) RUN_DIR="${2:?$USAGE}"; shift 2 ;;
    --force)   FORCE=1; shift ;;
    -h|--help) printf '%s\n' "$USAGE"; exit 0 ;;
    -*)        reject_unknown "$USAGE" "$1" ;;
    *)         KEY=$(parse_issue_key "$1"); shift ;;
  esac
done
[ -n "$KEY" ] || { printf 'render-pr-body: need an issue key\n%s\n' "$USAGE" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "render-pr-body: jq is not installed" >&2; exit 1; }

: "${RUN_DIR:=$HOME/.cubrid-agent/$KEY}"
MANIFEST="$RUN_DIR/manifest.json"
OUT="$RUN_DIR/pr-body.md"
[ -f "$MANIFEST" ] || { printf 'render-pr-body: no manifest at %s — nothing to render from.\n' "$MANIFEST" >&2; exit 1; }
# The human-written sections are the reason not to clobber: re-running after Purpose is filled in
# would throw that away. --force is the explicit override.
if [ -s "$OUT" ] && [ "$FORCE" != 1 ]; then
  printf 'render-pr-body: %s already exists — edit it, or pass --force to regenerate (your Purpose/Implementation text would be lost).\n' "$OUT" >&2
  exit 1
fi

m() { jq -r "$1 // empty" "$MANIFEST" 2>/dev/null; }

SQLREL=$(m '.author.path')
# Read the .sql from wherever the branch is actually checked out (why: tc_root_for_branch in common.sh).
_br=$(m '.author.branch'); [ -n "$_br" ] || _br="tc/$(printf '%s' "$KEY" | tr '[:upper:]' '[:lower:]')"
_wt=$(tc_root_for_branch "$TC" "$_br"); [ -n "$_wt" ] && TC=$_wt
SQL="$TC/$SQLREL"

# Cases: the `evaluate 'Case N: …'` labels are what CTP echoes into the answer, so they are the
# case list by definition — and counting them is exactly what went wrong when a human did it.
NCASE="?"
if [ -n "$SQLREL" ] && [ -f "$SQL" ]; then
  NCASE=$(grep -coE "evaluate[[:space:]]+'[Cc]ase" "$SQL" 2>/dev/null || echo 0)
elif [ -z "$SQLREL" ]; then
  printf 'render-pr-body: warning — author.path is not recorded in the manifest, case count left as "?"\n' >&2
else
  printf 'render-pr-body: warning — testcase not found at %s, case count left as "?"\n' "$SQL" >&2
fi

NPRE=$(jq -r '(.verify.preconditions // []) | length' "$MANIFEST")
NPRE_UNVERIFIED=$(jq -r '[(.verify.preconditions // [])[] | select(.verified != true)] | length' "$MANIFEST")
UNVERIFIED_LIST=$(jq -r '[(.verify.preconditions // [])[] | select(.verified != true) | (.id // "?")] | join(", ")' "$MANIFEST")
# A precondition marked verified whose own evidence says "interpretation" / "추정" contradicts
# itself. That is a keyword flag, not a judgment: it is surfaced for the reviewer to argue with,
# because an unstated assumption is precisely what drew the P2 findings on #3049.
SOFT=$(jq -r '[(.verify.preconditions // [])[]
               | select(.verified == true)
               | select(((.evidence // "") + " " + (.cond // "")) | test("interpretation|not a verified|해석|추정"; "i"))
               | (.id // "?")] | join(", ")' "$MANIFEST")

VSTATUS=$(m '.verify.status')
DET_RUNS=$(jq -r '.verify.determinism | (.runs // .n // "?") | tostring' "$MANIFEST" 2>/dev/null)
DET_SESS=$(jq -r '.verify.determinism | (.sessions // "?") | tostring' "$MANIFEST" 2>/dev/null)
DET_PASS=$(m '.verify.determinism.all_pass')
CCI_CHECKED=$(m '.verify.cci.checked'); CCI_MATCH=$(m '.verify.cci.matches_jdbc')
ANSWER_GEN=$(m '.lint.answer_not_handwritten')
BUILD=$(m '.verify.fail_to_pass.fixed_build'); [ -n "$BUILD" ] || BUILD=$(m '.build')
FTP=$(m '.verify.fail_to_pass.status')
FTP_PRE=$(m '.verify.fail_to_pass.prefix_build')
FTP_NOTE=$(m '.verify.fail_to_pass.note')
ITYPE=$(m '.select.issue_type')

{
  printf '<http://jira.cubrid.org/browse/%s>\n\n' "$KEY"
  printf '### Purpose\n\n<!-- 배경과 문제: 무엇이 잘못되어 있었고 이 이슈가 무엇을 고쳤나. 사용자 관점 한글, 2~3줄. -->\nTODO\n\n'
  printf '### Implementation\n\n<!-- 이 TC가 무엇을 어떻게 검증하는가. 코드 설명이 아니라 검증하는 동작. 2~3줄. -->\nTODO\n\n'
  printf '### Remarks\n\n'

  # 1) shape of the testcase
  _pre="전제 ${NPRE}개"
  if [ "${NPRE:-0}" = 0 ]; then _pre="전제 기록 없음"
  elif [ "${NPRE_UNVERIFIED:-0}" != 0 ]; then _pre="$_pre 중 **${NPRE_UNVERIFIED}개 미검증**(${UNVERIFIED_LIST}) — 그만큼 결론이 유보됨"
  else _pre="$_pre 전부 verified"; fi
  [ -n "$SOFT" ] && _pre="$_pre. ${SOFT}는 evidence가 검증이 아니라 해석이라고 적고 있음"
  printf -- '- 케이스 %s개(`.sql` 헤더의 Coverage 참조), %s\n' "$NCASE" "$_pre"

  # 2) verification — a blocked run must say so rather than look unverified-by-omission
  case "$VSTATUS" in
    passed|"")
      _det="결정성 ${DET_RUNS}회"
      [ "$DET_SESS" != "?" ] && [ -n "$DET_SESS" ] && _det="$_det / ${DET_SESS}세션"
      [ "$DET_PASS" = true ] && _det="$_det 전부 PASS" || _det="$_det (**all_pass 아님**)"
      _cci="CCI 교차 미실행"
      [ "$CCI_CHECKED" = true ] && { [ "$CCI_MATCH" = true ] && _cci="CCI 교차 일치" || _cci="CCI 교차 **불일치 — .answer_cci 필요**"; }
      _ans='`.answer` 출처 미기록'
      [ "$ANSWER_GEN" = true ] && _ans='`.answer`는 CTP 출력에서 승격'
      printf -- '- 검증: `%s`, %s, %s, %s\n' "${BUILD:-빌드 미기록}" "$_det" "$_cci" "$_ans"
      ;;
    *)
      printf -- '- **검증이 완료되지 않았습니다** (`verify.status=%s`): %s\n' "$VSTATUS" "$(m '.verify.note')"
      ;;
  esac

  # 3) fail -> pass, with the long attribution note collapsed so the body stays short
  case "$FTP" in
    confirmed|best_effort)
      printf -- '- fail→pass **%s**' "$FTP"
      [ -n "$FTP_PRE" ] && printf ': pre-fix `%s` FAIL → `%s` PASS' "$FTP_PRE" "${BUILD:-fixed}"
      printf '\n'
      [ -n "$FTP_NOTE" ] && printf '\n<details><summary>fail→pass 상세·귀속 한계</summary>\n\n%s\n\n</details>\n' "$FTP_NOTE"
      ;;
    "") : ;;
    *)  printf -- '- fail→pass **%s** — 이 TC가 fix 전에 실패한다는 증거가 없습니다\n' "$FTP" ;;
  esac

  printf '\n<!-- 위 세 줄은 render-pr-body.sh 가 manifest 와 .sql 에서 만든 것이다. 숫자를 손으로 고치지 말고,\n'
  printf '     틀렸으면 manifest 를 고치고 --force 로 다시 만들어라. 판단(남은 한계·주의)은 아래에 직접 쓴다. -->\n'
  [ -n "$ITYPE" ] && printf '<!-- 배치: %s → %s -->\n' "$ITYPE" "${SQLREL:-경로 미기록}"
} > "$OUT"

printf '[pr-body] %s\n' "$OUT"
printf '  생성됨 : 케이스 수(%s), 검증 수치, fail→pass\n' "$NCASE"
printf '  써야 함 : ### Purpose, ### Implementation 의 TODO, 그리고 Remarks 의 남은 한계·주의\n'
printf '  제출    : gh pr create --body-file %s ...\n' "$OUT"
exit 0
