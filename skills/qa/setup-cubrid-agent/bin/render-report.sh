#!/bin/bash
# Render the factual half of an author-testcase run report from the manifest, leaving the narrative
# for the human. Installed to ~/.cubrid-agent/bin/ by /setup-cubrid-agent.
#
# Why this is a script (DP6): the rehearsal's two report writes cost ~7.9k output tokens, and output
# tokens are what turn time actually tracks (measured correlation +0.88 against turn duration). Most
# of that text was facts the manifest already held — build, determinism, lint flags, paths — retyped
# in prose. Retyping is also where numbers drift: a hand-counted case total already contradicted the
# .sql once in a PR body (#3041, "8 cases" against 7).
#
# It also settles the one claim the skill warns about in capitals: "before you write that the TC is on
# the branch, prove it path-scoped". A script can simply run that git command every time.
#
# Usage: render-report.sh CBRD-XXXXX [--force]
set -u

USAGE='render-report.sh CBRD-XXXXX [--force]'
KEY=""; FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --force)   FORCE=1; shift ;;
    -h|--help) printf '%s\n' "$USAGE"; exit 0 ;;
    -*)        printf 'render-report: unknown option: %s\n%s\n  If that is a documented flag, this installed copy is stale (the plugin updated, ~/.cubrid-agent/bin did not) — run /setup-cubrid-agent to refresh it.\n' "$1" "$USAGE" >&2; exit 1 ;;
    *)         KEY=$(printf '%s' "$1" | grep -oiE '[A-Z]+-[0-9]+' | head -1 | tr '[:lower:]' '[:upper:]'); shift ;;
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

# shellcheck disable=SC1090
[ -f "$HOME/.cubrid-agent/env.sh" ] && . "$HOME/.cubrid-agent/env.sh"
TC=${CUBRID_TESTCASES:-$HOME/cubrid-testcases}

m() { jq -r "$1 // \"\"" "$MANIFEST" 2>/dev/null; }
u() { v=$(m "$1"); [ -n "$v" ] && printf '%s' "$v" || printf '미기록'; }

TCPATH=$(m '.author.path')
BRANCH=$(m '.author.branch'); [ -n "$BRANCH" ] || BRANCH="tc/$(printf '%s' "$KEY" | tr '[:upper:]' '[:lower:]')"

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
  _dir=$(dirname "$(dirname "$TCPATH")")   # sql/<tree>/<key>/cases/x.sql -> sql/<tree>/<key>
  _files=$(git -C "$TC" ls-tree -r --name-only "$BRANCH" -- "$_dir" 2>/dev/null)
  if [ -n "$_files" ]; then
    COMMITTED="커밋됨 — \`$BRANCH\`에 $(printf '%s\n' "$_files" | grep -c .)개 파일"
  else
    COMMITTED="**커밋되지 않았다** — \`git ls-tree -r $BRANCH -- $_dir\`가 비어 있다"
  fi
fi

{
  printf '# %s — author-testcase 실행 리포트\n\n' "$KEY"
  printf '<!-- 사실 부분은 render-report.sh 가 manifest·.sql·git 에서 만들었다. 숫자를 손으로 고치지 말고,\n'
  printf '     틀렸으면 manifest 를 고치고 --force 로 다시 만들어라. 서술(TODO)만 직접 쓴다. -->\n\n'

  printf '## Select\n\n'
  printf -- '- 이슈 타입: %s · QA Scenario: %s · Planned version: %s\n' "$(u '.select.issue_type')" "$(u '.select.qa_scenario')" "$(u '.select.planned_version')"
  # Queue basis: the manifest's frozen copy first, else the shared queue file — but only if that file
  # still lists THIS key, since select-queue.sh overwrites it on every build and a stale queue would
  # otherwise be cited as this run's basis. The fallback exists because the manifest copy is written
  # only for the head candidate, and the `checks_incomplete` line is the one a reader must not lose:
  # it says the already-processed screen was partial.
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
