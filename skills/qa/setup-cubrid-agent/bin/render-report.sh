#!/bin/bash
# Render the factual half of an author-testcase run report from the manifest, leaving the narrative
# for the human. Installed to ~/.cubrid-agent/bin/ by /setup-cubrid-agent.
#
# Everything here is a fact the manifest already holds; retyping it in prose is where numbers drift.
# It also proves path-scoped that the TC is really on the branch, rather than asserting it.
#
# Usage: render-report.sh CBRD-XXXXX [--force]
set -u

SELF_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
# shellcheck source=common.sh disable=SC1091
. "$SELF_DIR/common.sh" || { printf 'render-report: common.sh is not next to me (%s) — re-run /setup-cubrid-agent.\n' "$SELF_DIR" >&2; exit 1; }

USAGE='render-report.sh CBRD-XXXXX [--force]'
KEY=""; FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --force)   FORCE=1; shift ;;
    -h|--help) printf '%s\n' "$USAGE"; exit 0 ;;
    -*)        reject_unknown "$USAGE" "$1" ;;
    *)         KEY=$(parse_issue_key "$1"); shift ;;
  esac
done
[ -n "$KEY" ] || { printf 'render-report: need an issue key\n%s\n' "$USAGE" >&2; exit 1; }

RUN_DIR="$HOME/.cubrid-agent/$KEY"
MANIFEST="$RUN_DIR/manifest.json"
OUT_DIR="$HOME/.cubrid-agent/reports/author-testcase"
OUT="$OUT_DIR/$KEY.md"
[ -f "$MANIFEST" ] || { printf 'render-report: no manifest at %s — nothing to render from.\n' "$MANIFEST" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { printf 'render-report: jq is required.\n' >&2; exit 1; }
mkdir -p "$OUT_DIR"
if [ -f "$OUT" ] && [ "$FORCE" -ne 1 ]; then
  printf 'render-report: %s already exists — edit it, or pass --force to regenerate (your narrative would be lost).\n' "$OUT" >&2
  exit 1
fi

m() { jq -r "$1 // \"\"" "$MANIFEST" 2>/dev/null; }
u() { v=$(m "$1"); [ -n "$v" ] && printf '%s' "$v" || printf '미기록'; }

TCPATH=$(m '.author.path')
BRANCH=$(m '.author.branch'); [ -n "$BRANCH" ] || BRANCH="tc/$(printf '%s' "$KEY" | tr '[:upper:]' '[:lower:]')"
# Read from wherever the branch is actually checked out (why: tc_root_for_branch in common.sh).
_wt=$(tc_root_for_branch "$TC" "$BRANCH"); [ -n "$_wt" ] && TC=$_wt

# Case count from the .sql itself, never retyped.
NCASE='?'
if [ -n "$TCPATH" ]; then
  case "$TCPATH" in /*) SQL=$TCPATH ;; *) SQL="$TC/$TCPATH" ;; esac
  [ -f "$SQL" ] && NCASE=$(grep -cE "evaluate[[:space:]]+'Case " "$SQL" 2>/dev/null)
fi

# The claim the skill warns about: prove the work is committed, path-scoped, or say it is not.
COMMITTED="미확인 (TC 경로 또는 브랜치 미기록)"
# `-d "$TC/.git"` would be wrong: in a git worktree .git is a FILE, so the check would silently skip
# exactly where a reviewer runs. Ask git instead.
if [ -n "$TCPATH" ] && git -C "$TC" rev-parse --git-dir >/dev/null 2>&1; then
  # Two questions, because they fail differently. Membership: the directory bounds the search and the
  # key-derived filename decides what belongs (a per-issue directory exists in only one layout).
  # Existence: the `.sql` is asked for by name — an `.answer` committed beside an uncommitted `.sql`
  # is exactly what this proof exists to catch, and no filename count can see it.
  _rel=$TCPATH; case "$_rel" in "$TC"/*) _rel=${_rel#"$TC"/} ;; esac   # a pathspec must be repo-relative
  _dir=$(dirname "$(dirname "$_rel")")   # <tree>/cases/cbrd_x.sql -> <tree>, the parent of cases/ and answers/
  _base=$(printf '%s' "$KEY" | tr '[:upper:]-' '[:lower:]_')   # CBRD-25913 -> cbrd_25913
  if [ -n "$(git -C "$TC" ls-tree -r --name-only "$BRANCH" -- "$_rel" 2>/dev/null)" ]; then
    _files=$(git -C "$TC" ls-tree -r --name-only "$BRANCH" -- "$_dir" 2>/dev/null | grep -E "/${_base}[._]")
    COMMITTED="커밋됨 — \`$BRANCH\`에 $(printf '%s\n' "$_files" | grep -c .)개 파일"
  else
    COMMITTED="**커밋되지 않았다** — \`$_rel\` 가 \`$BRANCH\`에 없다"
  fi
fi

{
  printf '# %s — author-testcase 실행 리포트\n\n' "$KEY"
  printf '<!-- 사실 부분은 render-report.sh 가 manifest·.sql·git 에서 만들었다. 숫자를 손으로 고치지 말고,\n'
  printf '     틀렸으면 manifest 를 고치고 --force 로 다시 만들어라. 서술(TODO)만 직접 쓴다. -->\n\n'

  printf '## Select\n\n'
  printf -- '- 이슈 타입: %s · QA Scenario: %s · Planned version: %s\n' "$(u '.select.issue_type')" "$(u '.select.qa_scenario')" "$(u '.select.planned_version')"
  # Queue basis: the manifest's frozen copy first, else the shared queue file — but only if it still
  # lists THIS key, since select-queue.sh overwrites it on every build.
  QSRC="$MANIFEST"
  [ -n "$(m '.select.queue.summary')" ] || {
    _qf="$HOME/.cubrid-agent/select-queue.json"
    if [ -f "$_qf" ] && jq -e --arg k "$KEY" 'any(.queue[]?; .key == $k)' "$_qf" >/dev/null 2>&1; then
      QSRC=$(mktemp) && jq '{select:{queue:.}}' "$_qf" > "$QSRC" 2>/dev/null
    fi
  }
  _q=$(jq -r '.select.queue.summary // ""' "$QSRC" 2>/dev/null)
  [ -n "$_q" ] && printf -- '- 큐: %s\n' "$_q"
  jq -r '(.select.queue.dropped // [])[] | "  - 기계 제외: \(.key) — \(.reason)"' "$QSRC" 2>/dev/null
  jq -r '(.select.queue.checks_incomplete // [])[] | "  - **스크리닝 불완전**: \(.)"' "$QSRC" 2>/dev/null
  [ "$QSRC" != "$MANIFEST" ] && rm -f "$QSRC"
  _repro=$(m '.select.repro'); [ -n "$_repro" ] && printf -- '- repro 위치: %s\n' "$_repro"
  # A re-author over an existing PR is the one Select decision a reader must not have to infer.
  _ra=$(m '.select.reauthor_reason'); [ -n "$_ra" ] && printf -- '- **재작성**: 이미 PR이 있는 이슈를 다시 썼다 — %s\n' "$_ra"
  printf '\n## Ground\n\n'
  printf -- '- fix: %s\n' "$(u '.ground.fix_commit')"
  _fpr=$(m '.ground.fix_pr'); [ -n "$_fpr" ] && printf -- '- fix PR: %s\n' "$_fpr"
  _nr=$(jq -r '(.ground.read // []) | length' "$MANIFEST" 2>/dev/null)
  _nu=$(jq -r '(.ground.unread // []) | length' "$MANIFEST" 2>/dev/null)
  printf -- '- 첨부: 읽음 %s건 / 못 읽음 %s건\n' "${_nr:-0}" "${_nu:-0}"
  jq -r '(.ground.unread // [])[] | "  - 못 읽음: \(.name // "?") — \(.reason // "사유 미기록")"' "$MANIFEST" 2>/dev/null

  printf '\n## Author\n\n'
  printf -- '- TC: `%s`\n- 케이스 %s개\n- 커밋 상태: %s\n' "$(u '.author.path')" "$NCASE" "$COMMITTED"

  printf '\n## Verify\n\n'
  printf -- '- 빌드: `%s` · 상태: %s\n' "$(u '.verify.build')" "$(u '.verify.status')"
  _dr=$(m '.verify.determinism.runs'); _dp=$(m '.verify.determinism.all_pass')
  printf -- '- 결정성: %s회 반복, all_pass=%s\n' "${_dr:-?}" "${_dp:-미기록}"
  printf -- '- CCI 교차검증: checked=%s, matches_jdbc=%s\n' "$(u '.verify.cci.checked')" "$(u '.verify.cci.matches_jdbc')"
  # The debug run is the one a reader is most likely to assume happened; print it, including the marker,
  # because an assert is an engine finding that has to travel with its evidence.
  _dbg=$(jq -r 'if ((.verify.debug // {}) | has("result")) then .verify.debug.result else "" end' "$MANIFEST" 2>/dev/null)
  if [ -n "$_dbg" ]; then
    printf -- '- debug 빌드 실행: %s (checked=%s, build=%s)\n' "$_dbg" "$(u '.verify.debug.checked')" "$(u '.verify.debug.build')"
    _dm=$(m '.verify.debug.marker'); [ -n "$_dm" ] && printf -- '  - **assert/크래시 흔적**: `%s`\n' "$_dm"
    _dn=$(m '.verify.debug.note');   [ -n "$_dn" ] && printf -- '  - 메모: %s\n' "$_dn"
  else
    printf -- '- debug 빌드 실행: 미기록 — debug-check.sh 를 돌리지 않았다\n'
  fi
  printf -- '- fail→pass: %s\n' "$(u '.verify.fail_to_pass.status')"
  _fn=$(m '.verify.fail_to_pass.note'); [ -n "$_fn" ] && printf '\n<details><summary>fail→pass 상세·귀속 한계</summary>\n\n%s\n\n</details>\n\n' "$_fn"
  _rd=$(m '.verify.result_dir'); [ -n "$_rd" ] && printf -- '- 결과: `%s`\n' "$_rd"
  _df=$(m '.verify.diff'); [ -n "$_df" ] && printf -- '- **불일치 diff**: `%s`\n' "$_df"
  _np=$(jq -r '(.verify.preconditions // []) | length' "$MANIFEST" 2>/dev/null)
  if [ "${_np:-0}" -gt 0 ]; then
    printf -- '- 전제 %s건 (verified=false 는 결론이 유보된다는 뜻):\n' "$_np"
    jq -r '(.verify.preconditions // [])[] | "  - [\(if .verified then "v" else " " end)] \(.id // "?") — \(.cond // "")"' "$MANIFEST" 2>/dev/null
  fi

  printf '\n## Lint\n\n'
  jq -r '(.lint // {}) | to_entries | if length == 0 then "- 미기록" else (map("- \(.key): \(.value)") | .[]) end' "$MANIFEST" 2>/dev/null

  printf '\n## Review\n\n'
  printf -- '- verdict: %s\n' "$(u '.review.verdict')"
  printf -- '- fail→pass 승인: %s\n' "$(u '.review.failpass_approved')"

  printf '\n## Submit\n\n'
  _pr=$(m '.submit.pr'); [ -n "$_pr" ] || _pr=$(m '.submit.pr_url')
  if [ -n "$_pr" ]; then printf -- '- PR: %s\n' "$_pr"; else printf -- '- PR 미기록 — 제출하지 않았다면 그 사유를 아래에 쓴다\n'; fi

  printf '\n## 라운드 이력 (직접 쓴다)\n\n'
  printf '<!-- 라운드마다: 무엇이 지적됐고, 무엇을 고쳤고, 그래서 무엇이 달라졌나. manifest 에 없는 유일한 부분이다. -->\nTODO\n\n'
  printf '## 판단·남은 한계 (직접 쓴다)\n\n'
  printf '<!-- 이 실행이 무엇을 증명하고 무엇을 증명하지 못하는가. 위 수치를 다시 적지 말고 해석만 쓴다. -->\nTODO\n'
} > "$OUT"

printf '[report] %s\n' "$OUT"
printf '  생성됨 : Select·Ground·Author(케이스 %s, 커밋 상태 git 으로 확인)·Verify·Lint·Review·Submit\n' "$NCASE"
printf '  써야 함 : 라운드 이력, 판단·남은 한계 (TODO 2곳)\n'
