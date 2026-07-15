# 관점 카탈로그 (review perspectives) — L2 정본

**상태: 시드만 (마이닝 전).** 시드는 tc-author PoC 1·2호 교훈과 create/verify 스킬에서 왔다. **본문(빈도·대표 인용·신규 관점)은 리뷰 마이닝 세션이 채운다** — 아래 "마이닝 계약" 참조.

tc-reviewer L2와 tc-author Review lane이 공유하는 단일 정본. 스키마: 관점마다 `id / 이름 / 무엇을 잡나 / 검출 방법(정적·실행) / 기본 심각도 / 빈도(마이닝) / 대표 인용(마이닝)`.

## 시드 관점

| id | 이름 | 무엇을 잡나 | 검출 방법 | 기본 심각도 |
|---|---|---|---|---|
| P1 | answer 무결성 | `.answer`가 실행 산출물이 아니라 손으로 쓰였거나 stale | L3 실행 (Success/Fail) | blocker |
| P2 | 결정성 | ORDER BY 없는 다행 SELECT, 컬렉션의 Java 해시 렌더, 시간·locale·경로 의존 출력 | 정적 패턴 + L3 3회 반복 | blocker |
| P3 | fix 경로 커버리지 | 결정적 PASS라도 fix 코드 경로를 안 타면 무의미 (예: 데이터가 작아 병렬 대신 serial 경로) | 정적(트리거 조건 분석) + L3 plan/trace | major |
| P4 | 케이스 커버리지 | 이슈 재현 시나리오·fix 영향 범위 대비 케이스 누락, 경계값·부정 케이스 부재 | 정적 (이슈·fix diff 대조) | major |
| P5 | 격리·자기완결 | 공유 DB 연속 실행 오염 — DROP-before-CREATE 누락, cleanup 누락, `deallocate prepare` 누락, 세션 파라미터 미복원 | 정적 | major |
| P6 | 컨벤션 | 경로·네이밍(`_36_guava/cbrd_XXXXX`), 헤더 블록, `evaluate 'Case N'` 라벨, `--@queryplan`, autocommit·server-message 사용 관례 | 정적 (L1과 중복 허용) | minor |
| P7 | 기대값 정합성 | answer의 기대값 자체가 이슈의 "fix 후 동작"·SQL 스펙과 모순 | 정적 (이슈 대조) | blocker |
| P8 | 중복 | 같은 repro가 기존 TC에 이미 존재 (cbrd 번호가 아니라 테이블·쿼리 패턴 기준 검색) | 정적 (corpus 검색) | major |
| P9 | 러닝타임 | 데이터 크기·반복 수 과대로 회귀 스위트 시간 잠식 | L3 elapse 실측 | minor |
| P10 | 언어 | `.sql` 주석·커밋 메시지 영문 규칙 위반 | 정적 | minor |

## 마이닝 계약 (별도 세션 수행)

- **입력**: `work/tc-review-mining/` (gitignore, 2026-07-15 수집, 기간 2025-07-15~2026-07-15)
  - `chunk_0..4.jsonl` — 사람 라인 코멘트 600건(머지 PR 87건, PR 단위로 스레드 묶음, diff hunk 포함). **분류의 주 대상.**
  - `issue_human.jsonl` — PR 대화 코멘트 149건(보조 — 왕복 맥락).
  - `greptile.jsonl` — greptile 봇 라인 코멘트 118건(대조용 — 봇이 이미 잡는 관점 표시).
  - `merged_prs.json`, `pr_reviews.json`, `ds_*.json` — PR 메타·리뷰 제출 원본.
- **절차 제안**: 청크별 분류(시드 관점에 매핑, 안 맞으면 신규 관점 제안) → 집계(관점별 빈도·리뷰어 분포) → 대표 인용 3~5개 선별(PR 번호·리뷰어 표기) → 이 문서 갱신.
- **산출**: ① 위 표의 빈도·대표 인용 채움 + 신규 관점 행 추가, ② greptile 중복 여부 컬럼, ③ 리뷰 코멘트 언어 관례(한/영) 관측 → DESIGN 열린 질문 해소, ④ 판정 불일치 사례(사람 리뷰어끼리 상충된 지적)가 있으면 별도 기록.
- **품질 기준**: 인용은 원문 그대로(요약 금지), 관점 정의는 "무엇을 잡나"가 실패 사례로 서술될 것, 600건 전수 분류(샘플링 시 명시).
