# resolve-gate — 설계 v0 (cubrid-agent)

Handover→Resolved("Accept the fix") 전이를 맡는 **평가형 게이트**. 개발자가 인계한 fix를 QA가 받기 전, **QA-readiness(테스트 플랜 작성 가능성)** 를 심사해 accept/reject를 권고한다. 용어·초점은 [CONTEXT.md](./CONTEXT.md).

## 범위 (PoC)

- **한다**: Handover 이슈를 읽고 "이 내용(특히 description)으로 QA가 테스트 플랜을 짤 수 있는가"를 판정 → 읽기전용 게이트 리포트.
- **안 한다**: Jira 전이·코멘트 쓰기(사람이), fix 실행 검증(repro 재실행), 로컬 CTP, TC 작성.

## 확정 결정 (2026-07 grilling)

- **D1 초점 = test-plannability**: 이슈 내용만으로 테스트 플랜을 작성 가능한지가 중점. **fix가 실제로 동작하는지(실행검증)는 범위 밖**(추후 옵션).
- **D2 출력 = 읽기전용 게이트 리포트/권고**: accept/reject + 사유. Jira 전이는 사람이 수행(S4: Jira 쓰기=Stage 3).
- **D3 검사 2계층**: **차단**=test-plannability(C0~C2), **경고**=핸드오버 hygiene(C3/C5/C6). (근거: dry-run에서 실제 Handover 3건 모두 Fixed version·QA Scenario 미기입 — 이를 차단하면 전부 탈락하므로 경고로.)
- **D4 로컬 CTP 불요**: fix를 실행하지 않으므로 tc-author보다 가벼운 read-only 에이전트.

## 검사 기준

**차단(pass/fail 핵심) — test-plannability**
- **C1 Repro 존재·자기완결**: 재현 절차/스크립트가 있고, 빠진 스키마·데이터·오타 없이 그대로 실행 가능.
- **C2 Expected/Actual 명시**: fix 후 기대 동작 + fix 전 버그 동작.
- **C0 종합**: description만으로 QA가 테스트 플랜을 짤 수 있는가(dev-process p17 취지).

**경고(리포트에 표시) — 핸드오버 hygiene(p18)**
- **C3 Fixed version**(Planned 대비 머지 version) · **C5 QA Scenario**(Required/Not Required+사유) · **C6 Need Manual**(필요 시 CUBRIDMAN 링크) · **C4 변경 스펙/설정 반영**.

## 파이프라인

1. **Select** — `status=Handover` 풀 조회(cubrid-jira jql). QA Assignee는 이 시점 미설정 → 필터 기준은 열린 질문(§리스크).
2. **검사** — 각 이슈의 description·comment·fields를 읽어 C0~C6 판정. merge diff(cubrid repo)는 스펙 변경 이해·description 대조에 참고.
3. **Gate report** — 이슈별 `READY`(accept 권고) / `NOT-READY`(reject + 빠진 항목 체크리스트). 읽기전용.

## 재료

- **cubrid-jira**: 이슈 description·comment·필드(Fixed version/QA Scenario 등). 단일진실원천.
- **cubrid repo**: fix merge diff/PR(스펙 변경 이해, description 대조용 참고).
- **gh**: PR 머지 여부 확인(선택).
- 로컬 CTP·CUBRID **불요**.

## dry-run 근거 (2026-07, 실제 Handover 3건)

| 이슈 | C0~C2 | 판정 |
|---|---|---|
| CBRD-27056 (CAS numeric) | 자기완결 SELECT repro + Expected/Actual 명시 | **READY** (+ Fixed ver·QA Scenario 미기입 경고) |
| CBRD-27052 (core 회귀) | **repro 없음**(스택트레이스만) | **NOT-READY** — 반려: 재현 절차 부재 |
| CBRD-26909 (loaddb) | repro 있으나 **오타로 미실행** | **NOT-READY** — 반려: repro 자기완결 X |

→ 기준이 실제 판정을 정확히 냄. tc-author가 그 재료로 TC를 못 짜는 케이스를 미리 거른다.

## tc-author와의 관계

resolve-gate의 `READY` = tc-author Select의 입력 품질 보장. tc-author의 Ground(이슈→TC 재료 추출)가 성공할 조건을 resolve-gate가 앞단에서 판정한다. 두 에이전트의 조인 키는 이슈 키(`CBRD-XXXXX`).

## 리스크 / 열린 질문

- **Select 필터**: Handover 시점 QA Assignee 미설정 → 무엇으로 대상을 좁힐지(planned=guava 전체 / component / reporter=QA / 전 카테고리 vs SQL 계열).
- **hygiene 처리**: C3/C5/C6를 경고로 두되, 언젠가 차단으로 승격할지.
- **반려 산출물**: NOT-READY 시 Jira 코멘트 초안을 자동 작성할지(읽기전용이라 사람이 게시).
- **판정 주관성**: test-plannability는 정성 판단 → fresh-context 리뷰/근거 패킷으로 보강(tc-author Review 방식 차용).
- **fix 실행검증(범위 밖)**: 원하면 후속에 repro 재실행(fixed 빌드)으로 실제 해결까지 확인 — tc-author 로컬검증 인프라 재사용. CBRD-27052처럼 "fix가 실제론 미해결"인 케이스를 잡음.

## PoC 이후로 미룬 것

Jira 자동 전이·코멘트(Stage 3), fix 실행검증, 하드 게이트 hook(Stage 2 resolve-next류 오케스트레이션), 무인 스케줄.
