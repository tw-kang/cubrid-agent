# Stage 2 hard gates (hooks)

tc-author 파이프라인의 필수 품질 게이트를 Claude Code hook으로 **강제**한다. 스킬·CLAUDE.md는 '요청'이라 우회 가능 → hook은 '보장'.

**신뢰 모델**: 신뢰된 팀원의 **실수 방지 가드레일**이지 적대적 우회 방지가 아니다. manifest는 파이프라인이 기록하고 hook이 검사 — 고의 조작은 못 막지만 게이트를 깜빡 건너뛰는 것은 막는다. (적대적 강제는 Stage 3에서 CTP 산출물 직접 검증으로.)

## hook 3종 (플러그인 `hooks/hooks.json` 등록)

| hook | 이벤트 | 트리거 | 동작 |
|---|---|---|---|
| `gate-pr-submit.sh` | PreToolUse · Bash | `gh pr create … cubrid-testcases` | 브랜치 `tc/cbrd-XXXXX` → manifest 게이트 검사 → 미충족 시 **제출 차단(deny, exit 2)** |
| `lint-sql-tc.sh` | PostToolUse · Write\|Edit | `*/cases/cbrd_*.sql` | 기계적 컨벤션 린트 → `manifest.lint` 갱신(우회불가) + 위반 경고(비차단) |
| `gate-stop.sh` | Stop | (항상) | 미완·미제출 manifest 리마인드(비차단, exit 0) |

이 hook들은 **대상 명령/파일이 아니면 즉시 통과**(cubrid-agent 자체 커밋·PR·일반 파일 편집엔 개입 안 함).

## run manifest

- 위치: **`$HOME/.cubrid-agent/<CBRD-XXXXX>/manifest.json`** (프로젝트 디렉토리 무관 — $HOME 런타임 표준).
- 작성: **tc-author 오케스트레이터가 각 단계 결과를 기록**. 단 `lint.{header,evaluate,cleanup,english_comments}`는 `lint-sql-tc.sh`가 갱신(우회불가), `lint.answer_not_handwritten`은 provenance라 오케스트레이터가 기록.
- 스키마 예시: [manifest.example.json](../scripts/manifest.example.json).

## 제출 게이트 통과 조건 (gate-pr-submit)

전부 참이어야 `gh pr create` 통과:
- `verify.determinism.all_pass == true`
- `verify.fail_to_pass.status == "confirmed"` **또는** (`"best_effort"` **&&** `review.failpass_approved == true` **&&** `verify.fail_to_pass.note` 존재)
- `review.verdict == "PASS"`
- `verify.cci.checked == true` (CCI 교차 수행 — 기본 sql(JDBC) 출력과 다르면 `.answer_cci`)
- `lint.{header,evaluate,cleanup,answer_not_handwritten,english_comments}` 전부 true

## 로컬 확인 (세션에 걸지 않고 스크립트만 시험)

`HOME`을 임시 디렉토리로 바꿔 실제 manifest를 건드리지 않고 시험한다:
```bash
SM=$(mktemp -d)
# 미충족(manifest 없음) → deny(exit 2)
echo '{"tool_input":{"command":"gh pr create --repo CUBRID/cubrid-testcases --head tw-kang:tc/cbrd-99999 --draft"}}' \
  | HOME="$SM" bash scripts/gate-pr-submit.sh; echo "exit=$?"
# 비대상(cubrid-agent 자체) → 통과(exit 0)
echo '{"tool_input":{"command":"gh pr create --repo tw-kang/cubrid-agent"}}' \
  | HOME="$SM" bash scripts/gate-pr-submit.sh; echo "exit=$?"
rm -rf "$SM"
```
exit 2 = 차단(+deny JSON), exit 0 = 통과.
